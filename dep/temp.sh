#!/bin/bash

# ==============================================================================
# CONFIGURAÇÃO DE VARIÁVEIS
# ==============================================================================
DHCP_MAX_RETRIES=5      # Total de tentativas
DHCP_WAIT_TIME=5        # Pausa (segundos) entre tentativas
WAN0="eth0"             # Ajuste para a sua interface física real
WAN1="eth1"             # Ajuste para a sua interface física real

# ==============================================================================
# FUNÇÕES AUXILIARES (LAYER 2)
# ==============================================================================
setup_gw854807_l2() {
    # WAN0 - PRIMARY
    brctl addbr gw854807
    brctl stp gw854807 on
    brctl addif gw854807 "$WAN0"
    ip link set dev gw854807 up
}

setup_gw965918_l2() {
    # WAN1 - SECONDARY
    brctl addbr gw965918
    brctl stp gw965918 on
    brctl addif gw965918 "$WAN1"
    ip link set dev gw965918 up
}

# ==============================================================================
# FUNÇÃO PRINCIPAL
# ==============================================================================
dhcp() {
    echo "[INFO] A inicializar as pontes de rede..."
    setup_gw854807_l2
    setup_gw965918_l2

    # Definição Fixa de Prioridade
    # gw854807 (WAN0) -> Métrica 10 (Prioritária)
    # gw965918 (WAN1) -> Métrica 100 (Secundária)
    
    echo "[DHCP] A solicitar endereços IP (WAN0=Pri, WAN1=Sec)..."
    
    # Executa em background (-b) para não bloquear o script
    dhcpcd -4 -b -m 10 gw854807
    dhcpcd -4 -b -m 100 gw965918

    # Loop de Verificação (5 tentativas)
    local count=1
    local success=0

    while [ $count -le $DHCP_MAX_RETRIES ]; do
        echo "[WAIT] Tentativa $count de $DHCP_MAX_RETRIES... A verificar IPs..."
        
        # Verifica se obteve IP (filtra saída do ip addr)
        ip_wan0=$(ip -4 addr show gw854807 | grep "inet " | awk '{print $2}')
        ip_wan1=$(ip -4 addr show gw965918 | grep "inet " | awk '{print $2}')

        if [[ -n "$ip_wan0" ]] || [[ -n "$ip_wan1" ]]; then
            echo "[OK] Conectividade estabelecida!"
            if [[ -n "$ip_wan0" ]]; then
                ACTIVE_IFACE="gw854807"
                echo " -> gw854807 (WAN0): $ip_wan0 [PREFERIDA - ATIVA]"
            fi
            if [[ -n "$ip_wan1" ]]; then
                ACTIVE_IFACE="gw965918"
                echo " -> gw965918 (WAN1): $ip_wan1 [SECUNDÁRIA]"
            fi
            success=1
            break
        fi

        sleep $DHCP_WAIT_TIME
        ((count++))
    done

    # Morte Súbita: Encerra se ambas falharem após 5 tentativas
    if [ $success -eq 0 ]; then
        echo "[CRITICAL] Falha total: Nenhuma interface obteve endereço IP."
        echo "[STOP] A abortar o script."
        exit 1
    fi

    echo "[INFO] Rede configurada com sucesso. A continuar a execução..."
}

# Execução
main_gw