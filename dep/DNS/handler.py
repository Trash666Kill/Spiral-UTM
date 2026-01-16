#!/usr/bin/env python3
import os
import sys
import re
import glob
import subprocess
import pwd
import grp
import secrets
import argparse
import shutil
from datetime import datetime

# ================= CONFIGURATION =================
NAMED_CONF_LOCAL = "/etc/bind/named.conf.local"
NAMED_CONF_OPTIONS = "/etc/bind/named.conf.options"
KEYS_DIR = "/etc/bind/keys"
BIND_USER = "bind"
BIND_GROUP = "bind"
# =================================================

def check_root():
    """Ensures the script is running with root privileges."""
    if os.geteuid() != 0:
        print("Error: This script must be run as root.")
        sys.exit(1)

def get_bind_uid_gid():
    """Retrieves the UID and GID for the bind user to set file permissions."""
    try:
        uid = pwd.getpwnam(BIND_USER).pw_uid
        gid = grp.getgrnam(BIND_GROUP).gr_gid
        return uid, gid
    except KeyError:
        print(f"Error: User or group '{BIND_USER}' not found on this system.")
        sys.exit(1)

def parse_arguments():
    parser = argparse.ArgumentParser(description='BIND9 DNSSEC, Records, and Forwarders Manager')
    
    # Mutually exclusive actions (cannot list and set at the same time)
    group = parser.add_mutually_exclusive_group()
    
    # Zone Actions
    group.add_argument('--list', action='store_true', 
                        help='List all A records configured in the zone.')
    group.add_argument('--rotate-keys', action='store_true',
                        help='Force DNSSEC key rotation (ZSK/KSK), update serial, and re-sign zone.')
    
    # Forwarder Actions
    group.add_argument('--list-fwd', action='store_true',
                        help='List currently configured DNS forwarders.')
    group.add_argument('--set-fwd', type=str,
                        help='Set new DNS forwarders (replaces existing). Format: "IP1,IP2"')

    # Record Management (Can be combined with default run)
    parser.add_argument('--record', action='append', 
                        help='Add or Update an A record. Format: "HOSTNAME,IP,COMMENT"')
    
    return parser.parse_args()

def reload_service():
    """Reloads BIND9 using rndc if active, or starts it using systemctl if stopped."""
    if subprocess.run(["systemctl", "is-active", "--quiet", "named"]).returncode == 0:
        print("Reloading BIND9 configuration (rndc reload)...")
        try:
            subprocess.run(["rndc", "reload"], check=True)
        except subprocess.CalledProcessError:
            print("Warning: 'rndc reload' failed. Attempting 'systemctl reload named'...")
            subprocess.run(["systemctl", "reload", "named"], check=False)
    else:
        print("Service is stopped. Starting BIND9...")
        subprocess.run(["systemctl", "enable", "--now", "named"], check=False)

# ================= FORWARDERS LOGIC =================

def manage_forwarders(action, new_ips_str=None):
    if not os.path.isfile(NAMED_CONF_OPTIONS):
        print(f"Error: Configuration file {NAMED_CONF_OPTIONS} not found.")
        sys.exit(1)

    with open(NAMED_CONF_OPTIONS, 'r') as f:
        content = f.read()

    # Regex to find the forwarders block: forwarders { ... };
    regex_fwd = re.compile(r'(forwarders\s*\{)([^}]+)(\};)', re.DOTALL)
    match = regex_fwd.search(content)

    if action == 'list':
        print(f"{'CURRENT FORWARDERS':<20}")
        print("-" * 30)
        if match:
            # Clean string: remove semicolons, newlines, and extra spaces
            raw_ips = match.group(2).replace(';', ' ').replace('\n', ' ')
            ips = [ip for ip in raw_ips.split() if ip.strip()]
            for ip in ips:
                print(f" -> {ip}")
        else:
            print("No 'forwarders' block found in configuration.")
        print("-" * 30)

    elif action == 'set':
        if not match:
            print("Error: 'forwarders { ... };' block not found in named.conf.options.")
            print("This script modifies existing configurations but does not create the structure from scratch.")
            sys.exit(1)
        
        # Process input list
        ip_list = [ip.strip() for ip in new_ips_str.split(',') if ip.strip()]
        if not ip_list:
            print("Error: No valid IPs provided.")
            sys.exit(1)

        # Format new content: " 1.1.1.1; 8.8.8.8; "
        new_inner_content = " " + "; ".join(ip_list) + "; "
        
        # Substitute in original content
        new_content = regex_fwd.sub(r'\1' + new_inner_content + r'\3', content)

        # Backup before writing
        shutil.copy(NAMED_CONF_OPTIONS, NAMED_CONF_OPTIONS + ".bak")
        
        with open(NAMED_CONF_OPTIONS, 'w') as f:
            f.write(new_content)
        
        print(f"Forwarders updated to: {', '.join(ip_list)}")
        
        # Validate syntax before reloading
        check = subprocess.run(["named-checkconf", NAMED_CONF_OPTIONS], capture_output=True)
        if check.returncode != 0:
            print("CRITICAL ERROR: The new configuration is invalid.")
            print(check.stderr.decode())
            print("Restoring backup...")
            shutil.move(NAMED_CONF_OPTIONS + ".bak", NAMED_CONF_OPTIONS)
            sys.exit(1)
            
        reload_service()

