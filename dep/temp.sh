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

# Allow established and related connections
established_related() {
    # Filter Rules
    nft add rule inet firelux input ct state established,related accept
    nft add rule inet firelux output ct state established,related accept
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
        nft add rule inet firelux output tcp dport {53, 853} accept
        nft add rule inet firelux input tcp dport {53, 853} accept
        nft add rule inet firelux output tcp sport {53, 853} accept
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

setup_logging() {
    nft add rule inet firelux input log prefix \"INPUT_DROP: \" level info
    nft add rule inet firelux output log prefix \"OUTPUT_DROP: \" level info
    nft add rule inet firelux forward log prefix \"FORWARD_DROP: \" level info
}