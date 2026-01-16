#!/bin/bash

# - The second stage of firewall rules, its criticality level is yellow.
# It is intended for default configuration of UTM and VLAN interfaces.

# Close on any error
set -e

# Configure SSH access for host (UTM)
host() {
    ssh() {
    # Filter Rules
    nft add rule inet firelux input ip saddr 169.254.0.2 iif "gw471042" tcp dport 444 accept
    nft add rule inet firelux output ip daddr 169.254.0.2 oif "gw471042" tcp sport 444 accept
    #
    #nft add rule inet firelux input ip saddr 192.168.10.0 iif "vlan910" tcp dport 444 accept
    #nft add rule inet firelux output ip daddr 192.168.10.0 oif "vlan910" tcp sport 444 accept
    }

    # Call
    ssh
}

# Configure NAT and forwarding for DMZ (VLAN966)
dmz() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 192.168.66.0/26 oifname "$ACTIVE_IFACE" masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname { "vlan966", "br_vlan966" } oifname "$ACTIVE_IFACE" accept
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
    nft add rule inet firelux postrouting ip saddr 172.16.10.0/24 oifname "$ACTIVE_IFACE" masquerade

    # SNAT Rules
    nft add rule inet firelux postrouting oif "vlan710" ip saddr 172.16.10.0/24 snat to 172.16.10.254

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan710" oifname "$ACTIVE_IFACE" ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan710" oifname "$ACTIVE_IFACE" ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan710" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "vlan710" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {80, 443} accept
}

# Configure NAT and forwarding for Virtual Machine (VLAN714)
virtual_machine() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 172.16.14.0/24 oifname "$ACTIVE_IFACE" masquerade

    # SNAT Rules
    nft add rule inet firelux postrouting oif "vlan714" ip saddr 172.16.14.0/24 snat to 172.16.14.254

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan714" oifname "$ACTIVE_IFACE" ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan714" oifname "$ACTIVE_IFACE" ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan714" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "vlan714" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {80, 443} accept
}

# Configure NAT and forwarding for Container (VLAN718)
container() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 172.16.18.0/24 oifname "$ACTIVE_IFACE" masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan718" oifname "$ACTIVE_IFACE" ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan718" oifname "$ACTIVE_IFACE" ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan718" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "vlan718" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {80, 443} accept
}

# Configure NAT and forwarding for Workstation (vlan910)
workstation() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 192.168.10.0/24 oifname "$ACTIVE_IFACE" masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {80, 443} accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol udp udp dport {80, 443} accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {8080, 5060} accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol udp udp dport {8080, 5060} accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport 4634 accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol udp udp dport 8443 accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport 587 accept
    nft add rule inet firelux forward iifname "vlan910" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport 993 accept
}

wifi_controller() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 192.168.22.0/24 oifname "$ACTIVE_IFACE" masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan922" oifname "$ACTIVE_IFACE" ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan922" oifname "$ACTIVE_IFACE" ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan922" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "vlan922" oifname "$ACTIVE_IFACE" ip protocol tcp tcp dport {80, 443} accept
}

# Main function to orchestrate the setup
main() {
    RULES="
    host
    dmz
    switch
    server
    virtual_machine
    container
    workstation
    wifi_controller
    "

    for RULE in $RULES
    do
        $RULE
        sleep 2
    done
}

# Execute main function
main