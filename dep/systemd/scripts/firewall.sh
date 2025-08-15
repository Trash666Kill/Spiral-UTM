#!/bin/bash

# - Description: Configure firewall rules for network traffic management,
# - and ensure that the IDS (Intrusion Detection System) is active to monitor network traffic.
# - Firewall Setup Script Manual:
# - Masquerade: Hides the source IP address of packets by replacing it with the router's IP (used for NAT to external networks).
# - SNAT: Changes the source IP address of packets to a specific IP (used for internal routing).
# - DNAT: Changes the destination IP address and/or port of packets (used for port forwarding).
# - Forward: Controls packet forwarding between interfaces (used for traffic between VLANs or to WAN).
# - Filter: Controls incoming (input) or outgoing (output) traffic (used for basic firewall rules).

# Close on any error
set -e

# Interfaces
WAN0=gw854807

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

    ssh() {
        # Filter Rules
        nft add rule inet firelux input ip saddr 192.168.10.26 iif "vlan910" tcp dport 444 accept
        nft add rule inet firelux output ip daddr 192.168.10.26 oif "vlan910" tcp sport 444 accept
    }

    # Call Child Functions
    loopback
    icmp
    dns
    dhcp
    ntp
    web
    ssh
}

# Configure NAT and forwarding for Gateway (GW375993)
gateway() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 10.0.6.0/26 oifname gw854807 masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "gw375993" oifname gw854807 ip protocol icmp accept
    nft add rule inet firelux forward iifname "gw375993" oifname gw854807 ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "gw375993" oifname gw854807 ip protocol tcp tcp dport 53 accept
    nft add rule inet firelux forward iifname "gw375993" oifname gw854807 ip protocol tcp tcp dport {80, 443} accept
}

# Configure NAT and forwarding for DMZ (VLAN966)
dmz() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 192.168.66.0/26 oifname gw854807 masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan966" oifname gw854807 accept
}

# Configure NAT and forwarding for Switch (VLAN76)
switch() {
    # SNAT Rules
    nft add rule inet firelux postrouting oif "vlan76" ip saddr 172.16.6.0/24 snat to 172.16.6.254

    # Child Functions
    80() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 80 dnat to 172.16.6.0:80

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan76" tcp dport 80 accept
        nft add rule inet firelux forward iif "vlan76" oif "vlan910" tcp sport 80 accept
    }

    # Call Child Functions
    80
}

# Configure NAT and forwarding for Server (VLAN710)
server() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 172.16.10.0/24 oifname gw854807 masquerade

    # SNAT Rules
    nft add rule inet firelux postrouting oif "vlan710" ip saddr 172.16.10.0/24 snat to 172.16.10.254

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan710" oifname gw854807 ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan710" oifname gw854807 ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan710" oifname gw854807 ip protocol tcp tcp dport 53 accept
    nft add rule inet firelux forward iifname "vlan710" oifname gw854807 ip protocol tcp tcp dport {80, 443} accept

    # Child Functions
    # Subnet
    (
        subnet() {
            445() {
                # DNAT Rules
                nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 445 dnat to 172.16.10.0:445

                # Forward Rules
                nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 445 accept
                nft add rule inet firelux forward iif "vlan710" oif "vlan910" tcp sport 445 accept
            }

            5899() {
                # DNAT Rules
                nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 5899 dnat to 172.16.10.0:5899

                # Forward Rules
                nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 5899 accept
                nft add rule inet firelux forward iif "vlan710" oif "vlan910" tcp sport 5899 accept
            }

            4242() {
                # DNAT Rules
                nft add rule inet firelux prerouting iif "vlan714" ip daddr 172.16.14.0/24 tcp dport 4242 dnat to 172.16.10.0:4242

                # Forward Rules
                nft add rule inet firelux forward iif "vlan714" oif "vlan710" tcp dport 4242 accept
                nft add rule inet firelux forward iif "vlan710" oif "vlan714" tcp sport 4242 accept
            }

            vnc() {
            # DNAT Rules
            for port in $(seq 5900 5960); do
                nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport $port dnat to 172.16.10.0:$port
            done

            # Forward Rules
            nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 5900-5960 accept
            nft add rule inet firelux forward iif "vlan710" oif "vlan910" tcp sport 5900-5960 accept
            }

            # Call
            445
            5899
            4242
            vnc
        }
    )

    # Servers
    (
        servers() {
            4242() {
                # DNAT Rules
                nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 4242 dnat to 172.16.10.2:4242

                # Forward Rules
                nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 4242 accept
            }

            4533() {
                # DNAT Rules
                nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 4533 dnat to 172.16.10.2:4533

                # Forward Rules
                nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 4533 accept
            }

            6081() {
                # DNAT Rules
                nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 6081 dnat to 172.16.10.2:6081

                # Forward Rules
                nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 6081 accept
            }

            6600() {
                # DNAT Rules
                nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 6600 dnat to 172.16.10.2:6600

                # Forward Rules
                nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 6600 accept
            }

            5644() {
                # DNAT Rules
                nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 5644 dnat to 172.16.10.2:5644

                # Forward Rules
                nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 5644 accept
            }

            8080() {
                # DNAT Rules
                nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 8080 dnat to 172.16.10.2:8080

                # Forward Rules
                nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 8080 accept
            }

            8096() {
                # DNAT Rules
                nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 8096 dnat to 172.16.10.2:8096

                # Forward Rules
                nft add rule inet firelux forward iif "vlan910" oif "vlan710" tcp dport 8096 accept
            }

            # Call Child Functions
            445
            5899
            4242
            4533
            6081
            6600
            5644
            8080
            8096
            }
    )
}

