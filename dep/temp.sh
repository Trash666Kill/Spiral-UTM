# Configure NAT and forwarding for Bridge (BR_TAP714)
br_tap714() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 10.0.11.0/24 oifname "$WAN0" masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "br_tap714" oifname "$WAN0" accept
}