#!/bin/bash
# SCRIPT TO BUILD A PRODUCTION AND DEVELOPMENT SERVER FOLLOWING THE SPIRAL PATTERN

# --- Script Setup ---
# Move to the script's 'dep' subdirectory, making it runnable from anywhere.
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$SCRIPT_DIR/dep"

# Disable bash history for the session
unset HISTFILE

# ==============================================================================
# GLOBAL VARIABLE DECLARATIONS
# ==============================================================================
# Explicitly declare all global variables the script will create and use.
declare -g WAN0 WAN0_IPV4 WAN0_MASK WAN0_GATEWAY
declare -g LAN0 LAN0_IPV4 LAN0_MASK LAN0_GATEWAY
declare -g DOMAIN
declare -g TIMEZONE
declare -g HOSTNAME
declare -g TARGET_USER

# ==============================================================================
# FUNCTION DEFINITIONS
# ==============================================================================

# Function to update repository lists and upgrade installed packages.
update() {
    printf "\n\e[1;34m--- Starting System Update ---\e[0m\n"
    apt-get -y -qq update
    apt-get -y -qq upgrade
    printf "\n\e[1;34m--- System Update Complete ---\e[0m\n"
}

# Function to detect and configure network interfaces.
setup_interfaces() {
    printf "\n\e[1;34m--- Starting Network Interface Configuration ---\e[0m\n"
    local TARGET_IP="8.8.8.8"
    local BEST_INTERFACE=""
    local BEST_LATENCY="9999.0"

    printf "\n\e[32m*\e[0m Testando interfaces ativas para selecionar a melhor WAN0...\n"
    for IFACE in $(ip -o link show | awk -F': ' '/state UP/ && ($2 ~ /^(eth|en|enp)/) {sub(/@.*/, "", $2); print $2}'); do
        LATENCY=$(ping -I "$IFACE" -4 -c 3 "$TARGET_IP" 2>/dev/null | awk -F'/' 'END {print $5}')
        if [ -n "$LATENCY" ]; then
             if (( $(echo "$LATENCY < $BEST_LATENCY" | bc -l) )); then
                BEST_LATENCY="$LATENCY"
                BEST_INTERFACE="$IFACE"
            fi
        fi
    done

    WAN0="$BEST_INTERFACE"
    printf "\n\e[32m✅ Interface WAN0 selecionada: \033[1;32m%s\033[0m (Latência: %s ms)\n" "$WAN0" "$BEST_LATENCY"
    
    local IP_INFO
    IP_INFO=$(ip -4 addr show "$WAN0" | grep 'inet' | awk '{print $2}')
    WAN0_IPV4=$(echo "$IP_INFO" | cut -d'/' -f1)
    WAN0_MASK=$(echo "$IP_INFO" | cut -d'/' -f2)
    WAN0_GATEWAY=$(ip route | grep 'default' | grep "dev $WAN0" | awk '{print $3}')

    mapfile -t DOWN_INTERFACES < <(ip -o link show | awk -F': ' '/state DOWN/ && ($2 ~ /^(eth|en|enp)/) {sub(/@.*/, "", $2); print $2}')
    if [ ${#DOWN_INTERFACES[@]} -gt 0 ]; then
        printf "\n\e[32m*\e[0m As seguintes interfaces estão inativas. Escolha uma para LAN0:\n"
        for i in "${!DOWN_INTERFACES[@]}"; do
            printf "    \e[33m%d)\e[0m %s\n" "$((i+1))" "${DOWN_INTERFACES[$i]}"
        done
        
        local CHOICE
        read -p "  Digite o número da interface desejada: " CHOICE
        
        # Basic validation to ensure a valid choice is made
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#DOWN_INTERFACES[@]}" ]; then
            LAN0="${DOWN_INTERFACES[$((CHOICE-1))]}"
            printf "\n\e[32m✅ Interface LAN0 definida como: \033[1;32m%s\033[0m\n" "$LAN0"
        else
            printf "\n\e[31m❗ Opção inválida. Nenhuma interface LAN0 foi configurada.\e[0m\n"
        fi
    fi
    printf "\n\e[1;34m--- Network Interface Configuration Complete ---\e[0m\n"
}

# Function to interactively ask the user for a domain name.
prompt_for_domain() {
    printf "\n\e[1;34m--- Domain Name Setup ---\e[0m\n"
    read -p $'\n\e[32m*\e[0m Please enter the domain name (e.g., example.local): ' DOMAIN
    DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]')
}

# Function for global system settings (timezone).
global_settings() {
    printf "\n\e[1;34m--- Starting Timezone Configuration ---\e[0m\n"
    TIMEZONE="America/Sao_Paulo"
    timedatectl set-timezone "$TIMEZONE" > /dev/null 2>&1
    printf "\n\e[1;34m--- Timezone Configuration Complete ---\e[0m\n"
}

# Function to set a new system hostname.
set_hostname() {
    printf "\n\e[1;34m--- Starting Hostname Configuration ---\e[0m\n"
    HOSTNAME="utm$(shuf -i 10000-99999 -n 1)"
    printf "%s" "$HOSTNAME" > /etc/hostname
    local HOSTS_CONTENT="127.0.0.1       localhost
127.0.1.1       $HOSTNAME

::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters"
    printf "%s" "$HOSTS_CONTENT" > /etc/hosts
    printf "\n\e[1;34m--- Hostname Configuration Complete ---\e[0m\n"
}

# Function to create the target user and configure their environment.
setup_target_user() {
    TARGET_USER="sysop"
    printf "\n\e[1;34m--- Starting User Configuration ---\e[0m\n"
    apt-get -y -qq install sudo
    sed -i '$ a unset HISTFILE\nexport HISTSIZE=0\nexport HISTFILESIZE=0\nexport HISTCONTROL=ignoreboth' /etc/profile
    groupadd -g 1001 sysop > /dev/null 2>&1
    useradd -m -u 1001 -g 1001 -c "SysOp" -s /bin/bash sysop > /dev/null 2>&1
    /sbin/usermod -aG sudo "$TARGET_USER" > /dev/null 2>&1
    printf "\n\e[1;34m--- User Configuration Complete ---\e[0m\n"
}

# Function to generate and set system passwords.
set_passwords() {
    printf "\n\e[1;34m--- Starting Password Configuration ---\e[0m\n"
    apt-get -y -qq install pwgen
    local PASSWORD_ROOT; PASSWORD_ROOT=$(pwgen -s 18 1)
    local PASSWORD_TARGET; PASSWORD_TARGET=$(pwgen -s 18 1)
    echo "root:$PASSWORD_ROOT" | chpasswd
    echo "$TARGET_USER:$PASSWORD_TARGET" | chpasswd

    printf "\n\e[1;33m--- 🔑 IMPORTANT: Generated Passwords ---\e[0m\n"
    printf "\e[32m*\e[0m User \e[1;32m%-12s\e[0m -> Password: \e[1;37m%s\e[0m\n" "Root" "$PASSWORD_ROOT"
    printf "\e[32m*\e[0m User \e[1;32m%-12s\e[0m -> Password: \e[1;37m%s\e[0m\n" "$TARGET_USER" "$PASSWORD_TARGET"
    printf "\e[1;33m------------------------------------------\e[0m\n"
    printf "\n\e[1;34m--- Password Configuration Complete ---\e[0m\n"
}

# Main function to install all required software packages.
packages() {
    install_package_category() {
        local category_name="$1"; local packages_to_install="$2"
        apt-get -y -qq install $packages_to_install
    }
    printf "\n\e[1;34m--- Starting Package Installation ---\e[0m\n"
    install_package_category "Text Editor" "vim"
    install_package_category "Network Tools" "nfs-common tcpdump traceroute iperf ethtool geoip-bin socat speedtest-cli bridge-utils"
    install_package_category "Security Tools" "apparmor-utils"
    install_package_category "Compression and Archiving" "unzip xz-utils bzip2 pigz"
    install_package_category "Scripting and Automation" "sshpass python3-apt"
    install_package_category "System Monitoring" "screen htop sysstat stress lm-sensors nload smartmontools"
    install_package_category "Disk and File System Utilities" "hdparm dosfstools cryptsetup uuid rsync"
    install_package_category "Connectivity Utilities" "net-tools"
    install_package_category "Power Management" "pm-utils acpi acpid fwupd"
    install_package_category "Resource Control" "cpulimit"
    install_package_category "Network Firmware" "firmware-misc-nonfree firmware-realtek firmware-atheros"
    install_package_category "Additional Utilities" "tree"
    printf "\n\e[1;34m--- Package Installation Complete ---\e[0m\n"
}

# Function to create system and user directories.
create_directories() {
    printf "\n\e[1;34m--- Starting Directory Creation ---\e[0m\n"
    mkdir -p /mnt/{Temp,Local/{Container/{A,B},USB/{A,B}},Remote/Servers}
    mkdir -p /root/{Temp,.services/scheduled,.crypt}
    chmod 600 /root/.crypt
    mkdir -p /var/log/rsync
    chown "$TARGET_USER":"$TARGET_USER" -R /var/log/rsync
    su - "$TARGET_USER" -c "mkdir -p /home/$TARGET_USER/{Temp,.services/scheduled,.crypt}" > /dev/null 2>&1
    printf "\n\e[1;34m--- Directory Creation Complete ---\e[0m\n"
}

# Function to set up the main systemd trigger service.
setup_trigger_service() {
    printf "\n\e[1;34m--- Starting Systemd Service Setup ---\e[0m\n"
    cp systemd/trigger.service /etc/systemd/system/
    systemctl enable trigger --quiet
    mkdir -p /root/.services
    cp systemd/scripts/main.sh /root/.services/
    chmod 700 /root/.services/main.sh
    printf "\n\e[1;34m--- Systemd Service Setup Complete ---\e[0m\n"
}

# Main function to configure various network services.
setup_network_services() {
    setup_dhcp() {
        printf "\n\e[1;36m---  Configuring DHCP (KEA)  ---\e[0m\n"
        apt-get -y -qq install kea-dhcp4-server
        rm -f /etc/kea/kea-dhcp4.conf
        cp DHCP/kea-dhcp4.conf /etc/kea/
    }
    setup_ntp() {
        printf "\n\e[1;36m---  Configuring NTP (Chrony)  ---\e[0m\n"
        apt-get -y -qq install chrony
        local CHRONY_CONFIG_ADDITIONS
        CHRONY_CONFIG_ADDITIONS=$(cat <<'EOF'

# Servidores NTP Upstream
pool b.st1.ntp.br iburst
pool a.st1.ntp.br iburst
pool 200.186.125.195 iburst

# Interface de escuta e resposta
allow all
EOF
)
        sed -i '/^pool 2\.debian\.pool\.ntp\.org iburst/d' /etc/chrony/chrony.conf && printf "%s" "$CHRONY_CONFIG_ADDITIONS" >> /etc/chrony/chrony.conf
        systemctl restart chrony > /dev/null 2>&1
    }
    setup_dns() {
        printf "\n\e[1;36m---  Configuring DNS (BIND9)  ---\e[0m\n"
        apt-get -y -qq install bind9 bind9-utils bind9-doc dnsutils tcpdump cron
        rm -r /etc/bind
        mkdir -p /etc/bind/{zones,keys} && chmod 2755 /etc/bind && cd /etc/bind && chown bind:bind /etc/bind/* && chmod 755 zones && chmod 750 keys
        rndc-confgen -a > /dev/null 2>&1 && chown bind:bind rndc.key && chmod 640 rndc.key
        cd keys
        dnssec-keygen -a ECDSAP256SHA256 -n ZONE "$DOMAIN" > /dev/null 2>&1 && dnssec-keygen -a ECDSAP256SHA256 -n ZONE -f KSK "$DOMAIN" > /dev/null 2>&1 && chown bind:bind ./* && chmod 600 ./*.private && chmod 644 ./*.key
        cd ../
        local NAMED_CONF_CONTENT='include "/etc/bind/rndc.key";\ninclude "/etc/bind/named.conf.options";\ninclude "/etc/bind/named.conf.local";\n'
        local OPTIONS_CONTENT='options {\n    directory "/var/cache/bind";\n    recursion yes;\n    allow-query { any; };\n    listen-on { any; };\n    listen-on-v6 { none; };\n    forwarders {\n        1.1.1.1;\n        8.8.8.8;\n        9.9.9.9;\n    };\n    forward only;\n    dnssec-validation auto;\n};\n'
        printf "$NAMED_CONF_CONTENT" > named.conf && chown bind:bind named.conf && chmod 644 named.conf && printf "$OPTIONS_CONTENT" > named.conf.options && chown bind:bind named.conf.options && chmod 644 named.conf.options
        local NEW_SERIAL ADDRESS KEY_FILES ZSK_KEY KSK_KEY
        NEW_SERIAL=$(date '+%Y%m%d%H')
        ADDRESS="0.0.0.0"
        KEY_FILES=$(find /etc/bind/keys -type f -iname "K${DOMAIN}.*.key" | sort)
        ZSK_KEY=$(echo "$KEY_FILES" | head -1)
        KSK_KEY=$(echo "$KEY_FILES" | tail -1)
        local ZONE_CONTENT
        ZONE_CONTENT=$(printf '$TTL    86400\n@       IN      SOA     ns1.%s. admin.%s. (\n                        %s ; Serial\n                        3600       ; Refresh\n                        1800       ; Retry\n                        604800     ; Expire\n                        86400      ; Minimum TTL\n                )\n; Name servers\n        IN      NS      ns1.%s.\nns1     IN      A       %s\n\n; Zone records\n@       IN      A       %s\n\n; Include DNSSEC keys\n$INCLUDE "%s"\n$INCLUDE "%s"\n' "$DOMAIN" "$DOMAIN" "$NEW_SERIAL" "$DOMAIN" "$ADDRESS" "$ADDRESS" "$ZSK_KEY" "$KSK_KEY")
        printf "%s" "$ZONE_CONTENT" > zones/"db.$DOMAIN" && chown bind:bind zones/"db.$DOMAIN" && chmod 644 zones/"db.$DOMAIN"
        dnssec-signzone -A -3 $(head /dev/urandom | tr -dc A-F0-9 | head -c8) -N INCREMENT -o "$DOMAIN" -t -K keys zones/"db.$DOMAIN" > /dev/null 2>&1 && chown bind:bind zones/"db.$DOMAIN.signed" && chmod 644 zones/"db.$DOMAIN.signed"
        local ZONE_CONFIG_CONTENT
        ZONE_CONFIG_CONTENT=$(printf 'zone "%s" {\n    type master;\n    file "/etc/bind/zones/db.%s.signed";\n    allow-transfer { none; };\n};\n' "$DOMAIN" "$DOMAIN")
        printf "%s" "$ZONE_CONFIG_CONTENT" > named.conf.local && chown bind:bind named.conf.local && chmod 644 named.conf.local
        systemctl restart named --quiet
        sleep 3; rndc status > /dev/null 2>&1; rndc reload > /dev/null 2>&1; systemctl disable --now named --quiet
        cd / 
    }
    printf "\n\e[1;34m--- Starting Network Configuration ---\e[0m\n"
    systemctl disable networking --quiet && systemctl disable ModemManager --quiet && systemctl disable wpa_supplicant --quiet && systemctl disable NetworkManager.service --quiet
    setup_dhcp
    setup_ntp
    setup_dns
    printf "\n\e[1;34m--- Network Configuration Complete ---\e[0m\n"
}

cd "$SCRIPT_DIR/dep"

# Function to set up the firewall.
setup_firewall() {
    printf "\n\e[1;34m--- Starting Firewall Setup ---\e[0m\n"
    apt-get -y -qq install nftables
    systemctl disable --now nftables --quiet
    cp -r systemd/scripts/firewall /root/.services/
    chmod 700 /root/.services/firewall/*
    printf "\n\e[1;34m--- Firewall Setup Complete ---\e[0m\n"
}

# Main function to set up KVM and LXC hypervisor technologies.
setup_hypervisor() {
    setup_kvm() {
        printf "\n\e[1;36m---  Configuring KVM Hypervisor  ---\e[0m\n"
        apt-get -y -qq install qemu-kvm libvirt0 libvirt-daemon-system
        systemctl disable --now libvirtd --quiet
        gpasswd libvirt -a "$TARGET_USER" > /dev/null 2>&1
        local CPU
        CPU=$(lscpu | grep -E 'Vendor ID|ID de fornecedor' | cut -f 2 -d ":" | sed -n 1p | awk '{$1=$1}1')
        case "$CPU" in
            GenuineIntel)
                printf 'options kvm_intel nested=1' > /etc/modprobe.d/kvm.conf && /sbin/modprobe -r kvm_intel > /dev/null 2>&1 && /sbin/modprobe kvm_intel > /dev/null 2>&1
                ;;
            AuthenticAMD)
                printf 'options kvm_amd nested=1' > /etc/modprobe.d/kvm.conf && /sbin/modprobe -r kvm_amd > /dev/null 2>&1 && /sbin/modprobe kvm_amd > /dev/null 2>&1
                ;;
        esac
        mkdir -p /var/log/virsh && chown "$TARGET_USER":"$TARGET_USER" -R /var/log/virsh
        cp systemd/scripts/virtual-machine.sh /root/.services/ && chmod 700 /root/.services/virtual-machine.sh
    }
    setup_lxc() {
        printf "\n\e[1;36m---  Configuring LXC Containers  ---\e[0m\n"
        apt-get -y -qq install lxc
        sed -i '/^\s*}$/i \ \ /mnt\/Local\/Container\/A\/lxc\/** rw,\n\ \ mount options=(rw, move) -> /mnt\/Local\/Container\/A\/lxc\/**,' /etc/apparmor.d/usr.bin.lxc-copy && apparmor_parser -r /etc/apparmor.d/usr.bin.lxc-copy > /dev/null 2>&1
        systemctl disable --now lxc --quiet && systemctl disable --now lxc-net --quiet && systemctl mask lxc-net --quiet
        rm -f /etc/default/lxc-net && rm -f /etc/lxc/default.conf
        local LXC_CONF_CONTENT='lxc.net.0.type = veth
lxc.net.0.link = br_tap110
lxc.net.0.flags = up

lxc.apparmor.profile = generated
lxc.apparmor.allow_nesting = 1'
        printf "%s" "$LXC_CONF_CONTENT" > /etc/lxc/default.conf
        mkdir -p /var/log/lxc && chown "$TARGET_USER":"$TARGET_USER" -R /var/log/lxc
        cp systemd/scripts/container.sh /root/.services/ && chmod 700 /root/.services/container.sh
    }
    printf "\n\e[1;34m--- Starting Hypervisor Setup ---\e[0m\n"
    setup_kvm
    setup_lxc
    printf "\n\e[1;34m--- Hypervisor Setup Complete ---\e[0m\n"
}

# Function to set up and configure the SSH service and keys.
setup_ssh() {
    printf "\n\e[1;34m--- Starting SSH Configuration ---\e[0m\n"
    apt-get -y -qq install openssh-server sshfs autossh

    if [ -f "sshd_config" ]; then
        rm -f /etc/ssh/sshd_config
        cp sshd_config /etc/ssh/ && chmod 644 /etc/ssh/sshd_config
    else
        printf "\n\e[33mℹ️  Custom 'sshd_config' not found in 'dep' directory. Using default.\n"
    fi

    rm -f /etc/motd && touch /etc/motd

    # --- Root SSH Setup ---
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
    # Force overwrite of SSH key if it exists
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N '' <<<$'\n' > /dev/null 2>&1

    # --- Target User SSH Setup ---
    local USER_HOME
    USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    
    su - "$TARGET_USER" -c "mkdir -p ~/.ssh; \
                           ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N '' <<<\$'\n' >/dev/null 2>&1; \
                           touch ~/.ssh/authorized_keys"
                           
    chmod 700 "$USER_HOME/.ssh"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"

    printf "\n\e[1;34m--- SSH Configuration Complete ---\e[0m\n"
}

# Function to configure the custom spawn service.
setup_spawn_service() {
    printf "\n\e[1;34m--- Starting Spawn Service Configuration ---\e[0m\n"
    cp -r spawn /etc/ && chmod 700 /etc/spawn/CT/*.sh
    local USER_HOME
    USER_HOME=$(eval echo ~$TARGET_USER)
    ln -sf /etc/spawn/CT/spawn.sh "$USER_HOME"/.spawn
    ln -sf /etc/spawn/CT/spawn.sh /root/.spawn && chown -h sysop:sysop /root/.spawn
    printf "\n\e[1;34m--- Spawn Service Configuration Complete ---\e[0m\n"
}

# Function to configure the GRUB bootloader.
setup_grub() {
    printf "\n\e[1;34m--- Starting GRUB Configuration ---\e[0m\n"
    local GRUB_CONTENT
    GRUB_CONTENT=$(cat <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
EOF
)
    rm -f /etc/default/grub && printf "%s" "$GRUB_CONTENT" > /etc/default/grub && chmod 644 /etc/default/grub
    update-grub
    printf "\n\e[1;34m--- GRUB Configuration Complete ---\e[0m\n"
}

# Function to schedule a cleanup script to run once after the next reboot.
schedule_post_reboot_cleanup() {
    printf "\n\e[1;34m--- Scheduling Post-Reboot Cleanup ---\e[0m\n"
    local INITIAL_USER
    INITIAL_USER=$(grep ':1000:' /etc/passwd | cut -f 1 -d ":")
    local SCRIPT_CONTENT
    printf -v SCRIPT_CONTENT '#!/bin/bash
### BEGIN INIT INFO
# Provides:          later
# Required-Start:    $all
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:
# Short-Description: Post-reboot cleanup procedures.
### END INIT INFO
pkill -u %s
userdel -r %s
rm -rf /root/WS
rm -f /etc/init.d/later
' "$INITIAL_USER" "$INITIAL_USER"
    printf "%s" "$SCRIPT_CONTENT" > /etc/init.d/later && chmod +x /etc/init.d/later
    update-rc.d later defaults > /dev/null 2>&1
    printf "\n\e[1;34m--- Post-Reboot Cleanup Scheduled ---\e[0m\n"
}

# Function to perform final cleanup and prompt for a system reboot.
finalize_setup() {
    printf "\n\e[1;34m--- Finalizing Setup ---\e[0m\n"
    apt-get -y -qq autoremove
    rm -f /etc/network/interfaces
    printf "\n\e[1;32m✅ INSTALLATION COMPLETED SUCCESSFULLY!\e[0m\n"
    local response
    read -p $'\n\e[33m?\e[0m DO YOU WANT TO RESTART NOW? (y/n): ' response
    response=${response,,}
    if [[ "$response" == "y" ]]; then
        printf "\n\e[32m*\e[0m RESTARTING...\n"
        # systemctl reboot
    fi
    if [[ "$response" == "n" ]]; then
        printf "\n\e[32m*\e[0m Task complete. Please reboot the system later to apply all changes.\n"
    fi
}

# ==============================================================================
# MAIN ORCHESTRATION
# ==============================================================================
main() {
    update
    setup_interfaces
    prompt_for_domain
    global_settings
    set_hostname
    setup_target_user
    set_passwords
    packages
    create_directories
    setup_ssh
    setup_spawn_service
    setup_network_services
    setup_firewall
    setup_hypervisor
    setup_trigger_service
    setup_grub
    schedule_post_reboot_cleanup
    finalize_setup
}

# --- Execute main function ---
main