# ================= ZONE & DNSSEC LOGIC =================

def extract_zone_info():
    """Parses named.conf.local to find the domain name and zone file path."""
    if not os.path.isfile(NAMED_CONF_LOCAL):
        print(f"Error: {NAMED_CONF_LOCAL} not found.")
        sys.exit(1)
    
    with open(NAMED_CONF_LOCAL, 'r') as f:
        content = f.read()
        domain_match = re.search(r'zone\s+"([^"]+)"', content)
        file_match = re.search(r'file\s+"([^"]+)"', content)
        
        if domain_match and file_match:
            # Assumes the file in config points to the .signed version
            zone_file = file_match.group(1).replace(".signed", "")
            return domain_match.group(1).lower(), zone_file
            
    print("Error: Could not extract domain or zone file path from named.conf.local")
    sys.exit(1)

def list_zone_records(zone_file_path):
    print(f"{'HOSTNAME':<15} {'IP ADDRESS':<18} {'COMMENT'}")
    print("-" * 65)
    regex_record = re.compile(r'^(\S+)\s+IN\s+A\s+(\S+)\s*(;.*)?$')
    
    if not os.path.isfile(zone_file_path):
        print(f"Error: Zone file {zone_file_path} not found.")
        sys.exit(1)

    count = 0
    with open(zone_file_path, 'r') as f:
        for line in f:
            match = regex_record.match(line)
            if match:
                # Clean up comment (remove leading ; and spaces)
                comm = match.group(3).replace(';', '').strip() if match.group(3) else ""
                print(f"{match.group(1):<15} {match.group(2):<18} {comm}")
                count += 1
    if count == 0:
        print("No 'A' records found.")
    print("-" * 65)

