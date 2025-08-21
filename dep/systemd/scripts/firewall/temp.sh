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
  "Dhcp4": {
    // Configurações gerais do servidor DHCPv4
    "interfaces-config": {
      // Definição das interfaces de rede para operação do DHCP
      "interfaces": ["gw099324", "vlan710", "vlan714", "vlan910", "br_vlan966"]
    },
    "lease-database": {
      // Parâmetros do banco de dados para gerenciamento de leases
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/kea-leases4.csv"
    },
    "subnet4": [
      {
        // Configurações da sub-rede 10.0.4.0/28
        "id": 1,
        "subnet": "10.0.4.0/28",
        "interface": "gw099324",
        "valid-lifetime": 43200,
        "pools": [
          {
            // Faixa de endereços IP para alocação dinâmica
            "pool": "10.0.4.1 - 10.0.4.13"
          }
        ],
        "option-data": [
          {
            // Configuração do gateway padrão
            "name": "routers",
            "data": "10.0.4.14"
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
      },
      {
        // Configurações da sub-rede 172.16.10.0/24
        "id": 2,
        "subnet": "172.16.10.0/24",
        "interface": "vlan710",
        "valid-lifetime": 604800,
        "pools": [
          {
            // Faixa de endereços IP para alocação dinâmica
            "pool": "172.16.10.1 - 172.16.10.253"
          }
        ],
        "option-data": [
          {
            // Configuração do gateway padrão
            "name": "routers",
            "data": "172.16.10.254"
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
        ],
        "reservations": [
          {
            // SRV59978
            "hw-address": "ac:22:0b:2e:2b:f7",
            "ip-address": "172.16.10.2",
            "hostname": "srv59978"
          }
        ]
      },
      {
        // Configurações da sub-rede 172.16.14.0/24
        "id": 3,
        "subnet": "172.16.14.0/24",
        "interface": "vlan714",
        "valid-lifetime": 604800,
        "pools": [
          {
            // Faixa de endereços IP para alocação dinâmica
            "pool": "172.16.14.1 - 172.16.14.253"
          }
        ],
        "option-data": [
          {
            // Configuração do gateway padrão
            "name": "routers",
            "data": "172.16.14.254"
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
      },
      {
        // Configurações da sub-rede 192.168.10.0/24
        "id": 4,
        "subnet": "192.168.10.0/24",
        "interface": "vlan910",
        "valid-lifetime": 43200,
        "pools": [
          {
            // Faixa de endereços IP para alocação dinâmica
            "pool": "192.168.10.1 - 192.168.10.253"
          }
        ],
        "option-data": [
          {
            // Configuração do gateway padrão
            "name": "routers",
            "data": "192.168.10.254"
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
        ],
        "reservations": [
          {
            // Reservas de endereços IP para dispositivos específicos
            "hw-address": "dc:a2:66:91:73:95",
            "ip-address": "192.168.10.26",
            "hostname": "nb367095"
          }
        ]
      },
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
    ],
    "loggers": [
      {
        // Configurações de registro de logs do servidor DHCP
        "name": "kea-dhcp4",
        "output_options": [
          {
            // Definição do arquivo de saída para logs
            "output": "/var/log/kea/kea-dhcp4.log"
          }
        ],
        "severity": "INFO"
      }
    ]
  }
}




