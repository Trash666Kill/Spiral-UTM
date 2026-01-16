#!/bin/bash

# Close on any error
set -e

#WAN0=""
#WAN1=""
#LAN0=""

DHCP_MAX_RETRIES=5
DHCP_WAIT_TIME=5

# Physical interfaces
interfaces() {
    wan0() {
        ip link set dev "$WAN0" up
    }

    wan1() {
        ip link set dev "$WAN1" up
    }

    lan0() {
        ip link set dev "$LAN0" up
    }

    # Call
    wan0
    wan1
    lan0
}

# Gateways required for UTM to work
main_gw() {
    # Trunk/WAN0
    gw854807() {
        # Primary
        brctl addbr gw854807
        brctl stp gw854807 on
        brctl addif gw854807 "$WAN0"
        ip link set dev gw854807 up
    }

    # Trunk/WAN1
    gw965918() {
        # Secondary
        brctl addbr gw965918
        brctl stp gw965918 on
        brctl addif gw965918 "$WAN1"
        ip link set dev gw965918 up
    }

    dhcp() {
        gw854807
        gw965918

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

            # Se pelo menos UMA interface tiver IP, entra no bloco de sucesso
            if [[ -n "$ip_wan0" ]] || [[ -n "$ip_wan1" ]]; then
                echo "[OK] Conectividade estabelecida!"

                # --- CORREÇÃO LÓGICA DE PREFERÊNCIA ---
                # Verifica PRIMEIRO se a WAN0 (gw854807) tem IP. 
                # Se tiver, ela é a ativa (mesmo que a WAN1 também tenha).
                if [[ -n "$ip_wan0" ]]; then
                    ACTIVE_IFACE="gw854807"
                    # Exibe info da WAN0
                    echo " -> gw854807 (WAN0): $ip_wan0 [PREFERIDA - ATIVA]"
                    # Se a WAN1 também estiver ativa, apenas avisa, mas não muda a ACTIVE_IFACE
                    if [[ -n "$ip_wan1" ]]; then
                        echo " -> gw965918 (WAN1): $ip_wan1 [ONLINE - STANDBY]"
                    fi
                else
                    # Se caiu aqui, WAN0 está OFF e WAN1 está ON
                    ACTIVE_IFACE="gw965918"
                    echo " -> gw854807 (WAN0): OFFLINE"
                    echo " -> gw965918 (WAN1): $ip_wan1 [SECUNDÁRIA - ATIVA]"
                fi

                # Captura o Altname da interface VENCEDORA
                ALTNAME=$(ip addr show "$ACTIVE_IFACE" | awk '/altname/ {print $2; exit}')
                
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

        # Vincula a interface ao UTM como primária
        # Remove qualquer definição anterior para evitar duplicidade
        sed -i '/^ACTIVE_IFACE=/d' /etc/environment
        echo "ACTIVE_IFACE=$ACTIVE_IFACE" >> /etc/environment
        
        sed -i '/^ACTIVE_ALTNAME=/d' /etc/environment
        echo "ACTIVE_ALTNAME=$ALTNAME" >> /etc/environment

        echo "[INFO] Rede configurada. Interface ativa: $ACTIVE_IFACE ($ALTNAME). A continuar..."
    }

    # DNS, NTP, etc services of the real host
    tap16() {
        ip tuntap add tap16 mode tap
        ip link set dev tap16 up
        ip addr add 10.0.6.1/32 dev tap16
    }

    # APIPA
    gw471042() {
        brctl addbr gw471042
        brctl stp gw471042 on
        brctl addif gw471042 "$LAN0"
        ip link set dev gw471042 up
        ip addr add 169.254.0.1/30 dev gw471042
    }

    # Call
    gw471042
    tap16
    dhcp
}

# Subsidiary gateways according to the needs of the environment
subsidiary_gw() {
    #Default
    vlan1() {
        ip link add link "$LAN0" name vlan1 type vlan id 1
        ip link set dev vlan1 up
    }

    #Switch
    vlan76() {
        ip link add link "$LAN0" name vlan76 type vlan id 76
        ip link set dev vlan76 up
        ip addr add 172.16.6.254/24 dev vlan76
    }

    #Server
    vlan710() {
        ip link add link "$LAN0" name vlan710 type vlan id 710
        ip link set dev vlan710 up
        ip addr add 172.16.10.254/24 dev vlan710
    }

    #Virtual Machine
    vlan714() {
        ip link add link "$LAN0" name vlan714 type vlan id 714
        ip link set dev vlan714 up
        ip addr add 172.16.14.254/24 dev vlan714
    }

    #Container
    vlan718() {
        ip link add link "$LAN0" name vlan718 type vlan id 718
        ip link set dev vlan718 up
        ip addr add 172.16.18.254/24 dev vlan718
    }

    #Workstation
    vlan910() {
        ip link add link "$LAN0" name vlan910 type vlan id 910
        ip link set dev vlan910 up
        ip addr add 192.168.10.254/24 dev vlan910
    }

    #Wi-Fi (Controller)
    vlan922() {
        ip link add link "$LAN0" name vlan922 type vlan id 922
        ip link set dev vlan922 up
        ip addr add 192.168.22.254/24 dev vlan922
    }

    #DMZ
    vlan966() {
        ip link add link "$LAN0" name vlan966 type vlan id 966
        ip link set dev vlan966 up
        ip addr add 192.168.66.254/24 dev vlan966
    }

    # Call
    vlan1
    vlan76
    vlan710
    vlan714
    vlan718
    vlan910
    vlan922
    vlan966
}

# Main function to orchestrate the setup
main() {
    interfaces
    main_gw
    subsidiary_gw
}

# Execute main function
main




