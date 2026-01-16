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