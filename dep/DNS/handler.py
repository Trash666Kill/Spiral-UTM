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
from datetime import datetime

# ================= CONFIGURAÇÕES =================
NAMED_CONF = "/etc/bind/named.conf.local"
KEYS_DIR = "/etc/bind/keys"
BIND_USER = "bind"
BIND_GROUP = "bind"
# =================================================

def check_root():
    if os.geteuid() != 0:
        print("Este script deve ser executado como root.")
        sys.exit(1)

def get_bind_uid_gid():
    try:
        uid = pwd.getpwnam(BIND_USER).pw_uid
        gid = grp.getgrnam(BIND_GROUP).gr_gid
        return uid, gid
    except KeyError:
        print(f"Erro: Usuário ou grupo '{BIND_USER}' não encontrado.")
        sys.exit(1)

def parse_arguments():
    parser = argparse.ArgumentParser(description='Gerenciador DNSSEC e Registros BIND9')
    
    # Grupo de ações exclusivas (não faz sentido listar e rotacionar ao mesmo tempo)
    group = parser.add_mutually_exclusive_group()
    
    group.add_argument('--list', action='store_true', 
                        help='Lista todos os registros do tipo A configurados na zona.')
    
    group.add_argument('--rotate-keys', action='store_true',
                        help='FORÇA a geração de novas chaves ZSK/KSK (rotação), atualiza serial e re-assina a zona.')

    # Argumento para manipulação de registros
    parser.add_argument('--record', action='append', 
                        help='Adicionar/Atualizar registro A. Formato: "hostname,ip,comentario"')
    
    return parser.parse_args()

def extract_zone_info():
    """Lê a configuração do BIND para descobrir o domínio e o arquivo de zona."""
    if not os.path.isfile(NAMED_CONF):
        print(f"Erro: {NAMED_CONF} não encontrado.")
        sys.exit(1)

    domain = None
    zone_file_path_signed = None

    with open(NAMED_CONF, 'r') as f:
        content = f.read()
        domain_match = re.search(r'zone\s+"([^"]+)"', content)
        file_match = re.search(r'file\s+"([^"]+)"', content)

        if domain_match: domain = domain_match.group(1).lower()
        if file_match: zone_file_path_signed = file_match.group(1)

    if not domain or not zone_file_path_signed:
        print("Erro: Não foi possível extrair domínio ou arquivo de zona do named.conf.local.")
        sys.exit(1)

    zone_file_path = zone_file_path_signed.replace(".signed", "")
    if not os.path.isfile(zone_file_path):
        print(f"Erro: Arquivo de zona base {zone_file_path} não existe.")
        sys.exit(1)

    return domain, zone_file_path

def list_records(zone_file_path):
    """Lista os registros A encontrados no arquivo de zona."""
    print(f"{'HOSTNAME':<15} {'IP ADDRESS':<18} {'COMENTÁRIO'}")
    print("-" * 60)
    
    regex_record = re.compile(r'^(\S+)\s+IN\s+A\s+(\S+)\s*(;.*)?$')
    
    count = 0
    with open(zone_file_path, 'r') as f:
        for line in f:
            match = regex_record.match(line)
            if match:
                host = match.group(1)
                ip = match.group(2)
                # Remove o ponto e vírgula inicial e espaços do comentário, se existir
                comment = match.group(3).replace(';', '').strip() if match.group(3) else ""
                print(f"{host:<15} {ip:<18} {comment}")
                count += 1
    
    if count == 0:
        print("Nenhum registro do tipo A encontrado ou formato não reconhecido.")
    print("-" * 60)

def process_zone_records(lines, new_records):
    """Manipula as linhas do arquivo para adicionar ou atualizar registros."""
    updated_lines = []
    processed_hosts = set()
    regex_record = re.compile(r'^(\S+)\s+IN\s+A\s+(\S+)\s*(;.*)?$')

    # 1. Atualização
    for line in lines:
        match = regex_record.match(line)
        if match:
            current_host = match.group(1)
            record_update = next((r for r in new_records if r['host'] == current_host), None)
            
            if record_update:
                print(f"  [ATUALIZANDO] {current_host}: {record_update['ip']}")
                new_line = f"{current_host:<8} IN      A       {record_update['ip']:<15} ; {record_update['comment']}\n"
                updated_lines.append(new_line)
                processed_hosts.add(current_host)
            else:
                updated_lines.append(line)
        else:
            updated_lines.append(line)

    # 2. Adição
    for record in new_records:
        if record['host'] not in processed_hosts:
            print(f"  [CRIANDO]     {record['host']}: {record['ip']}")
            new_line = f"{record['host']:<8} IN      A       {record['ip']:<15} ; {record['comment']}\n"
            
            inserted = False
            for i, line in enumerate(updated_lines):
                 if '$INCLUDE' in line or '; Include DNSSEC keys' in line:
                     updated_lines.insert(i, new_line)
                     inserted = True
                     break
            if not inserted:
                updated_lines.append(new_line)

    return updated_lines

