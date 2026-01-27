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
    """Retrieves the UID and GID for the bind user."""
    try:
        uid = pwd.getpwnam(BIND_USER).pw_uid
        gid = grp.getgrnam(BIND_GROUP).gr_gid
        return uid, gid
    except KeyError:
        print(f"Error: User or group '{BIND_USER}' not found on this system.")
        sys.exit(1)

def parse_arguments():
    epilog_text = """EXAMPLES:
  1. List current forwarders:
     ./handler.py --list-fwd

  2. Set new forwarders (Use commas, NO spaces or slashes):
     ./handler.py --set-fwd "1.1.1.1,8.8.8.8"

  3. Add a new A record:
     ./handler.py --record "srv01,192.168.1.10,File Server"

  4. List zone records:
     ./handler.py --list

  5. Force key rotation (Maintenance):
     ./handler.py --rotate-keys
    """
    
    parser = argparse.ArgumentParser(
        description='BIND9 DNSSEC, Records, and Forwarders Manager',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=epilog_text
    )
    
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
                        help='Set new DNS forwarders. Format: "IP1,IP2"')

    # Record Management
    parser.add_argument('--record', action='append', 
                        help='Add or Update an A record. Format: "HOSTNAME,IP,COMMENT"')
    
    return parser.parse_args()

