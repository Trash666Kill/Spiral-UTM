#!/bin/bash

# Close on any error
set -e

# Enable IP forwarding
ip_forwarding() {
    sysctl -w net.ipv4.ip_forward=1
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to enable IP forwarding.\n"
        exit 1
    fi
}

# Restart nftables service
restart_nftables() {
    local SERVICE=nftables
    echo "Restarting $SERVICE..."
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

# Flush existing nftables rules
flush_nftables() {
    echo "Flushing ruleset..."
    nft flush ruleset
}

# Create main table
main_table() {
    echo "Creating table..."
    nft add table inet firelux
}

# Main function for the blacklist system
blacklist_set() {
    echo "Configuring Blacklist..."
    # Cria o set
    nft add set inet firelux blacklist { type ipv4_addr \; flags interval \; }

    blacklist_elements() {
        echo "Adding elements to blacklist..."
        nft add element inet firelux blacklist { 45.231.112.0/22 }
    }

    blacklist_rules() {
        echo "Applying blacklist rules..."
        nft add rule inet firelux input ip saddr @blacklist drop
        nft add rule inet firelux forward ip saddr @blacklist drop
    }

    # Call Child Functions
    blacklist_elements
    blacklist_rules
}

# Create chains with default drop policy
chains() {
    echo "Creating chains..."
    nft add chain inet firelux input { type filter hook input priority 0 \; policy drop \; }
    nft add chain inet firelux output { type filter hook output priority 0 \; policy drop \; }
    nft add chain inet firelux forward { type filter hook forward priority filter \; policy drop \; }
    nft add chain inet firelux prerouting { type nat hook prerouting priority 0 \; policy accept \; }
    nft add chain inet firelux postrouting { type nat hook postrouting priority srcnat \; policy accept \; }
}

# Setup logging for dropped packets
setup_logging() {
    echo "Setting up logging..."
    nft add rule inet firelux input log prefix \"INPUT_DROP: \" level info
    nft add rule inet firelux output log prefix \"OUTPUT_DROP: \" level info
    nft add rule inet firelux forward log prefix \"FORWARD_DROP: \" level info
}

# Allow established and related connections (essential for stateful firewall)
established_related() {
    echo "Allowing established/related connections..."
    nft add rule inet firelux input ct state established,related accept
    nft add rule inet firelux output ct state established,related accept
    nft add rule inet firelux forward ct state established,related accept
}

# Configure host-specific rules
host() {
    echo "Configuring host rules..."
    # Filter Rules
    loopback() {
        nft add rule inet firelux input iif "lo" accept
        nft add rule inet firelux output oif "lo" accept
    }

    # Filter Rules
    icmp() {
        nft add rule inet firelux input icmp type { echo-request, echo-reply, destination-unreachable, time-exceeded } accept
        nft add rule inet firelux output icmp type { echo-request, echo-reply, destination-unreachable, time-exceeded } accept
    }

    # Filter Rules
    dns() {
        nft add rule inet firelux output udp dport 53 accept
        nft add rule inet firelux output tcp dport 53 accept
    }

    # Filter Rules
    ntp() {
        nft add rule inet firelux output udp dport 123 accept
    }

    # Filter Rules
    web() {
        nft add rule inet firelux output tcp dport 80 accept
        nft add rule inet firelux output tcp dport 443 accept
        # SSH do Host
        nft add rule inet firelux input tcp dport { 4634, 4635 } accept
    }

    # Call Child Functions
    loopback
    icmp
    dns
    ntp
    web
}

# Função para as regras de NAT e Forwarding das VMs (necessário para manter seu ambiente funcional)
vms_and_nat() {
    echo "Configuring VM Forwarding and NAT..."
    # DNAT
    nft add rule inet firelux prerouting iifname "eth0" tcp dport 80 dnat ip to 10.0.11.3:80
    nft add rule inet firelux prerouting iifname "eth0" tcp dport 443 dnat ip to 10.0.11.3:443
    nft add rule inet firelux prerouting iifname "eth0" tcp dport 7881 dnat ip to 10.0.11.9:7881
    nft add rule inet firelux prerouting iifname "eth0" udp dport 50000-60000 dnat ip to 10.0.11.9
    
    # Forwarding Accept
    nft add rule inet firelux forward ip daddr 10.0.11.3 tcp dport { 80, 443 } accept
    nft add rule inet firelux forward ip daddr 10.0.11.9 tcp dport 7881 accept
    nft add rule inet firelux forward ip daddr 10.0.11.9 udp dport 50000-60000 accept
    nft add rule inet firelux forward iifname "br_tap111" oifname "eth0" accept
    
    # Masquerade
    nft add rule inet firelux postrouting ip saddr 10.0.11.0/24 oifname "eth0" masquerade
}

# Main function to orchestrate the setup
main() {
    RULES="
    ip_forwarding
    restart_nftables
    flush_nftables
    main_table
    chains
    blacklist_set
    established_related
    host
    vms_and_nat
    setup_logging
    "

    for RULE in $RULES
    do
        $RULE
    done
}

# Execute main function
main