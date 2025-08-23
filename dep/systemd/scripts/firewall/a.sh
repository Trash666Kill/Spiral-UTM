#!/bin/bash

# - Description: Configure firewall rules for network traffic management,
# - The first stage of firewall rules, its criticality level is red.
# It is intended for the default configuration of primary interfaces and crucial UTM security rules.
# Modifying it is not recommended.
# - and ensure that the IDS (Intrusion Detection System) is active to monitor network traffic.
# - Firewall Setup Script Manual:
# - Masquerade: Hides the source IP address of packets by replacing it with the router's IP (used for NAT to external networks).
# - SNAT: Changes the source IP address of packets to a specific IP (used for internal routing).
# - DNAT: Changes the destination IP address and/or port of packets (used for port forwarding).
# - Forward: Controls packet forwarding between interfaces (used for traffic between VLANs or to WAN).
# - Filter: Controls incoming (input) or outgoing (output) traffic (used for basic firewall rules).

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

ids() {
    local SERVICE=suricata
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

# Restart nftables service
restart_nftables() {
    local SERVICE=nftables
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

# Flush existing nftables rules
flush_nftables() {
    nft flush ruleset
}

# Create main table
main_table() {
    nft add table inet firelux
}

# Create chains
chains() {
    nft add chain inet firelux input { type filter hook input priority 0 \; policy drop \; }
    nft add chain inet firelux output { type filter hook output priority 0 \; policy drop \; }
    nft add chain inet firelux forward { type filter hook forward priority filter \; policy drop \; }
    nft add chain inet firelux prerouting { type nat hook prerouting priority 0 \; policy accept \; }
    nft add chain inet firelux postrouting { type nat hook postrouting priority srcnat \; policy accept \; }
}

setup_logging() {
    nft add rule inet firelux input log prefix \"INPUT_DROP: \" level info
    nft add rule inet firelux output log prefix \"OUTPUT_DROP: \" level info
    nft add rule inet firelux forward log prefix \"FORWARD_DROP: \" level info
}

# Allow established and related connections
established_related() {
    # Filter Rules
    nft add rule inet firelux input ct state established,related accept
    nft add rule inet firelux forward ct state established,related accept
}

# Configure host-specific rules
host() {
    # Host-specific Rules
    loopback() {
        # Filter Rules
        nft add rule inet firelux input iif "lo" accept
        nft add rule inet firelux output oif "lo" accept
    }

    icmp() {
        # Filter Rules
        nft add rule inet firelux input ip protocol icmp accept
        nft add rule inet firelux output ip protocol icmp accept
    }

    dns() {
        # Filter Rules
        nft add rule inet firelux output udp dport 53 accept
        nft add rule inet firelux input udp dport 53 accept
        nft add rule inet firelux output udp sport 53 accept
        nft add rule inet firelux output tcp dport 53 accept
        nft add rule inet firelux input tcp dport 53 accept
        nft add rule inet firelux output tcp sport 53 accept
    }

    dhcp() {
        # Filter Rules
        nft add rule inet firelux input udp dport 67 accept
        nft add rule inet firelux output udp sport 67 accept
        nft add rule inet firelux output udp dport 68 accept
    }

    ntp() {
        # Filter Rules
        nft add rule inet firelux output udp dport 123 accept
        nft add rule inet firelux input udp dport 123 accept
        nft add rule inet firelux output udp sport 123 accept
    }

    web() {
        # Filter Rules
        nft add rule inet firelux output tcp dport 80 accept
        nft add rule inet firelux output tcp dport 443 accept
    }

    # Call Child Functions
    loopback
    icmp
    dns
    dhcp
    ntp
    web
}

# Main function to orchestrate the setup
main() {
    RULES="
    ip_forwarding
    restart_nftables
    flush_nftables
    main_table
    chains
    established_related
    host
    setup_logging
    "

    for RULE in $RULES
    do
        $RULE
        sleep 1
    done
}

# Execute main function
main