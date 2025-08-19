# Configure NAT and forwarding for Bridge (BR_TAP110)
br_tap111() {
    # Masquerade Rules
    nft add rule inet firelux postrouting ip saddr 10.0.11.0/24 oifname "$WAN" masquerade

    # Forward Rules
    nft add rule inet firelux forward iifname "br_tap111" oifname "$WAN" accept
}