def main():
    check_root()
    args = parse_arguments()
    bind_uid, bind_gid = get_bind_uid_gid()

    # --- FLOW 1: Forwarder Management ---
    if args.list_fwd:
        manage_forwarders('list')
        sys.exit(0)
        
    if args.set_fwd:
        manage_forwarders('set', args.set_fwd)
        sys.exit(0)

    # --- FLOW 2: Zone & DNSSEC Management ---
    
    domain, zone_file_path = extract_zone_info()

    if args.list:
        print(f"Listing records for zone: {domain}")
        list_zone_records(zone_file_path)
        sys.exit(0)

    # Prepare user records if provided
    user_records = []
    if args.record:
        for item in args.record:
            parts = item.split(',')
            if len(parts) < 3:
                print(f"Error: Invalid record format '{item}'. Must be: HOSTNAME,IP,COMMENT")
                sys.exit(1)
            # Rejoin comments in case they contain commas
            user_records.append({
                'host': parts[0].strip(), 
                'ip': parts[1].strip(), 
                'comment': ",".join(parts[2:]).strip()
            })

    print(f"Managing zone: {domain}")

    # 1. Key Management
    if not os.path.exists(KEYS_DIR):
        os.makedirs(KEYS_DIR)
        os.chown(KEYS_DIR, bind_uid, bind_gid)
        os.chmod(KEYS_DIR, 0o750)

    # Check existing keys
    existing_keys = glob.glob(os.path.join(KEYS_DIR, f"K{domain}.*.key"))
    
    # Generate keys if missing OR if rotation is requested
    if args.rotate_keys or len(existing_keys) < 2:
        if args.rotate_keys:
            print("Rotation requested. Removing old keys...")
            for f in glob.glob(os.path.join(KEYS_DIR, f"K{domain}.*")):
                os.remove(f)
        else:
            print("Keys missing. Generating new DNSSEC key pair...")

        os.chdir(KEYS_DIR)
        # Generate ZSK and KSK
        subprocess.run(["dnssec-keygen", "-a", "ECDSAP256SHA256", "-n", "ZONE", domain], stdout=subprocess.DEVNULL)
        subprocess.run(["dnssec-keygen", "-a", "ECDSAP256SHA256", "-n", "ZONE", "-f", "KSK", domain], stdout=subprocess.DEVNULL)
        
        # Fix permissions
        for f in os.listdir(KEYS_DIR):
            os.chown(os.path.join(KEYS_DIR, f), bind_uid, bind_gid)
            if f.endswith(".private"): os.chmod(os.path.join(KEYS_DIR, f), 0o600)
            else: os.chmod(os.path.join(KEYS_DIR, f), 0o644)

    # Identify current keys (Last modified assumed to be the active ones)
    key_files = sorted(glob.glob(os.path.join(KEYS_DIR, f"K{domain}.*.key")), key=os.path.getmtime)
    if len(key_files) < 2:
        print("Critical Error: Keys were not generated correctly.")
        sys.exit(1)

    zsk_key = os.path.basename(key_files[0]) # Assuming older one is ZSK (or doesn't matter if created same time)
    ksk_key = os.path.basename(key_files[-1]) # Assuming newer/last one is KSK

    # 2. Zone File Processing (Read -> Update Records -> Update Serial -> Write)
    if not os.path.isfile(zone_file_path):
        print(f"Error: Base zone file {zone_file_path} not found.")
        sys.exit(1)

    with open(zone_file_path, 'r') as f:
        lines = f.readlines()

    # Step A: Update/Append Records
    updated_lines = []
    processed_hosts = set()
    regex_rec = re.compile(r'^(\S+)\s+IN\s+A\s+(\S+)\s*(;.*)?$')

    # Update existing lines
    for line in lines:
        match = regex_rec.match(line)
        if match:
            current_host = match.group(1)
            # Check if this host needs updating
            update_data = next((r for r in user_records if r['host'] == current_host), None)
            
            if update_data:
                print(f"  [UPDATING] {current_host}: {update_data['ip']}")
                new_line = f"{current_host:<8} IN      A       {update_data['ip']:<15} ; {update_data['comment']}\n"
                updated_lines.append(new_line)
                processed_hosts.add(current_host)
            else:
                updated_lines.append(line)
        else:
            updated_lines.append(line)

    # Append new records
    for record in user_records:
        if record['host'] not in processed_hosts:
            print(f"  [CREATING] {record['host']}: {record['ip']}")
            new_line = f"{record['host']:<8} IN      A       {record['ip']:<15} ; {record['comment']}\n"
            
            # Insert before DNSSEC includes if possible
            inserted = False
            for i, line in enumerate(updated_lines):
                 if '$INCLUDE' in line or '; Include DNSSEC keys' in line:
                     updated_lines.insert(i, new_line)
                     inserted = True
                     break
            if not inserted:
                updated_lines.append(new_line)

    # Step B: Update Serial and Clean Includes
    final_lines = []
    serial_updated = False
    # Serial format: YYYYMMDDHH
    date_serial = int(datetime.utcnow().strftime('%Y%m%d%H'))

    for line in updated_lines:
        # Remove old key includes to prevent duplication
        if '$INCLUDE' in line and '.key' in line: continue
        if '; Include DNSSEC keys' in line: continue
        
        # Increment Serial
        serial_match = re.search(r'(\d+)\s*;\s*Serial', line, re.IGNORECASE)
        if serial_match and not serial_updated:
            current_serial = int(serial_match.group(1))
            new_serial = date_serial
            # Ensure serial always increments
            if new_serial <= current_serial:
                new_serial = current_serial + 1
            
            line = re.sub(r'\d+(\s*;\s*Serial)', f'{new_serial}\\1', line, count=1)
            serial_updated = True
            print(f"Serial updated: {current_serial} -> {new_serial}")
        
        final_lines.append(line)

    # Step C: Write file with Key Includes
    content = "".join(final_lines).rstrip()
    content += "\n\n; Include DNSSEC keys\n"
    content += f'$INCLUDE "{os.path.join(KEYS_DIR, zsk_key)}"\n'
    content += f'$INCLUDE "{os.path.join(KEYS_DIR, ksk_key)}"\n'

    with open(zone_file_path, 'w') as f:
        f.write(content)
    
    os.chown(zone_file_path, bind_uid, bind_gid)
    os.chmod(zone_file_path, 0o644)

    # 3. Sign Zone
    print("Signing zone with DNSSEC...")
    salt = secrets.token_hex(4).upper()
    try:
        subprocess.run([
            "dnssec-signzone", "-A", "-3", salt, 
            "-N", "INCREMENT", "-o", domain, 
            "-K", KEYS_DIR, zone_file_path
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        print(f"Error signing zone: {e.stderr.decode()}")
        sys.exit(1)

    # Set permissions on signed file
    signed_file = zone_file_path + ".signed"
    if os.path.exists(signed_file):
        os.chown(signed_file, bind_uid, bind_gid)
        os.chmod(signed_file, 0o644)

    # 4. Reload Service
    reload_service()

    print("Operation completed successfully.")

if __name__ == "__main__":
    main()