#!/bin/bash
# - SCRIPT FOR AUTOMATIC CONSTRUCTION OF LXC CONTAINERS FOR VPS

# Diretório de execução
cd /etc/spawn/CT/

# Desativa histórico bash
unset HISTFILE

BASE="SpiralCT"
BASE_CT_FILES="basect.sh"
ARCH=amd64
NEW_CT="CT$(shuf -i 100000-999999 -n 1)"
NEW_CT_FILES="later.sh"
RELEASE=bookworm

basect() {
# Verifica se os arquivos necessários para criar o container base existem
for file in $BASE_CT_FILES; do
    if [[ ! -f "$file" ]]; then
        printf "\e[31m*\e[0m ERROR: FILES REQUIRED TO BUILD THE BASE CONTAINER \033[32m%s\033[0m DO NOT EXIST.\n" "$file"
        exit 1
    fi
done

# Verifica se o container base já existe
if ! lxc-ls --filter "^${BASE}$" | grep -q "${BASE}"; then
    printf "\e[33m*\e[0m ATTENTION: THE BASE CONTAINER \033[32m%s\033[0m DOES NOT EXIST, WAIT...\n" "$BASE"

    # Cria o container base se não existir
    lxc-create --name "${BASE}" --template download -- --dist debian --release "${RELEASE}" --arch "${ARCH}" > /dev/null

    # Copia o script de configuração para o diretório do container
    cp basect.sh /var/lib/lxc/"${BASE}"/rootfs/root/

    # Verifica se a cópia foi bem-sucedida
    if [ $? -ne 0 ]; then
        printf "\e[31m*\e[0m ERROR: FAILED TO CREATE BASE CONTAINER \033[32m%s\033[0m.\n" "$BASE"
        exit 1
    fi

    # Tenta iniciar o container
    if ! lxc-start --name "${BASE}"; then
        printf "\e[31m*\e[0m ERROR: CONTAINER \033[32m%s\033[0m FAILED TO START.\n" "$BASE"
        exit 1
    fi

    # Tenta conectar o container à internet
    printf "\e[32m*\e[0m TRYING TO CONNECT TO THE INTERNET, WAIT...\n"
    if ! lxc-attach --name "${BASE}" -- dhclient eth0; then
        printf "\e[31m*\e[0m ERROR: CONTAINER \033[32m%s\033[0m WAS UNABLE TO CONNECT TO THE INTERNET.\n" "$BASE"
        lxc-stop --name "${BASE}"
        exit 1
    fi

    # Realiza as operações de construção e configuração no container
    printf "\e[32m*\e[0m BUILDING BASE, WAIT...\n"
    lxc-attach --name "${BASE}" -- chmod +x /root/basect.sh
    lxc-attach --name "${BASE}" -- /root/basect.sh

    # Verifica se a atualização ou instalação dos pacotes falhou
    if [ $? -ne 0 ]; then
        printf "\e[31m*\e[0m ERROR: COULD NOT UPDATE OR INSTALL PACKAGES IN CONTAINER \033[32m%s\033[0m.\n" "$BASE"
        lxc-stop --name "${BASE}"
        exit 1
    fi

    # Para o container após a conclusão
    lxc-stop --name "${BASE}"
    sleep 5

    printf "\e[32m*\e[0m CONTAINER \033[32m%s\033[0m SUCCESSFULLY CREATED AND CONFIGURED.\n" "$BASE"
else
    printf "\e[32m*\e[0m BASE CONTAINER ALREADY EXISTS.\n"
fi
}

newct() {
# Verifica se os arquivos necessários para criar o novo container existem
for file in $NEW_CT_FILES; do
    if [[ ! -f "$file" ]]; then
        printf "\e[31m*\e[0m ERROR: FILES REQUIRED TO BUILD THE NEW CONTAINER \033[32m%s\033[0m DO NOT EXIST.\n" "$file"
        exit 1
    fi
done

# Inicia a criação do novo container a partir do container base
printf "\e[32m*\e[0m CREATING CONTAINER FROM BASE, WAIT...\n"
lxc-copy --name "${BASE}" --newname "${NEW_CT}"

# Verifica se a cópia do container foi bem-sucedida
if [ $? -eq 0 ]; then
    printf "\033[32m*\033[0m CONTAINER CREATED SUCCESSFULLY\n"

    # Caminho do arquivo de configuração do container
    local lxc_config_path="/var/lib/lxc/$NEW_CT/config"

    # Verifica se o arquivo de configuração do container existe
    if [ ! -f "$lxc_config_path" ]; then
        printf "\e[31m*\e[0m ERROR: CONTAINER CONFIGURATION FILE \033[32m%s\033[0m NOT FOUND\n" "$NEW_CT"
        exit 1
    fi

    # Gera um UUID e cria um endereço MAC único
    local uuid=$(uuidgen | tr -d '-' | cut -c 1-12)
    local MAC_ADDRESS="00:16:3e:${uuid:0:2}:${uuid:2:2}:${uuid:4:2}"

    # Atualiza ou adiciona a configuração de endereço MAC no arquivo de configuração do container
    sed -i '/lxc.net.0.hwaddr/d' "$lxc_config_path"
    echo "lxc.net.0.hwaddr = $MAC_ADDRESS" >> "$lxc_config_path"

    # Inicia o novo container
    printf "\033[32m*\033[0m STARTING...\n"
    cp later.sh /var/lib/lxc/"${NEW_CT}"/rootfs/root/
    lxc-start --name "${NEW_CT}"

    # Torna o script later.sh executável e o executa dentro do container
    lxc-attach --name "${NEW_CT}" -- chmod +x /root/later.sh
    lxc-attach --name "${NEW_CT}" -- /root/later.sh
else
    printf "\e[31m*\e[0m ERROR CREATING CONTAINER \033[32m%s\033[0m.\n" "$NEW_CT"
    exit 1
fi
}

# Sequence
basect; newct