#!/usr/bin/env python3

import sys
import os
import subprocess
import time

# - Description: Orquestra a execução dos scripts network.sh e firewall.sh
#                e reinicia serviços do sistema.
# - Garante que as tarefas sejam executadas em sequência.
# - Sai com um erro se algum script ou serviço falhar.
# - Para adicionar novas tarefas, crie uma nova função e adicione-a à
#   lista 'tasks_to_run' na função main.
#
#   Observação: Este script deve ser executado com privilégios de root,
#   assim como o script original, para modificar arquivos de sistema e
#   reiniciar serviços.

# --- Constantes ---

# Cores para o terminal
COLOR_YELLOW = "\033[33m"
COLOR_RED = "\033[31m"
COLOR_GREEN = "\033[32m"
COLOR_RESET = "\033[0m"

# Caminhos para os scripts
NETWORK_SCRIPT = "/root/.services/network.sh"
FIREWALL_SCRIPT = "/root/.services/firewall.sh"


def print_error(message):
    """Imprime uma mensagem de erro formatada."""
    print(f"{COLOR_RED}* {COLOR_RESET}Erro: {message}")


def print_info(message):
    """Imprime uma mensagem de informação formatada."""
    print(f"{COLOR_YELLOW}* {COLOR_RESET}{message}")


def run_script(script_path):
    """
    Verifica e executa um script shell, tratando erros.
    """
    if not os.path.exists(script_path):
        print_error(f"O script '{script_path}' não foi encontrado.")
        sys.exit(1)

    if not os.access(script_path, os.X_OK):
        print_error(f"O script '{script_path}' não tem permissão de execução.")
        sys.exit(1)

    print_info(f"Executando {script_path}...")
    # Usamos subprocess.run para executar o script
    result = subprocess.run(['bash', script_path], capture_output=True, text=True)

    if result.returncode != 0:
        print_error(f"A execução de '{script_path}' falhou.")
        # Imprime a saída de erro do script para depuração
        if result.stderr:
            print(f"  Saída de erro:\n{result.stderr}")
        sys.exit(1)


def restart_service(service_name):
    """
    Reinicia um serviço systemd e trata erros.
    """
    print_info(f"Reiniciando o serviço {service_name}...")
    command = ['systemctl', 'restart', service_name]
    result = subprocess.run(command, capture_output=True, text=True)

    if result.returncode != 0:
        print_error(f"Falha ao reiniciar o serviço '{service_name}'.")
        if result.stderr:
            print(f"  Saída de erro:\n{result.stderr}")
        sys.exit(1)

# --- Definições das Tarefas ---

def network():
    """Executa o script de rede."""
    run_script(NETWORK_SCRIPT)

def firewall():
    """Executa o script de firewall."""
    run_script(FIREWALL_SCRIPT)

def dns():
    """Reinicia o serviço dnsmasq."""
    restart_service('dnsmasq')

def dhcp():
    """Reinicia o serviço Kea DHCP."""
    restart_service('kea-dhcp4-server')

def ntp():
    """Reinicia o serviço Chrony (NTP)."""
    restart_service('chrony')

def ssh():
    """Reinicia o serviço SSH."""
    restart_service('ssh')

def others():
    """Desliga os LEDs de Power (PWR) e Atividade (ACT)."""
    print_info("Configurando LEDs do sistema...")
    led_paths = [
        "/sys/class/leds/PWR/brightness",
        "/sys/class/leds/ACT/brightness"
    ]
    for path in led_paths:
        try:
            with open(path, 'w') as f:
                f.write('0')
        except IOError as e:
            # Não sai do script por falha no LED, apenas avisa.
            print(f"{COLOR_YELLOW}* {COLOR_RESET}Aviso: Não foi possível escrever em '{path}': {e}")


def main():
    """
    Função principal para orquestrar a execução das tarefas.
    """
    # A ordem nesta lista define a ordem de execução
    tasks_to_run = [
        network,
        ssh,
        ntp,
        firewall,
        dns,
        dhcp,
        others
    ]

    for task in tasks_to_run:
        # Tenta executar a tarefa. Se falhar, o script sairá
        # devido às chamadas sys.exit(1) nas funções auxiliares.
        task()
        print(f"{COLOR_GREEN}  -> Sucesso!{COLOR_RESET}")
        time.sleep(4)


if __name__ == "__main__":
    try:
        main()
        print(f"\n{COLOR_GREEN}* {COLOR_RESET}Todos os scripts e serviços foram executados com sucesso!")
        sys.exit(0)
    except SystemExit as e:
        # Captura a saída para garantir que o script termine com o código correto
        sys.exit(e.code)
    except Exception as e:
        # Captura qualquer outra exceção inesperada
        print_error(f"Uma exceção inesperada ocorreu: {e}")
        sys.exit(1)