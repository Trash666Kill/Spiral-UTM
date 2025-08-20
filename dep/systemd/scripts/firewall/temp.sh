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

nft add rule inet firelux forward iifname { "vlan966", "br_vlan966" } oifname "gw854807" accept


      {
        // Configurações da sub-rede 192.168.66.0/24
        "id": 5,
        "subnet": "192.168.66.0/24",
        "interface": "br_vlan966",
        "valid-lifetime": 43200,
        "pools": [
          {
            // Faixa de endereços IP para alocação dinâmica
            "pool": "192.168.66.4 - 192.168.66.20"
          }
        ],
        "option-data": [
          {
            // Configuração do gateway padrão
            "name": "routers",
            "data": "192.168.66.254"
          },
          {
            // Configuração dos servidores DNS
            "name": "domain-name-servers",
            "data": "10.0.6.1"
          },
          {
            // Configuração do domínio padrão
            "name": "domain-name",
            "data": "pine.local.br"
          },
          {
            // Configuração dos servidores NTP
            "name": "ntp-servers",
            "data": "10.0.6.1"
          }
        ]
      }