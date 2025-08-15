#!/bin/bash

# - Description: Configures network interfaces and gateways for a UTM environment.
# - Sets up physical interfaces (WAN/LAN), main gateways (Trunk, DNS/NTP, SSH/SNMP),
# - and subsidiary VLANs (Switch, Server, VM, Container, Workstation, DMZ).
# - Exits with an error if any configuration fails.
# - To add new gateways or VLANs, copy and edit functions like gw854807 or vlan76.

# Close on any error
set -e

# Physical interfaces
interfaces() {
    wan0() {
        WAN0=eth0
        ip link set dev "$WAN0" up
    }

    lan0() {
        LAN0=eth1
        ip link set dev "$LAN0" up
    }

    # Call
    wan0
    lan0
}

# Gateways required for UTM to work
main_gw() {
    # Trunk/WAN0
    gw854807() {
        brctl addbr gw854807
        brctl stp gw854807 on
        brctl addif gw854807 "$WAN0"
        ip link set dev gw854807 up
        ip addr add 10.0.2.253/24 dev gw854807
        ip route add default via 10.0.2.254 dev gw854807
    }

    # DNS, NTP, DHCP etc services of the real host
    gw375993() {
        ip tuntap add tap16 mode tap
        ip link set dev tap16 up
        brctl addbr gw375993
        brctl stp gw375993 on
        brctl addif gw375993 tap16
        ip link set dev gw375993 up
        ip addr add 10.0.6.62/26 dev gw375993
    }

    # SSH, SNMP, etc via LAN
    gw471042() {
        brctl addbr gw471042
        brctl stp gw471042 on
        brctl addif gw471042 "$LAN0"
        ip link set dev gw471042 up
        ip addr add 172.16.2.253/30 dev gw471042
    }

    # Call
    gw854807
    gw375993
    gw471042
}

# Subsidiary gateways according to the needs of the environment
subsidiary_gw() {
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

    #DMZ
    vlan966() {
        ip link add link "$LAN0" name vlan966 type vlan id 966
        ip link set dev vlan966 up
        ip addr add 192.168.66.62/26 dev vlan966
    }

    # Call
    vlan76
    vlan710
    vlan714
    vlan718
    vlan910
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