listen-address=10.0.6.62,172.16.10.254,172.16.14.254,192.168.10.254
domain=pine.local.br
#Firewall dedicated
#dhcp-range=set:FWD,10.0.6.51,10.0.6.61,12h
dhcp-option=tag:FWD,3,10.0.6.62
dhcp-option=tag:FWD,6,10.0.6.62
dhcp-option=tag:FWD,42,10.0.6.62
#Servers
dhcp-range=set:SRV,172.16.10.1,172.16.10.253,12h
dhcp-option=tag:SRV,3,172.16.10.254
dhcp-option=tag:SRV,6,10.0.6.62
dhcp-option=tag:SRV,42,10.0.6.62
#Virtual Machines and Containers
dhcp-range=set:VMCT,172.16.14.26,172.16.14.253,12h
dhcp-option=tag:VMCT,3,172.16.14.254
dhcp-option=tag:VMCT,6,10.0.6.62
dhcp-option=tag:VMCT,42,10.0.6.62
#Workstation
dhcp-range=set:DKNBPRN,192.168.10.1,192.168.10.253,12h
dhcp-option=tag:DKNBPRN,3,192.168.10.254
dhcp-option=tag:DKNBPRN,6,10.0.6.62
dhcp-option=tag:DKNBPRN,42,10.0.6.62
#server=/example.local.br/172.30.100.6 #Bypass for domain lookup on specific upstream DNS server
expand-hosts
no-hosts
domain-needed
bogus-priv
dnssec
cache-size=1024
conf-file=/usr/share/dnsmasq-base/trust-anchors.conf
resolv-file=/etc/dnsmasq.d/config/resolv
addn-hosts=/etc/dnsmasq.d/config/hosts
dhcp-hostsfile=/etc/dnsmasq.d/config/reservations