def restart_service():
    """Restarts BIND9 using systemctl (No reload, No RNDC)."""
    print("Restarting BIND9 service...")
    
    # Ensure service is enabled
    subprocess.run(["systemctl", "enable", "named"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Force restart
    result = subprocess.run(["systemctl", "restart", "named"], check=False)
    
    if result.returncode == 0:
        print("Success: Service restarted.")
    else:
        print("CRITICAL: Failed to restart BIND9 service.")
        sys.exit(1)

# ================= FORWARDERS LOGIC =================

def validate_ip_format(ip_string):
    """Validates the forwarder input string."""
    if '/' in ip_string:
        print(f"Error: Invalid character '/' detected in '{ip_string}'.")
        print("Hint: Use commas to separate IPs. Example: \"8.8.8.8,1.1.1.1\"")
        return False
    
    parts = ip_string.split(',')
    for part in parts:
        clean_part = part.strip()
        if not clean_part: continue
        if not re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$", clean_part):
            print(f"Error: '{clean_part}' does not look like a valid IP address.")
            return False
    return True

def manage_forwarders(action, new_ips_str=None):
    if not os.path.isfile(NAMED_CONF_OPTIONS):
        print(f"Error: Configuration file {NAMED_CONF_OPTIONS} not found.")
        sys.exit(1)

    with open(NAMED_CONF_OPTIONS, 'r') as f:
        content = f.read()

    regex_fwd = re.compile(r'(forwarders\s*\{)([^}]+)(\};)', re.DOTALL)
    match = regex_fwd.search(content)

    if action == 'list':
        print(f"{'CURRENT FORWARDERS':<20}")
        print("-" * 30)
        if match:
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
            sys.exit(1)
        
        if not validate_ip_format(new_ips_str):
            sys.exit(1)
        
        ip_list = [ip.strip() for ip in new_ips_str.split(',') if ip.strip()]
        if not ip_list:
            print("Error: No valid IPs provided.")
            sys.exit(1)

        new_inner_content = " " + "; ".join(ip_list) + "; "
        new_content = regex_fwd.sub(r'\1' + new_inner_content + r'\3', content)

        shutil.copy(NAMED_CONF_OPTIONS, NAMED_CONF_OPTIONS + ".bak")
        
        with open(NAMED_CONF_OPTIONS, 'w') as f:
            f.write(new_content)
        
        print(f"Forwarders configuration updated to: {', '.join(ip_list)}")
        
        check = subprocess.run(["named-checkconf", NAMED_CONF_OPTIONS], capture_output=True)
        if check.returncode != 0:
            print("CRITICAL ERROR: The new configuration is invalid.")
            print(check.stderr.decode())
            print("Restoring backup...")
            shutil.move(NAMED_CONF_OPTIONS + ".bak", NAMED_CONF_OPTIONS)
            sys.exit(1)
            
        restart_service()

# ================= ZONE & DNSSEC LOGIC =================

def extract_zone_info():
    if not os.path.isfile(NAMED_CONF_LOCAL):
        print(f"Error: {NAMED_CONF_LOCAL} not found.")
        sys.exit(1)
    
    with open(NAMED_CONF_LOCAL, 'r') as f:
        content = f.read()
        domain_match = re.search(r'zone\s+"([^"]+)"', content)
        file_match = re.search(r'file\s+"([^"]+)"', content)
        
        if domain_match and file_match:
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
                comm = match.group(3).replace(';', '').strip() if match.group(3) else ""
                print(f"{match.group(1):<15} {match.group(2):<18} {comm}")
                count += 1
    if count == 0:
        print("No 'A' records found.")
    print("-" * 65)

def check_keys_need_rotation(domain):
    """Check if keys exist and if DNSSEC signatures are expired."""
    existing_keys = glob.glob(os.path.join(KEYS_DIR, f"K{domain}.*.key"))
    
    # No keys? Need generation
    if len(existing_keys) < 2:
        return True, "Keys missing"
    
    # Check if signatures are expired by looking at the signed zone file
    domain, zone_file_path = extract_zone_info()
    signed_file = zone_file_path + ".signed"
    
    if not os.path.exists(signed_file):
        return True, "Signed zone file missing"
    
    # Check for expired signatures in logs or file
    try:
        result = subprocess.run(
            ["named-checkzone", domain, signed_file],
            capture_output=True,
            text=True
        )
        if "expired" in result.stderr.lower() or "expired" in result.stdout.lower():
            return True, "DNSSEC signatures expired"
    except:
        pass
    
    return False, "Keys are valid"

def ensure_dnssec_keys(domain, force_rotation=False):
    """Ensure DNSSEC keys exist and are valid. Rotate if needed or forced."""
    bind_uid, bind_gid = get_bind_uid_gid()
    
    if not os.path.exists(KEYS_DIR):
        os.makedirs(KEYS_DIR)
        os.chown(KEYS_DIR, bind_uid, bind_gid)
        os.chmod(KEYS_DIR, 0o750)
    
    needs_rotation, reason = check_keys_need_rotation(domain)
    
    if force_rotation:
        print("Notice: FORCED key rotation requested...")
        reason = "Manual rotation"
        needs_rotation = True
    elif needs_rotation:
        print(f"Notice: Key rotation needed: {reason}")
    
    if needs_rotation:
        # Remove old keys
        print("   Removing old keys...")
        for f in glob.glob(os.path.join(KEYS_DIR, f"K{domain}.*")):
            os.remove(f)
        
        # Generate new keys
        print("   Generating new DNSSEC key pair...")
        os.chdir(KEYS_DIR)
        subprocess.run(["dnssec-keygen", "-a", "ECDSAP256SHA256", "-n", "ZONE", domain], 
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["dnssec-keygen", "-a", "ECDSAP256SHA256", "-n", "ZONE", "-f", "KSK", domain], 
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        # Fix permissions
        for f in os.listdir(KEYS_DIR):
            os.chown(os.path.join(KEYS_DIR, f), bind_uid, bind_gid)
            if f.endswith(".private"): 
                os.chmod(os.path.join(KEYS_DIR, f), 0o600)
            else: 
                os.chmod(os.path.join(KEYS_DIR, f), 0o644)
        
        print("   Success: New keys generated.")
    
    # Get key files
    key_files = sorted(glob.glob(os.path.join(KEYS_DIR, f"K{domain}.*.key")), key=os.path.getmtime)
    if not key_files:
        print("Error: DNSSEC keys generation failed.")
        sys.exit(1)
    
    return os.path.basename(key_files[0]), os.path.basename(key_files[-1])

def update_zone_file(zone_file_path, user_records, zsk_key, ksk_key):
    """Update zone file with new records and DNSSEC keys."""
    bind_uid, bind_gid = get_bind_uid_gid()
    
    if not os.path.isfile(zone_file_path):
        print(f"Error: Zone file {zone_file_path} not found.")
        sys.exit(1)

    with open(zone_file_path, 'r') as f:
        lines = f.readlines()

    updated_lines = []
    processed_hosts = set()
    regex_rec = re.compile(r'^(\S+)\s+IN\s+A\s+(\S+)\s*(;.*)?$')

    # Update existing records or keep them
    for line in lines:
        match = regex_rec.match(line)
        if match:
            current_host = match.group(1)
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

    # Add new records
    for record in user_records:
        if record['host'] not in processed_hosts:
            print(f"  [CREATING] {record['host']}: {record['ip']}")
            new_line = f"{record['host']:<8} IN      A       {record['ip']:<15} ; {record['comment']}\n"
            inserted = False
            for i, line in enumerate(updated_lines):
                if '$INCLUDE' in line or '; Include DNSSEC keys' in line:
                    updated_lines.insert(i, new_line)
                    inserted = True
                    break
            if not inserted:
                updated_lines.append(new_line)

    # Update serial and prepare final content
    final_lines = []
    serial_updated = False
    date_serial = int(datetime.utcnow().strftime('%Y%m%d%H'))

    for line in updated_lines:
        if '$INCLUDE' in line and '.key' in line: continue
        if '; Include DNSSEC keys' in line: continue
        
        serial_match = re.search(r'(\d+)\s*;\s*Serial', line, re.IGNORECASE)
        if serial_match and not serial_updated:
            current_serial = int(serial_match.group(1))
            new_serial = date_serial
            if new_serial <= current_serial:
                new_serial = current_serial + 1
            line = re.sub(r'\d+(\s*;\s*Serial)', f'{new_serial}\\1', line, count=1)
            serial_updated = True
            print(f"   Serial updated: {current_serial} -> {new_serial}")
        
        final_lines.append(line)

    # Add DNSSEC keys
    content = "".join(final_lines).rstrip()
    content += "\n\n; Include DNSSEC keys\n"
    content += f'$INCLUDE "{os.path.join(KEYS_DIR, zsk_key)}"\n'
    content += f'$INCLUDE "{os.path.join(KEYS_DIR, ksk_key)}"\n'

    # Write updated zone file
    with open(zone_file_path, 'w') as f:
        f.write(content)
    
    os.chown(zone_file_path, bind_uid, bind_gid)
    os.chmod(zone_file_path, 0o644)

def sign_zone(domain, zone_file_path):
    """Sign the zone with DNSSEC."""
    bind_uid, bind_gid = get_bind_uid_gid()
    
    print("Signing zone with DNSSEC...")
    salt = secrets.token_hex(4).upper()
    try:
        subprocess.run([
            "dnssec-signzone", "-A", "-3", salt, 
            "-N", "INCREMENT", "-o", domain, 
            "-K", KEYS_DIR, zone_file_path
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        print("   Success: Zone signed.")
    except subprocess.CalledProcessError as e:
        print(f"Error signing zone: {e.stderr.decode()}")
        sys.exit(1)

    signed_file = zone_file_path + ".signed"
    if os.path.exists(signed_file):
        os.chown(signed_file, bind_uid, bind_gid)
        os.chmod(signed_file, 0o644)

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

    # --- FLOW 2: Zone Management ---
    domain, zone_file_path = extract_zone_info()

    if args.list:
        print(f"Listing records for zone: {domain}")
        list_zone_records(zone_file_path)
        sys.exit(0)

    # Parse user records
    user_records = []
    if args.record:
        for item in args.record:
            parts = item.split(',')
            if len(parts) < 3:
                print(f"Error: Invalid record format '{item}'. Must be: HOSTNAME,IP,COMMENT")
                sys.exit(1)
            user_records.append({
                'host': parts[0].strip(), 
                'ip': parts[1].strip(), 
                'comment': ",".join(parts[2:]).strip()
            })

    print(f"Managing zone: {domain}")

    # Ensure DNSSEC keys are valid (auto-rotate if expired)
    zsk_key, ksk_key = ensure_dnssec_keys(domain, force_rotation=args.rotate_keys)

    # Update zone file with records and keys
    if user_records or args.rotate_keys:
        update_zone_file(zone_file_path, user_records, zsk_key, ksk_key)
    
    # Always sign the zone when making changes
    sign_zone(domain, zone_file_path)
    
    # Restart BIND9
    restart_service()

    print("Operation completed successfully.")

if __name__ == "__main__":
    main()