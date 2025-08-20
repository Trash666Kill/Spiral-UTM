chains() {
    nft add chain inet firelux input { type filter hook input priority 0 \; policy drop \; }
    nft add rule inet firelux input log prefix \"INPUT_DROP: \" level info drop
    nft add chain inet firelux output { type filter hook output priority 0 \; policy drop \; }
    nft add rule inet firelux output log prefix \"OUTPUT_DROP: \" level info drop
    nft add chain inet firelux forward { type filter hook forward priority filter \; policy drop \; }
    nft add rule inet firelux forward log prefix \"FORWARD_DROP: \" level info drop
    nft add chain inet firelux prerouting { type nat hook prerouting priority 0 \; policy accept \; }
    nft add rule inet firelux prerouting log prefix \"PREROUTING: \" level info accept
    nft add chain inet firelux postrouting { type nat hook postrouting priority srcnat \; policy accept \; }
    nft add rule inet firelux postrouting log prefix \"POSTROUTING: \" level info accept
}




chains() {
    nft add chain inet firelux input { type filter hook input priority 0 \; policy drop \; }
    nft add chain inet firelux output { type filter hook output priority 0 \; policy drop \; }
    nft add chain inet firelux forward { type filter hook forward priority filter \; policy drop \; }
    nft add chain inet firelux prerouting { type nat hook prerouting priority 0 \; policy accept \; }
    nft add chain inet firelux postrouting { type nat hook postrouting priority srcnat \; policy accept \; }
}