# Configure NAT and forwarding for Virtual Machine (VLAN714)
virtual_machine() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 172.16.14.0/24 oifname gw854807 masquerade

    # SNAT Rules
    nft add rule inet firelux postrouting oif "vlan714" ip saddr 172.16.14.0/24 snat to 172.16.14.254

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan714" oifname gw854807 ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan714" oifname gw854807 ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan714" oifname gw854807 ip protocol tcp tcp dport 53 accept
    nft add rule inet firelux forward iifname "vlan714" oifname gw854807 ip protocol tcp tcp dport {80, 443} accept

    # Child Functions
    vm60230_4343() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 4343 dnat to 172.16.14.23:4343

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan714" tcp dport 4343 accept
        nft add rule inet firelux forward iif "vlan714" oif "vlan910" tcp sport 4343 accept
    }

    vm60231_3389() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "vlan910" ip daddr 192.168.10.0/24 tcp dport 3389 dnat to 172.16.14.180:3389

        # Forward Rules
        nft add rule inet firelux forward iif "vlan910" oif "vlan714" tcp dport 3389 accept
    }

    # Call Child Functions
    vm60230_4343
    vm60231_3389
}

# Configure NAT and forwarding for Container (VLAN718)
container() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 172.16.18.0/24 oifname gw854807 masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan718" oifname gw854807 ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan718" oifname gw854807 ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan718" oifname gw854807 ip protocol tcp tcp dport 53 accept
    nft add rule inet firelux forward iifname "vlan718" oifname gw854807 ip protocol tcp tcp dport {80, 443} accept
}

# Configure NAT and forwarding for Workstation (VLAN910)
workstation() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 192.168.10.0/24 oifname gw854807 masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "vlan910" oifname gw854807 ip protocol icmp accept
    nft add rule inet firelux forward iifname "vlan910" oifname gw854807 ip protocol udp udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan910" oifname gw854807 ip protocol tcp tcp dport 53 accept
    nft add rule inet firelux forward iifname "vlan910" oifname gw854807 ip protocol tcp tcp dport {80, 443} accept
    nft add rule inet firelux forward iifname "vlan910" oifname gw854807 ip protocol tcp tcp dport {8080, 5060} accept
    nft add rule inet firelux forward iifname "vlan910" oifname gw854807 ip protocol udp udp dport {8080, 5060} accept
    nft add rule inet firelux forward iifname "vlan910" oifname gw854807 ip protocol tcp tcp dport 4634 accept
    nft add rule inet firelux forward iifname "vlan910" oifname gw854807 ip protocol udp udp dport 8443 accept
    nft add rule inet firelux forward iifname "vlan910" oifname gw854807 ip protocol tcp tcp dport 587 accept
    nft add rule inet firelux forward iifname "vlan910" oifname gw854807 ip protocol tcp tcp dport 993 accept
}

# Configure WireGuard tunnel
wireguard() {

    sleep 15

    # Filter Rules
    nft add rule inet firelux output udp dport 62931 accept

    # WireGuard Setup
    if ! wg show wg0 &>/dev/null; then
        wg-quick up wg0
    fi

    sleep 10

    # Child Functions
    4533() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "wg0" ip daddr 10.8.0.0/24 tcp dport 4533 dnat to 172.16.10.2:4533

        # Forward Rules
        nft add rule inet firelux forward iif "wg0" oif "vlan710" tcp dport 4533 accept
    }
    
    4534() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "wg0" ip daddr 10.8.0.0/24 tcp dport 4534 dnat to 172.16.10.2:4534

        # Forward Rules
        nft add rule inet firelux forward iif "wg0" oif "vlan710" tcp dport 4534 accept
    }
    
    8096() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "wg0" ip daddr 10.8.0.0/24 tcp dport 8096 dnat to 172.16.10.2:8096

        # Forward Rules
        nft add rule inet firelux forward iif "wg0" oif "vlan710" tcp dport 8096 accept
    }

    transmission_9091() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "wg0" ip daddr 10.8.0.0/24 tcp dport 9091 dnat to 192.168.66.1:9091

        # Forward Rules
        nft add rule inet firelux forward iif "wg0" oif "vlan966" tcp dport 9091 accept
    }

    4242() {
        # DNAT Rules
        nft add rule inet firelux prerouting iif "wg0" ip daddr 10.8.0.0/24 tcp dport 4242 dnat to 172.16.10.2:4242

        # Forward Rules
        nft add rule inet firelux forward iif "wg0" oif "vlan710" tcp dport 4242 accept
    }

    # Call Child Functions
    4533
    4534
    8096
    transmission_9091
    4242
}

# Main function to orchestrate the setup
main() {
    ip_forwarding
    #ids
    restart_nftables
    flush_nftables
    main_table
    chains
    established_related
    host
    gateway
    dmz
    switch
    server
    virtual_machine
    container
    workstation
    wireguard
}

# Execute main function
main