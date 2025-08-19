# Configure NAT and forwarding for Bridge (BR_TAP714)
br_tap714() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 172.16.14.0/24 oifname "vlan714" masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "br_tap714" oifname "vlan714" accept
}