def main():
    check_root()
    args = parse_arguments()
    bind_uid, bind_gid = get_bind_uid_gid()

    # 1. Obter informações da zona
    domain, zone_file_path = extract_zone_info()

    # 2. Modo LISTAGEM (Executa e sai)
    if args.list:
        print(f"Listando registros para a zona: {domain}")
        list_records(zone_file_path)
        sys.exit(0)

    print(f"Gerenciando zona: {domain}")

    # Processar inputs de novos registros
    user_records = []
    if args.record:
        for item in args.record:
            parts = item.split(',')
            if len(parts) < 3:
                print(f"Erro: O registro '{item}' está incompleto. Use: HOST,IP,COMENTARIO")
                sys.exit(1)
            user_records.append({
                'host': parts[0].strip(),
                'ip': parts[1].strip(),
                'comment': ",".join(parts[2:]).strip()
            })

    # 3. Gerenciamento de Chaves (Rotação ou Verificação)
    if not os.path.exists(KEYS_DIR):
        os.makedirs(KEYS_DIR)
        os.chown(KEYS_DIR, bind_uid, bind_gid)
        os.chmod(KEYS_DIR, 0o750)

    keys_exist = len(glob.glob(os.path.join(KEYS_DIR, f"K{domain}.*.key"))) >= 2
    
    # Se pediu rotação (--rotate-keys) OU não existem chaves, gera novas.
    if args.rotate_keys or not keys_exist:
        if args.rotate_keys:
            print("AVISO: Rotação de chaves solicitada via argumento.")
            # Remove chaves antigas
            for f in glob.glob(os.path.join(KEYS_DIR, f"K{domain}.*")):
                os.remove(f)
        else:
            print("Chaves não encontradas. Gerando par inicial...")

        os.chdir(KEYS_DIR)
        subprocess.run(["dnssec-keygen", "-a", "ECDSAP256SHA256", "-n", "ZONE", domain], stdout=subprocess.DEVNULL)
        subprocess.run(["dnssec-keygen", "-a", "ECDSAP256SHA256", "-n", "ZONE", "-f", "KSK", domain], stdout=subprocess.DEVNULL)
        
        for f in os.listdir(KEYS_DIR):
            os.chown(os.path.join(KEYS_DIR, f), bind_uid, bind_gid)
            
    # Identificar chaves atuais
    key_files = sorted(glob.glob(os.path.join(KEYS_DIR, f"K{domain}.*.key")), key=os.path.getmtime)
    if not key_files:
        print("Erro crítico: Nenhuma chave encontrada após geração.")
        sys.exit(1)
        
    zsk_key = os.path.basename(key_files[0])
    ksk_key = os.path.basename(key_files[-1])

    # 4. Manipulação do Arquivo de Zona
    with open(zone_file_path, 'r') as f:
        lines = f.readlines()

    # Se houver novos registros, processa
    if user_records:
        lines = process_zone_records(lines, user_records)

    # Atualizar Serial
    new_lines = []
    current_serial = 0
    serial_updated = False
    date_serial = int(datetime.utcnow().strftime('%Y%m%d%H'))

    for line in lines:
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
            print(f"Serial atualizado: {current_serial} -> {new_serial}")
        
        new_lines.append(line)

    # Inserir Includes das chaves
    content = "".join(new_lines).rstrip()
    content += "\n\n; Include DNSSEC keys\n"
    content += f'$INCLUDE "{os.path.join(KEYS_DIR, zsk_key)}"\n'
    content += f'$INCLUDE "{os.path.join(KEYS_DIR, ksk_key)}"\n'

    with open(zone_file_path, 'w') as f:
        f.write(content)
    
    os.chown(zone_file_path, bind_uid, bind_gid)
    os.chmod(zone_file_path, 0o644)

    # 5. Assinar Zona e Reload
    salt = secrets.token_hex(4).upper()
    print("Assinando zona...")
    try:
        subprocess.run([
            "dnssec-signzone", "-A", "-3", salt, 
            "-N", "INCREMENT", "-o", domain, 
            "-K", KEYS_DIR, zone_file_path
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        print(f"Erro ao assinar: {e.stderr.decode()}")
        sys.exit(1)

    signed_file = zone_file_path + ".signed"
    if os.path.exists(signed_file):
        os.chown(signed_file, bind_uid, bind_gid)
        os.chmod(signed_file, 0o644)

    if subprocess.run(["systemctl", "is-active", "--quiet", "named"]).returncode == 0:
        print("Recarregando BIND9...")
        subprocess.run(["rndc", "reload"], check=False)
    else:
        print("Iniciando BIND9...")
        subprocess.run(["systemctl", "enable", "--now", "named"], check=False)

    print("Operação concluída.")

if __name__ == "__main__":
    main()