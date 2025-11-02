# Configure NAT and forwarding for Server (VLAN710)
server() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 172.16.10.0/24 oifname "$WAN0" masquerade

    # SNAT Rules
    nft add rule inet firelux postrouting oif "vlan710" ip saddr 172.16.10.0/24 snat to 172.16.10.254

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan710" oifname "$WAN0" ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan710" oifname "$WAN0" ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan710" oifname "$WAN0" ip protocol tcp tcp dport 53 accept
    nft add rule inet firelux forward iifname "vlan710" oifname "$WAN0" ip protocol tcp tcp dport {80, 443} accept

    # Child Functions
    srv28013_445() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 445 dnat to 172.16.10.1:445

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 445 accept
        nft add rule inet firelux forward iif "vlan710" oif "vlan910" tcp sport 445 accept
    }

    srv28013_4242() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 4242 dnat to 172.16.10.1:4242

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 4242 accept
    }

    srv28013_6600() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 6600 dnat to 172.16.10.1:6600

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 6600 accept
    }

    srv28013_5644() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 5644 dnat to 172.16.10.1:5644

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 5644 accept
    }

    srv28013_4533() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 4533 dnat to 172.16.10.1:4533

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 4533 accept
    }

    srv28013_8096() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 8096 dnat to 172.16.10.1:8096

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 8096 accept
    }

    srv28013_6080() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 6080 dnat to 172.16.10.1:6080

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 6080 accept
    }

    srv28013_6081() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 6081 dnat to 172.16.10.1:6081

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 6081 accept
    }

    srv28013_8081() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 8081 dnat to 172.16.10.1:8081

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 8081 accept
    }

    srv28013_3389() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 3389 dnat to 172.16.10.1:3389

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 3389 accept
    }

    srv28013_vnc() {
        # DNAT Rules
        for port in $(seq 5900 5960); do
            nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport $port dnat to 172.16.10.1:$port
        done

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 5900-5960 accept
        nft add rule inet firelux forward iif "vlan710" oif "vlan910" tcp sport 5900-5960 accept
    }

    inter_vlan_4242() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan714" ip daddr 172.16.14.0/24 tcp dport 4242 dnat to 172.16.10.0:4242

        # Forward Rules
        nft add rule inet firelux forward iif "vlan714" oif "vlan710" tcp dport 4242 accept
        nft add rule inet firelux forward iif "vlan710" oif "vlan714" tcp sport 4242 accept
    }

    # Call Child Functions
    srv28013_445
    srv28013_4242
    srv28013_5644
    srv28013_6600
    srv28013_4533
    srv28013_8096
    srv28013_6080
    srv28013_6081
    srv28013_8081
    srv28013_3389
    srv28013_vnc
    inter_vlan_4242
}