#!/bin/bash
# SCRIPT TO BUILD A PRODUCTION AND DEVELOPMENT SERVER FOLLOWING THE SPIRAL PATTERN

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Script Setup ---
# Move to the script's 'dep' subdirectory, making it runnable from anywhere.
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if [ -d "$SCRIPT_DIR/dep" ]; then
    cd "$SCRIPT_DIR/dep"
else
    echo "ERROR: 'dep' subdirectory not found in script location."
    exit 1
fi

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
    printf "\n\e[32m*\e[0m Updating package lists (apt-get update)...\n"
    if apt-get -y update > /dev/null 2>&1; then
        printf "  \e[32m✅ Success\e[0m\n"
        printf "\n\e[32m*\e[0m Upgrading installed packages (apt-get upgrade)...\n"
        if apt-get -y upgrade > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error during package upgrade.\e[0m\n"
        fi
    else
        printf "  \e[31m❗ Error during package list update.\e[0m\n"
        printf "  \e[33mℹ️ Skipping package upgrade due to update failure.\e[0m\n"
    fi
    printf "\n\e[1;34m--- System Update Complete ---\e[0m\n"
}

# Function to detect and configure network interfaces.
setup_interfaces() {
    printf "\n\e[1;34m--- Starting Network Interface Configuration ---\e[0m\n"
    printf "\n\e[32m*\e[0m Choosing the best interface for WAN0 (active), please wait...\n"
    local TARGET_IP="8.8.8.8"
    local BEST_INTERFACE=""
    local BEST_LATENCY="9999.0"

    for IFACE in $(ip -o link show | awk -F': ' '/state UP/ && ($2 ~ /^(eth|en|enp)/) {sub(/@.*/, "", $2); print $2}'); do
        LATENCY=$(ping -I "$IFACE" -4 -c 3 "$TARGET_IP" 2>/dev/null | awk -F'/' 'END {print $5}')
        if [ -n "$LATENCY" ]; then
            printf "  \e[36m✔\e[0m Interface \033[32m%-10s\033[0m -> Latency: \033[32m%s ms\033[0m\n" "$IFACE" "$LATENCY"
            if (( $(echo "$LATENCY < $BEST_LATENCY" | bc -l) )); then
                BEST_LATENCY="$LATENCY"
                BEST_INTERFACE="$IFACE"
            fi
        else
            printf "  \e[31m✖\e[0m Interface \033[31m%-10s\033[0m -> Ping failed for %s\n" "$IFACE" "$TARGET_IP"
        fi
    done

    if [ -n "$BEST_INTERFACE" ]; then
        WAN0="$BEST_INTERFACE"
        printf "\n\e[32m✅ BEST INTERFACE FOR WAN0 SET: \033[1;32m%s\033[0m (Latency: %s ms)\n" "$WAN0" "$BEST_LATENCY"
        printf "\e[32m*\e[0m Fetching network details for \033[1;32m%s\033[0m...\n" "$WAN0"
        local IP_INFO
        IP_INFO=$(ip -4 addr show "$WAN0" | grep 'inet' | awk '{print $2}')
        if [ -n "$IP_INFO" ]; then
            WAN0_IPV4=$(echo "$IP_INFO" | cut -d'/' -f1)
            WAN0_MASK=$(echo "$IP_INFO" | cut -d'/' -f2)
        fi
        WAN0_GATEWAY=$(ip route | grep 'default' | grep "dev $WAN0" | awk '{print $3}')
    else
        printf "\n\e[31m❗ NO FUNCTIONAL ACTIVE INTERFACE FOUND FOR WAN0.\n"
    fi

    printf "\n\e[32m*\e[0m Searching for interfaces for LAN0 (inactive)...\n"
    local DOWN_INTERFaces
    mapfile -t DOWN_INTERFACES < <(ip -o link show | awk -F': ' '/state DOWN/ && ($2 ~ /^(eth|en|enp)/) {sub(/@.*/, "", $2); print $2}')
    if [ ${#DOWN_INTERFACES[@]} -gt 0 ]; then
        printf "  The following interfaces are inactive. Choose one for LAN0:\n"
        for i in "${!DOWN_INTERFACES[@]}"; do
            printf "    \e[33m%d)\e[0m %s\n" "$((i+1))" "${DOWN_INTERFACES[$i]}"
        done
        while true; do
            read -p "  Enter the number of the desired interface: " CHOICE
            if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#DOWN_INTERFACES[@]}" ]; then
                LAN0="${DOWN_INTERFACES[$((CHOICE-1))]}"
                printf "\n\e[32m✅ INTERFACE FOR LAN0 SET: \033[1;32m%s\033[0m\n" "$LAN0"
                printf "\n  Now, configure the network details for \033[1;32m%s\033[0m:\n" "$LAN0"
                while true; do
                    read -p "  -> IPv4 Address: " LAN0_IPV4
                    if [[ -n "$LAN0_IPV4" && "$LAN0_IPV4" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                        break
                    else
                        printf "     \e[31mInvalid or empty IPv4 address. Please try again.\e[0m\n"
                    fi
                done
                while true; do
                    read -p "  -> Subnet Mask Prefix (1-32): " LAN0_MASK
                    if [[ "$LAN0_MASK" =~ ^[0-9]+$ ]] && [ "$LAN0_MASK" -ge 1 ] && [ "$LAN0_MASK" -le 32 ]; then
                        break
                    else
                        printf "     \e[31mInvalid prefix. Please enter a number between 1 and 32.\e[0m\n"
                    fi
                done
                read -p "  -> Gateway (optional, press Enter to skip): " LAN0_GATEWAY
                break
            else
                printf "  \e[31mInvalid option. Try again.\e[0m\n"
            fi
        done
    else
        printf "\n\e[33mℹ️ No inactive interfaces found to be candidates for LAN0.\n"
    fi
    printf "\n\e[1;34m--- Network Interface Configuration Complete ---\e[0m\n"
}

# Function to interactively ask the user for a domain name.
prompt_for_domain() {
    validate_domain() {
        local domain_to_check=$1
        if [[ $domain_to_check =~ ^[a-zA-Z0-9.-]+$ ]]; then return 0; else return 1; fi
    }
    printf "\n\e[1;34m--- Domain Name Setup ---\e[0m\n"
    while true; do
        read -p $'\n\e[32m*\e[0m Please enter the domain name (e.g., example.local): ' DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            printf "  \e[31m❗ Domain name cannot be empty. Please provide a valid domain.\e[0m\n"
            continue
        fi
        DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]')
        if validate_domain "$DOMAIN"; then
            printf "  \e[32m✅ Domain set to:\e[0m \e[1;33m%s\e[0m\n" "$DOMAIN"
            break
        else
            printf "  \e[31m❗ Invalid domain name. Use only alphanumeric characters, hyphens, and dots.\e[0m\n"
        fi
    done
}

# Function for global system settings (timezone).
global_settings() {
    printf "\n\e[1;34m--- Starting Timezone Configuration ---\e[0m\n"
    TIMEZONE="America/Sao_Paulo"
    printf "\n\e[32m*\e[0m Setting system timezone to \e[1;33m%s\e[0m...\n" "$TIMEZONE"
    if timedatectl status | grep -q "Time zone: $TIMEZONE"; then
        printf "  \e[33mℹ️ Timezone is already set to %s. Skipping.\e[0m\n" "$TIMEZONE"
    else
        if timedatectl set-timezone "$TIMEZONE" > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error setting timezone.\e[0m\n"
        fi
    fi
    printf "\n\e[1;34m--- Timezone Configuration Complete ---\e[0m\n"
}

# Function to set a new system hostname.
set_hostname() {
    printf "\n\e[1;34m--- Starting Hostname Configuration ---\e[0m\n"
    printf "\n\e[32m*\e[0m Generating new hostname...\n"
    HOSTNAME="utm$(shuf -i 10000-99999 -n 1)"
    printf "  \e[32m✅ Generated hostname: \e[1;33m%s\e[0m\n" "$HOSTNAME"

    printf "\n\e[32m*\e[0m Updating /etc/hostname file...\n"
    if printf "%s" "$HOSTNAME" > /etc/hostname; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error writing to /etc/hostname.\e[0m\n"
    fi

    printf "\n\e[32m*\e[0m Updating /etc/hosts file...\n"
    local HOSTS_CONTENT="127.0.0.1       localhost
127.0.1.1       $HOSTNAME

::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters"
    if printf "%s" "$HOSTS_CONTENT" > /etc/hosts; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error writing to /etc/hosts.\e[0m\n"
    fi
    printf "\n\e[1;34m--- Hostname Configuration Complete ---\e[0m\n"
}

# Function to create the target user and configure their environment.
setup_target_user() {
    TARGET_USER="sysop"
    printf "\n\e[1;34m--- Starting User Configuration ---\e[0m\n"
    printf "\n\e[32m*\e[0m Installing sudo package...\n"
    if apt-get -y install sudo > /dev/null 2>&1; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[33mℹ️  Could not install package (it may already be installed).\e[0m\n"
    fi

    printf "\n\e[32m*\e[0m Disabling command history in /etc/profile...\n"
    if grep -q "unset HISTFILE" /etc/profile; then
        printf "  \e[33mℹ️ History settings already exist in /etc/profile. Skipping.\e[0m\n"
    else
        if sed -i '$ a unset HISTFILE\nexport HISTSIZE=0\nexport HISTFILESIZE=0\nexport HISTCONTROL=ignoreboth' /etc/profile; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
    fi

    printf "\n\e[32m*\e[0m Creating group 'sysop' (GID 1001)...\n"
    if grep -q "^sysop:" /etc/group; then
        printf "  \e[33mℹ️ Group 'sysop' already exists. Skipping.\e[0m\n"
    else
        if groupadd -g 1001 sysop > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error creating group 'sysop'.\e[0m\n"
        fi
    fi

    printf "\n\e[32m*\e[0m Creating user 'sysop' (UID 1001)...\n"
    if id "sysop" > /dev/null 2>&1; then
        printf "  \e[33mℹ️ User 'sysop' already exists. Skipping.\e[0m\n"
    else
        if useradd -m -u 1001 -g 1001 -c "SysOp" -s /bin/bash sysop > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error creating user 'sysop'.\e[0m\n"
        fi
    fi

    printf "\n\e[32m*\e[0m Adding user '%s' to the 'sudo' group...\n" "$TARGET_USER"
    if id "$TARGET_USER" > /dev/null 2>&1; then
        if groups "$TARGET_USER" | grep -q "\bsudo\b"; then
             printf "  \e[33mℹ️ User '%s' is already in the sudo group. Skipping.\e[0m\n" "$TARGET_USER"
        else
            if /sbin/usermod -aG sudo "$TARGET_USER" > /dev/null 2>&1; then
                printf "  \e[32m✅ Success\e[0m\n"
            else
                printf "  \e[31m❗ Error\e[0m\n"
            fi
        fi
    else
        printf "  \e[31m❗ Error: User '%s' does not exist.\e[0m\n" "$TARGET_USER"
    fi
    printf "\n\e[1;34m--- User Configuration Complete ---\e[0m\n"
}

# Function to generate and set system passwords.
set_passwords() {
    printf "\n\e[1;34m--- Starting Password Configuration ---\e[0m\n"
    printf "\n\e[32m*\e[0m Installing password generation tool (pwgen)...\n"
    if apt-get -y install pwgen > /dev/null 2>&1; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[33mℹ️  Could not install package (it may already be installed).\e[0m\n"
    fi

    printf "\n\e[32m*\e[0m Generating secure passwords...\n"
    local PASSWORD_ROOT; PASSWORD_ROOT=$(pwgen -s 18 1)
    local PASSWORD_TARGET; PASSWORD_TARGET=$(pwgen -s 18 1)
    printf "  \e[32m✅ Success\e[0m\n"

    printf "\n\e[32m*\e[0m Verifying user '%s' exists...\n" "$TARGET_USER"
    if ! id "$TARGET_USER" &>/dev/null; then
        printf "  \e[31m❗ Error: User '%s' does not exist.\e[0m\n" "$TARGET_USER"; return 1;
    else
        printf "  \e[32m✅ Success\e[0m\n"
    fi

    printf "\n\e[32m*\e[0m Setting password for 'root' user...\n"
    if echo "root:$PASSWORD_ROOT" | chpasswd; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error changing root password.\e[0m\n"; return 1;
    fi

    printf "\n\e[32m*\e[0m Setting password for '%s' user...\n" "$TARGET_USER"
    if echo "$TARGET_USER:$PASSWORD_TARGET" | chpasswd; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error changing password for user '%s'.\e[0m\n" "$TARGET_USER"; return 1;
    fi

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
        printf "\n\e[32m*\e[0m INSTALLING CATEGORY: \e[1;33m%s\e[0m...\n" "$category_name"
        if apt-get -y install $packages_to_install > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
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
    printf "\n\e[32m*\e[0m Creating directories under /mnt...\n"
    if mkdir -p /mnt/{Temp,Local/{Container/{A,B},USB/{A,B}},Remote/Servers}; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error\e[0m\n"
    fi
    printf "\n\e[32m*\e[0m Creating directories under /root...\n"
    if mkdir -p /root/{Temp,.services/scheduled,.crypt}; then
        printf "  \e[32m✅ Success\e[0m\n"
        printf "\n\e[32m*\e[0m Adjusting permissions for /root/.crypt...\n"
        if chmod 600 /root/.crypt; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
    else
        printf "  \e[31m❗ Error\e[0m\n"
    fi
    if [ -z "$TARGET_USER" ]; then
        printf "\n\e[31m❗ Error: TARGET_USER variable is not set. Skipping rsync directory creation.\e[0m\n"
    else
        printf "\n\e[32m*\e[0m Creating rsync log directory...\n"
        if mkdir -p /var/log/rsync; then
            printf "  \e[32m✅ Success\e[0m\n"
            printf "\n\e[32m*\e[0m Setting ownership for /var/log/rsync to '%s'...\n" "$TARGET_USER"
            if chown "$TARGET_USER":"$TARGET_USER" -R /var/log/rsync; then
                printf "  \e[32m✅ Success\e[0m\n"
            else
                printf "  \e[31m❗ Error\e[0m\n"
            fi
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
    fi
    if [ -z "$TARGET_USER" ]; then
        printf "\n\e[31m❗ Error: TARGET_USER variable is not set. Skipping user directory creation.\e[0m\n"
    else
        printf "\n\e[32m*\e[0m Creating home directories for user '%s'...\n" "$TARGET_USER"
        if su - "$TARGET_USER" -c "mkdir -p /home/$TARGET_USER/{Temp,.services/scheduled,.crypt}" > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
    fi
    printf "\n\e[1;34m--- Directory Creation Complete ---\e[0m\n"
}

# Function to set up the main systemd trigger service.
setup_trigger_service() {
    printf "\n\e[1;34m--- Starting Systemd Service Setup ---\e[0m\n"
    printf "\n\e[32m*\e[0m Copying systemd service file (trigger.service)...\n"
    if cp systemd/trigger.service /etc/systemd/system/; then
        printf "  \e[32m✅ Success\e[0m\n"
        printf "\n\e[32m*\e[0m Enabling 'trigger' service...\n"
        if systemctl enable trigger --quiet; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error enabling the systemd service.\e[0m\n"
        fi
    else
        printf "  \e[31m❗ Error copying service file. Check if 'systemd/trigger.service' exists.\e[0m\n"
    fi
    printf "\n\e[32m*\e[0m Copying main service script (main.sh)...\n"
    mkdir -p /root/.services
    if cp systemd/scripts/main.sh /root/.services/; then
        printf "  \e[32m✅ Success\e[0m\n"
        printf "\n\e[32m*\e[0m Adjusting permissions for the main service script...\n"
        if chmod 700 /root/.services/main.sh; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error setting permissions.\e[0m\n"
        fi
    else
        printf "  \e[31m❗ Error copying main script. Check if 'systemd/scripts/main.sh' exists.\e[0m\n"
    fi
    printf "\n\e[1;34m--- Systemd Service Setup Complete ---\e[0m\n"
}

# Main function to configure various network services.
setup_network_services() {
    setup_dhcp() {
        printf "\n\e[1;36m---  Configuring DHCP (KEA)  ---\e[0m\n"

        printf "\n\e[32m*\e[0m Installing KEA DHCPv4 server...\n"
        if apt-get -y install kea-dhcp4-server > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[33mℹ️  Could not install package (it may already be installed).\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Removing default KEA configuration file...\n"
        if rm -f /etc/kea/kea-dhcp4.conf; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error: Failed to remove file (it may not have existed, which is OK).\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Copying new KEA DHCPv4 configuration file...\n"
        if [ ! -f "DHCP/kea-dhcp4.conf" ]; then
            printf "  \e[31m❗ Error: Source file 'DHCP/kea-dhcp4.conf' not found.\e[0m\n"
        elif cp DHCP/kea-dhcp4.conf /etc/kea/; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error: Failed to copy configuration file.\e[0m\n"
        fi
    }
    setup_ntp() {
        printf "\n\e[1;36m---  Configuring NTP (Chrony)  ---\e[0m\n"
        printf "\n\e[32m*\e[0m Installing new time service (chrony)...\n"
        if apt-get install -y chrony > /dev/null 2>&1; then printf "  \e[32m✅ Success\e[0m\n"; else printf "  \e[31m❗ Error installing chrony.\e[0m\n"; return 1; fi
        printf "\n\e[32m*\e[0m Configuring chrony NTP servers...\n"
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
        if sed -i '/^pool 2\.debian\.pool\.ntp\.org iburst/d' /etc/chrony/chrony.conf && printf "%s" "$CHRONY_CONFIG_ADDITIONS" >> /etc/chrony/chrony.conf; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error modifying /etc/chrony/chrony.conf.\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Restarting chrony service to apply changes...\n"
        if systemctl restart chrony > /dev/null 2>&1; then printf "  \e[32m✅ Success\e[0m\n"; else printf "  \e[31m❗ Error restarting chrony.\e[0m\n"; fi
    }
    setup_dns() {
        printf "\n\e[1;36m---  Configuring DNS (BIND9)  ---\e[0m\n"
        printf "\n\e[32m*\e[0m Installing BIND9 and utilities...\n"
        if apt-get -y install bind9 bind9-utils bind9-doc dnsutils tcpdump cron > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error installing BIND9 packages.\e[0m\n"; return 1;
        fi
        printf "\n\e[32m*\e[0m Creating BIND9 directory structure...\n"
        if [ -d "/etc/bind" ]; then rm -r /etc/bind; fi
        if mkdir -p /etc/bind/{zones,keys} && chmod 2755 /etc/bind && cd /etc/bind && chown bind:bind /etc/bind/* && chmod 755 zones && chmod 750 keys; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error creating BIND9 directories.\e[0m\n"; return 1;
        fi
        printf "\n\e[32m*\e[0m Generating RNDC key...\n"
        if rndc-confgen -a > /dev/null 2>&1 && chown bind:bind rndc.key && chmod 640 rndc.key; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error generating RNDC key.\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Generating DNSSEC keys for '%s'...\n" "$DOMAIN"
        cd keys
        if dnssec-keygen -a ECDSAP256SHA256 -n ZONE "$DOMAIN" > /dev/null 2>&1 && dnssec-keygen -a ECDSAP256SHA256 -n ZONE -f KSK "$DOMAIN" > /dev/null 2>&1 && chown bind:bind ./* && chmod 600 ./*.private && chmod 644 ./*.key; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error generating DNSSEC keys.\e[0m\n"
        fi
        cd ../
        printf "\n\e[32m*\e[0m Creating BIND9 main configuration files...\n"
        local NAMED_CONF_CONTENT='include "/etc/bind/rndc.key";\ninclude "/etc/bind/named.conf.options";\ninclude "/etc/bind/named.conf.local";\n'
        local OPTIONS_CONTENT='options {\n    directory "/var/cache/bind";\n    recursion yes;\n    allow-query { any; };\n    listen-on { any; };\n    listen-on-v6 { none; };\n    forwarders {\n        1.1.1.1;\n        8.8.8.8;\n        9.9.9.9;\n    };\n    forward only;\n    dnssec-validation auto;\n};\n'
        if printf "$NAMED_CONF_CONTENT" > named.conf && chown bind:bind named.conf && chmod 644 named.conf && printf "$OPTIONS_CONTENT" > named.conf.options && chown bind:bind named.conf.options && chmod 644 named.conf.options; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error creating main configuration files.\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Creating and signing zone file for '%s'...\n" "$DOMAIN"
        local NEW_SERIAL ADDRESS KEY_FILES ZSK_KEY KSK_KEY
        NEW_SERIAL=$(date '+%Y%m%d%H')
        ADDRESS="0.0.0.0"
        KEY_FILES=$(find /etc/bind/keys -type f -iname "K${DOMAIN}.*.key" | sort)
        ZSK_KEY=$(echo "$KEY_FILES" | head -1)
        KSK_KEY=$(echo "$KEY_FILES" | tail -1)
        local ZONE_CONTENT
        ZONE_CONTENT=$(printf '$TTL    86400\n@       IN      SOA     ns1.%s. admin.%s. (\n                        %s ; Serial\n                        3600       ; Refresh\n                        1800       ; Retry\n                        604800     ; Expire\n                        86400      ; Minimum TTL\n                )\n; Name servers\n        IN      NS      ns1.%s.\nns1     IN      A       %s\n\n; Zone records\n@       IN      A       %s\n\n; Include DNSSEC keys\n$INCLUDE "%s"\n$INCLUDE "%s"\n' "$DOMAIN" "$DOMAIN" "$NEW_SERIAL" "$DOMAIN" "$ADDRESS" "$ADDRESS" "$ZSK_KEY" "$KSK_KEY")
        if printf "%s" "$ZONE_CONTENT" > zones/"db.$DOMAIN" && chown bind:bind zones/"db.$DOMAIN" && chmod 644 zones/"db.$DOMAIN"; then
            if dnssec-signzone -A -3 $(head /dev/urandom | tr -dc A-F0-9 | head -c8) -N INCREMENT -o "$DOMAIN" -t -K keys zones/"db.$DOMAIN" > /dev/null 2>&1 && chown bind:bind zones/"db.$DOMAIN.signed" && chmod 644 zones/"db.$DOMAIN.signed"; then
                printf "  \e[32m✅ Success\e[0m\n"
            else
                printf "  \e[31m❗ Error signing the zone file.\e[0m\n"
            fi
        else
            printf "  \e[31m❗ Error creating the zone file.\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Creating local zone configuration...\n"
        local ZONE_CONFIG_CONTENT
        ZONE_CONFIG_CONTENT=$(printf 'zone "%s" {\n    type master;\n    file "/etc/bind/zones/db.%s.signed";\n    allow-transfer { none; };\n};\n' "$DOMAIN" "$DOMAIN")
        if printf "%s" "$ZONE_CONFIG_CONTENT" > named.conf.local && chown bind:bind named.conf.local && chmod 644 named.conf.local; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error creating named.conf.local.\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Finalizing BIND9 service state...\n"
        if systemctl restart named --quiet; then
            sleep 3; rndc status > /dev/null 2>&1; rndc reload > /dev/null 2>&1; systemctl disable --now named --quiet;
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error managing BIND9 service.\e[0m\n"
        fi
        cd / 
    }
    printf "\n\e[1;34m--- Starting Network Configuration ---\e[0m\n"
    printf "\n\e[32m*\e[0m Disabling conflicting network services...\n"
    if systemctl disable networking --quiet && systemctl disable ModemManager --quiet && systemctl disable wpa_supplicant --quiet && systemctl disable NetworkManager-wait-online --quiet && systemctl disable NetworkManager.service --quiet; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error disabling one or more services.\e[0m\n"
    fi
    setup_dhcp
    setup_ntp
    setup_dns
    printf "\n\e[1;34m--- Network Configuration Complete ---\e[0m\n"
}

# Function to set up the firewall.
setup_firewall() {
    printf "\n\e[1;34m--- Starting Firewall Setup ---\e[0m\n"

    printf "\n\e[32m*\e[0m Installing nftables package...\n"
    # Lógica corrigida: apt-get retorna 0 se o pacote já estiver instalado.
    # Um código de saída diferente de zero indica um erro real.
    if apt-get -y install nftables > /dev/null 2>&1; then
        printf "  \e[32m✅ Success (package installed or already present).\e[0m\n"
    else
        printf "  \e[31m❗ Error installing nftables package.\e[0m\n"
    fi

    printf "\n\e[32m*\e[0m Disabling the default nftables service...\n"
    if systemctl disable --now nftables --quiet; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error disabling nftables service.\e[0m\n"
    fi

    printf "\n\e[32m*\e[0m Copying custom firewall script...\n"
    if cp -r systemd/scripts/firewall /root/.services/; then
        printf "  \e[32m✅ Success\e[0m\n"
        printf "\n\e[32m*\e[0m Adjusting permissions for firewall script...\n"
        if chmod 700 /root/.services/firewall/*; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error setting permissions.\e[0m\n"
        fi
    else
        # Mensagem de erro corrigida para referenciar o diretório correto sendo copiado.
        printf "  \e[31m❗ Error copying firewall script. Check if 'systemd/scripts/firewall' directory exists.\e[0m\n"
    fi

    printf "\n\e[1;34m--- Firewall Setup Complete ---\e[0m\n"
}

# Main function to set up KVM and LXC hypervisor technologies.
setup_hypervisor() {
    setup_kvm() {
        printf "\n\e[1;36m---  Configuring KVM Hypervisor  ---\e[0m\n"
        printf "\n\e[32m*\e[0m Installing KVM packages...\n"
        if apt-get -y install qemu-kvm libvirt0 libvirt-daemon-system > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[33mℹ️  Could not install packages (they may already be installed).\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Disabling libvirtd service for manual configuration...\n"
        if systemctl disable --now libvirtd --quiet; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Adding user '%s' to 'libvirt' group...\n" "$TARGET_USER"
        if [ -z "$TARGET_USER" ]; then
            printf "  \e[31m❗ Error: TARGET_USER variable is not set.\e[0m\n"
        elif gpasswd libvirt -a "$TARGET_USER" > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Configuring kernel for nested virtualization...\n"
        local CPU
        CPU=$(lscpu | grep -E 'Vendor ID|ID de fornecedor' | cut -f 2 -d ":" | sed -n 1p | awk '{$1=$1}1')
        case "$CPU" in
            GenuineIntel)
                if printf 'options kvm_intel nested=1' > /etc/modprobe.d/kvm.conf && /sbin/modprobe -r kvm_intel > /dev/null 2>&1 && /sbin/modprobe kvm_intel > /dev/null 2>&1; then
                    printf "  \e[32m✅ Success (Intel)\e[0m\n"
                else
                    printf "  \e[31m❗ Error (Intel)\e[0m\n"
                fi
                ;;
            AuthenticAMD)
                if printf 'options kvm_amd nested=1' > /etc/modprobe.d/kvm.conf && /sbin/modprobe -r kvm_amd > /dev/null 2>&1 && /sbin/modprobe kvm_amd > /dev/null 2>&1; then
                    printf "  \e[32m✅ Success (AMD)\e[0m\n"
                else
                    printf "  \e[31m❗ Error (AMD)\e[0m\n"
                fi
                ;;
            *)
                printf "  \e[33mℹ️  Unknown or unsupported CPU for nested virtualization.\e[0m\n"
                ;;
        esac
        printf "\n\e[32m*\e[0m Creating KVM log and script directories...\n"
        if mkdir -p /var/log/virsh && chown "$TARGET_USER":"$TARGET_USER" -R /var/log/virsh; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Copying KVM startup script...\n"
        if cp systemd/scripts/virtual-machine.sh /root/.services/ && chmod 700 /root/.services/virtual-machine.sh; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error copying KVM script.\e[0m\n"
        fi
    }
    setup_lxc() {
        printf "\n\e[1;36m---  Configuring LXC Containers  ---\e[0m\n"
        printf "\n\e[32m*\e[0m Installing LXC package...\n"
        if apt-get -y install lxc > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[33mℹ️  Could not install package (it may already be installed).\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Configuring AppArmor for LXC...\n"
        if sed -i '/^\s*}$/i \ \ /mnt\/Local\/Container\/A\/lxc\/** rw,\n\ \ mount options=(rw, move) -> /mnt\/Local\/Container\/A\/lxc\/**,' /etc/apparmor.d/usr.bin.lxc-copy && apparmor_parser -r /etc/apparmor.d/usr.bin.lxc-copy > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Disabling LXC services...\n"
        if systemctl disable --now lxc --quiet && systemctl disable --now lxc-net --quiet && systemctl mask lxc-net --quiet; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Removing default LXC configuration files...\n"
        if rm -f /etc/default/lxc-net && rm -f /etc/lxc/default.conf; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[33mℹ️  Could not remove files (they may not exist).\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Creating custom LXC default configuration...\n"
        local LXC_CONF_CONTENT='lxc.net.0.type = veth
lxc.net.0.link = br_tap110
lxc.net.0.flags = up

lxc.apparmor.profile = generated
lxc.apparmor.allow_nesting = 1'
        if printf "%s" "$LXC_CONF_CONTENT" > /etc/lxc/default.conf; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Creating LXC log directory...\n"
        if mkdir -p /var/log/lxc && chown "$TARGET_USER":"$TARGET_USER" -R /var/log/lxc; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Copying LXC startup script...\n"
        if cp systemd/scripts/container.sh /root/.services/ && chmod 700 /root/.services/container.sh; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error copying LXC script.\e[0m\n"
        fi
    }
    printf "\n\e[1;34m--- Starting Hypervisor Setup ---\e[0m\n"
    setup_kvm
    setup_lxc
    printf "\n\e[1;34m--- Hypervisor Setup Complete ---\e[0m\n"
}

# Function to set up and configure the SSH service and keys.
setup_ssh() {
    printf "\n\e[1;34m--- Starting SSH Configuration ---\e[0m\n"
    printf "\n\e[32m*\e[0m Installing SSH packages (openssh-server, sshfs, autossh)...\n"
    if apt-get -y install openssh-server sshfs autossh > /dev/null 2>&1; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[33mℹ️  Could not install packages (they may already be installed).\e[0m\n"
    fi
    printf "\n\e[32m*\e[0m Deploying custom sshd_config file...\n"
    if rm -f /etc/ssh/sshd_config && cp sshd_config /etc/ssh/ && chmod 644 /etc/ssh/sshd_config; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error copying sshd_config. Does the source file exist?\e[0m\n"
    fi
    printf "\n\e[32m*\e[0m Clearing /etc/motd file...\n"
    if rm -f /etc/motd && touch /etc/motd; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error\e[0m\n"
    fi
    printf "\n\e[32m*\e[0m Configuring SSH for 'root' user...\n"
    if mkdir -p /root/.ssh && chmod 700 /root/.ssh; then
        printf "  \e[32m✅ Directory permissions set correctly.\e[0m\n"
    else
        printf "  \e[31m❗ Error setting up /root/.ssh directory.\e[0m\n"
    fi
    printf "\n\e[32m*\e[0m Creating SSH key for 'root' user...\n"
    if [ -f "/root/.ssh/id_rsa" ]; then
        printf "  \e[33mℹ️  SSH key for root already exists. Skipping.\e[0m\n"
    else
        if touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N '' > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error generating SSH key for root.\e[0m\n"
        fi
    fi
    if [ -z "$TARGET_USER" ]; then
        printf "\n\e[31m❗ Error: TARGET_USER variable is not set. Skipping user SSH setup.\e[0m\n"
    else
        printf "\n\e[32m*\e[0m Configuring SSH for user '%s'...\n" "$TARGET_USER"
        local USER_HOME
        USER_HOME=$(eval echo ~$TARGET_USER)
        if [ ! -d "$USER_HOME" ]; then
            printf "  \e[31m❗ Error: Home directory for user '%s' not found.\e[0m\n" "$TARGET_USER"
        else
            printf "\n\e[32m*\e[0m Creating SSH key for user '%s'...\n" "$TARGET_USER"
            if [ -f "$USER_HOME/.ssh/id_rsa" ]; then
                printf "  \e[33mℹ️  SSH key for '%s' already exists. Skipping.\e[0m\n" "$TARGET_USER"
            else
                if su - "$TARGET_USER" -c "mkdir -p ~/.ssh && ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ''" > /dev/null 2>&1 && \
                   su - "$TARGET_USER" -c "touch ~/.ssh/authorized_keys" > /dev/null 2>&1 && \
                   chmod 700 "$USER_HOME/.ssh" && \
                   chmod 600 "$USER_HOME/.ssh/authorized_keys"; then
                    printf "  \e[32m✅ Success\e[0m\n"
                else
                    printf "  \e[31m❗ Error generating SSH key or setting permissions for '%s'.\e[0m\n" "$TARGET_USER"
                fi
            fi
        fi
    fi
    printf "\n\e[1;34m--- SSH Configuration Complete ---\e[0m\n"
}

# Function to configure the custom spawn service.
setup_spawn_service() {
    printf "\n\e[1;34m--- Starting Spawn Service Configuration ---\e[0m\n"
    printf "\n\e[32m*\e[0m Copying spawn service files to /etc/...\n"
    if cp -r spawn /etc/ && chmod 700 /etc/spawn/CT/*.sh; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error copying files. Does the 'spawn' directory exist?\e[0m\n"
    fi
    if [ -z "$TARGET_USER" ]; then
        printf "\n\e[31m❗ Error: TARGET_USER variable is not set. Skipping user symlink creation.\e[0m\n"
    else
        printf "\n\e[32m*\e[0m Creating spawn symlink for user '%s'...\n" "$TARGET_USER"
        local USER_HOME
        USER_HOME=$(eval echo ~$TARGET_USER)
        if [ ! -d "$USER_HOME" ]; then
            printf "  \e[31m❗ Error: Home directory for user '%s' not found.\e[0m\n" "$TARGET_USER"
        elif ln -sf /etc/spawn/CT/spawn.sh "$USER_HOME"/.spawn; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
    fi
    printf "\n\e[32m*\e[0m Creating spawn symlink for 'root' user...\n"
    if ln -sf /etc/spawn/CT/spawn.sh /root/.spawn && chown -h sysop:sysop /root/.spawn; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error\e[0m\n"
    fi
    printf "\n\e[1;34m--- Spawn Service Configuration Complete ---\e[0m\n"
}

# Function to configure the GRUB bootloader.
setup_grub() {
    printf "\n\e[1;34m--- Starting GRUB Configuration ---\e[0m\n"
    printf "\n\e[32m*\e[0m Creating custom GRUB configuration file (/etc/default/grub)...\n"
    local GRUB_CONTENT
    GRUB_CONTENT=$(cat <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
EOF
)
    if rm -f /etc/default/grub && printf "%s" "$GRUB_CONTENT" > /etc/default/grub && chmod 644 /etc/default/grub; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error creating the GRUB configuration file.\e[0m\n"
    fi
    printf "\n\e[32m*\e[0m Applying new GRUB configuration (update-grub)...\n"
    if update-grub; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error: The 'update-grub' command failed.\e[0m\n"
    fi
    printf "\n\e[1;34m--- GRUB Configuration Complete ---\e[0m\n"
}

# Function to schedule a cleanup script to run once after the next reboot.
schedule_post_reboot_cleanup() {
    printf "\n\e[1;34m--- Scheduling Post-Reboot Cleanup ---\e[0m\n"
    printf "\n\e[32m*\e[0m Identifying initial user (UID 1000) for cleanup...\n"
    local INITIAL_USER
    INITIAL_USER=$(grep ':1000:' /etc/passwd | cut -f 1 -d ":")
    if [ -z "$INITIAL_USER" ]; then
        printf "  \e[33mℹ️  No user with UID 1000 found. Skipping cleanup scheduling.\e[0m\n"
    else
        printf "  \e[32m✅ User found: \e[1;33m%s\e[0m\n" "$INITIAL_USER"
        printf "\n\e[32m*\e[0m Creating cleanup script at /etc/init.d/later...\n"
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
        if printf "%s" "$SCRIPT_CONTENT" > /etc/init.d/later && chmod +x /etc/init.d/later; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error creating the cleanup script.\e[0m\n"
        fi
        printf "\n\e[32m*\e[0m Scheduling the cleanup script to run on next boot...\n"
        if update-rc.d later defaults > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error scheduling the script with update-rc.d.\e[0m\n"
        fi
    fi
    printf "\n\e[1;34m--- Post-Reboot Cleanup Scheduled ---\e[0m\n"
}

# Function to perform final cleanup and prompt for a system reboot.
finalize_setup() {
    printf "\n\e[1;34m--- Finalizing Setup ---\e[0m\n"
    printf "\n\e[32m*\e[0m Removing unused packages (autoremove)...\n"
    if apt-get -y autoremove > /dev/null 2>&1; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error\e[0m\n"
    fi
    printf "\n\e[32m*\e[0m Removing default network configuration file...\n"
    if rm -f /etc/network/interfaces; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error\e[0m\n"
    fi
    printf "\n\e[1;32m✅ INSTALLATION COMPLETED SUCCESSFULLY!\e[0m\n"
    local response
    while true; do
        read -p $'\n\e[33m?\e[0m DO YOU WANT TO RESTART NOW? (y/n): ' response
        response=${response,,}
        if [[ "$response" == "y" ]]; then
            printf "\n\e[32m*\e[0m RESTARTING...\n"
            # systemctl reboot
            break
        elif [[ "$response" == "n" ]]; then
            printf "\n\e[32m*\e[0m Task complete. Please reboot the system later to apply all changes.\n"
            break
        else
            printf "  \e[31m❗ Invalid option. Please answer with 'y' for yes or 'n' for no.\e[0m\n"
        fi
    done
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
