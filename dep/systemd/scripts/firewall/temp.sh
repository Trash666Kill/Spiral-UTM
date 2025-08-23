# LOGGING RULES - MOVIDA PARA CÁ
info() {
    nft add rule inet firelux input log prefix \"INPUT_DROP: \" level info drop
    nft add rule inet firelux output log prefix \"OUTPUT_DROP: \" level info drop
    nft add rule inet firelux forward log prefix \"FORWARD_DROP: \" level info drop
    
    # As regras de nat não precisam de "accept" aqui, a política da chain já é accept
    # nft add rule inet firelux prerouting log prefix \"PREROUTING: \" level info accept
    # nft add rule inet firelux postrouting log prefix \"POSTROUTING: \" level info accept
}