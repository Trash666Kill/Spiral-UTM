#!/bin/bash

# - ?

# Close on any error
set -e

# Configure NAT and forwarding for DMZ (VLAN966)
dmz() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 192.168.66.0/26 oifname "$WAN0" masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan966" oifname "$WAN0" accept
}

# Configure NAT and forwarding for Switch (VLAN76)
switch() {
    # SNAT Rules
    nft add rule inet firelux postrouting oif "vlan76" ip saddr 172.16.6.0/24 snat to 172.16.6.254

    # Child Functions
    subnet_80() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 80 dnat to 172.16.6.0:80

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan76" tcp dport 80 accept
        nft add rule inet firelux forward iif "vlan76" oif "vlan910" tcp sport 80 accept
    }

    # Call Child Functions
    subnet_80
}

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
}

# Configure NAT and forwarding for Virtual Machine (VLAN714)
virtual_machine() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 172.16.14.0/24 oifname "$WAN0" masquerade

    # SNAT Rules
    nft add rule inet firelux postrouting oif "vlan714" ip saddr 172.16.14.0/24 snat to 172.16.14.254

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan714" oifname "$WAN0" ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan714" oifname "$WAN0" ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan714" oifname "$WAN0" ip protocol tcp tcp dport 53 accept
    nft add rule inet firelux forward iifname "vlan714" oifname "$WAN0" ip protocol tcp tcp dport {80, 443} accept
}

# Configure NAT and forwarding for Container (VLAN718)
container() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 172.16.18.0/24 oifname "$WAN0" masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan718" oifname "$WAN0" ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan718" oifname "$WAN0" ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan718" oifname "$WAN0" ip protocol tcp tcp dport 53 accept
    nft add rule inet firelux forward iifname "vlan718" oifname "$WAN0" ip protocol tcp tcp dport {80, 443} accept
}

# Configure NAT and forwarding for Workstation (VLAN910)
workstation() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 192.168.10.0/24 oifname "$WAN0" masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan910" oifname "$WAN0" ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$WAN0" ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$WAN0" ip protocol tcp tcp dport 53 accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$WAN0" ip protocol tcp tcp dport {80, 443} accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$WAN0" ip protocol tcp tcp dport {8080, 5060} accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$WAN0" ip protocol udp udp dport {8080, 5060} accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$WAN0" ip protocol tcp tcp dport 4634 accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$WAN0" ip protocol udp udp dport 8443 accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$WAN0" ip protocol tcp tcp dport 587 accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$WAN0" ip protocol tcp tcp dport 993 accept
}

wireguard() {

    sleep 15

    # Filter Rules
    nft add rule inet firelux output udp dport 62931 accept

    # WireGuard Setup
    if ! wg show wg0 &>/dev/null; then
        wg-quick up wg0
    fi

    sleep 10
}

# Main function to orchestrate the setup
main() {
    SERVICES="
    dmz
    switch
    server
    virtual_machine
    container
    workstation
    wireguard
    "

    for SERVICE in $SERVICES
    do
        $SERVICE
        sleep 30
    done
}

# Execute main function
main