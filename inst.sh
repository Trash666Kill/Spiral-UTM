#!/bin/bash
# SCRIPT TO BUILD A PRODUCTION AND DEVELOPMENT SERVER FOLLOWING THE SPIRAL PATTERN
# Revised for improved robustness, readability, and maintainability.
#
# Usage:
#   sudo ./inst.sh        (Runs in quiet mode)
#   sudo ./inst.sh -v     (Runs in verbose mode for debugging)

# --- Script Safety and Setup ---
# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# Pipelines return the exit status of the last command to fail.
set -euo pipefail

# Check if running as root
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ This script must be run as root." >&2
  exit 1
fi

# Store the script's directory and its 'dep' subdirectory.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
DEP_DIR="$SCRIPT_DIR/dep"

# --- Verbose Mode Setup ---
# By default, quiet mode is active.
VERBOSE=false
APT_OPTIONS="-y -qq"
REDIRECT_OUTPUT=">/dev/null 2>&1"

# Check if the first argument is -v (verbose)
if [[ "${1-}" == "-v" || "${1-}" == "--verbose" ]]; then
  echo "✅ Verbose mode enabled. APT command output will be displayed."
  VERBOSE=true
  APT_OPTIONS="-y" # Remove -qq for more info
  REDIRECT_OUTPUT="" # Clear the redirect variable
fi

# Function Wrapper for APT
# Executes apt-get, respecting the verbose mode setting.
run_apt() {
  # 'eval' is used here safely to apply the redirection only when the
  # REDIRECT_OUTPUT variable is not empty.
  eval apt-get "$APT_OPTIONS" "$@" "$REDIRECT_OUTPUT"
}

# Move into the dependency directory after setting up variables
cd "$DEP_DIR"

# Disable bash history for this session for security
unset HISTFILE

# ==============================================================================
# GLOBAL CONFIGURATION & DECLARATIONS
# ==============================================================================
# Centralized configuration for easy modification.
declare -g TARGET_USER="sysop"
declare -g TARGET_UID="1001"
declare -g TARGET_GID="1001"
declare -g TIMEZONE="America/Sao_Paulo"

# Global variables to be populated by the script.
declare -g WAN0 WAN0_IPV4 WAN0_MASK WAN0_GATEWAY
declare -g LAN0
declare -g DOMAIN
declare -g HOSTNAME

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

log_info() { printf "\n\e[1;34m--- %s ---\e[0m\n" "$1"; }
log_success() { printf "\e[32m✅ %s\e[0m\n" "$1"; }
log_step() { printf "\e[32m*\e[0m %s\n" "$1"; }
log_warning() { printf "\e[33m⚠️  %s\e[0m\n" "$1"; }
log_error() { printf "\n\e[31m❗ ERROR: %s\e[0m\n" "$1" >&2; }

# ==============================================================================
# FUNCTION DEFINITIONS
# ==============================================================================

update_system() {
    log_info "Starting System Update"
    run_apt update
    run_apt upgrade
    log_success "System Update Complete"
}

setup_interfaces() {
    log_info "Starting Network Interface Configuration"
    
    # Adicionado: Garante que o 'bc' esteja instalado para os testes de latência.
    log_step "Ensuring 'bc' package is installed for latency tests..."
    run_apt install bc

    local target_ip="8.8.8.8"
    local best_interface=""
    local best_latency=9999.0

    log_step "Testing active interfaces to select the best WAN0..."
    for iface in $(ip -o link show | awk -F': ' '/state UP/ && ($2 ~ /^(eth|en|enp)/) {sub(/@.*/, "", $2); print $2}'); do
        local latency
        # Ping para medir a latência. Pula para a próxima interface se o ping falhar.
        latency=$(ping -I "$iface" -4 -c 3 "$target_ip" 2>/dev/null | awk -F'/' 'END {print $5}') || continue
        
        # Compara a latência atual com a melhor encontrada até agora
        if [[ -n "$latency" && $(echo "$latency < $best_latency" | bc -l) -eq 1 ]]; then
            best_latency="$latency"
            best_interface="$iface"
        fi
    done

    if [[ -z "$best_interface" ]]; then
        log_error "Could not find a suitable WAN interface with internet connectivity."
        exit 1
    fi

    WAN0="$best_interface"
    printf "\n\e[32m✅ WAN0 interface selected: \033[1;32m%s\033[0m (Latency: %s ms)\n" "$WAN0" "$best_latency"
    
    local ip_info
    ip_info=$(ip -4 addr show "$WAN0" | grep 'inet' | awk '{print $2}')
    WAN0_IPV4=$(echo "$ip_info" | cut -d'/' -f1)
    WAN0_MASK=$(echo "$ip_info" | cut -d'/' -f2)
    WAN0_GATEWAY=$(ip route | grep default | grep "dev $WAN0" | awk '{print $3}')

    mapfile -t down_interfaces < <(ip -o link show | awk -F': ' '/state DOWN/ && ($2 ~ /^(eth|en|enp)/) {sub(/@.*/, "", $2); print $2}')
    if [[ ${#down_interfaces[@]} -gt 0 ]]; then
        log_step "The following interfaces are inactive. Choose one for LAN0:"
        for i in "${!down_interfaces[@]}"; do
            printf "    \e[33m%d)\e[0m %s\n" "$((i+1))" "${down_interfaces[$i]}"
        done
        local choice
        read -p "  Enter the number for the desired interface: " choice
        if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#down_interfaces[@]}" ]]; then
            LAN0="${down_interfaces[$((choice-1))]}"
            printf "\n\e[32m✅ LAN0 interface set to: \033[1;32m%s\033[0m\n" "$LAN0"
        else
            log_warning "Invalid option. No LAN0 interface was configured."
        fi
    fi
    log_success "Network Interface Configuration Complete"
}

prompt_for_domain() {
    log_info "Domain Name Setup"
    read -p $'\n\e[32m*\e[0m Please enter the domain name (e.g., example.local): ' DOMAIN
    DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | xargs)
    log_success "Domain set to: $DOMAIN"
}

configure_global_settings() {
    log_info "Configuring Timezone"
    timedatectl set-timezone "$TIMEZONE"
    log_success "Timezone set to $TIMEZONE"
}

configure_hostname() {
    log_info "Configuring Hostname"
    HOSTNAME="utm$(shuf -i 10000-99999 -n 1)"
    hostnamectl set-hostname "$HOSTNAME"
    cat > /etc/hosts <<-EOF
	127.0.0.1       localhost
	127.0.1.1       $HOSTNAME

	::1     localhost ip6-localhost ip6-loopback
	ff02::1 ip6-allnodes
	ff02::2 ip6-allrouters
	EOF
    log_success "Hostname set to $HOSTNAME"
}

setup_target_user() {
    log_info "Configuring User: $TARGET_USER"
    run_apt install sudo
    echo -e '\nunset HISTFILE\nexport HISTSIZE=0\nexport HISTFILESIZE=0\nexport HISTCONTROL=ignoreboth' >> /etc/profile
    if ! getent group "$TARGET_USER" >/dev/null; then
        groupadd -g "$TARGET_GID" "$TARGET_USER"
    fi
    if ! id "$TARGET_USER" >/dev/null 2>&1; then
        useradd -m -u "$TARGET_UID" -g "$TARGET_GID" -c "SysOp" -s /bin/bash "$TARGET_USER"
    fi
    usermod -aG sudo "$TARGET_USER"
    log_success "User $TARGET_USER configured successfully"
}

set_passwords() {
    log_info "Configuring System Passwords"
    run_apt install pwgen
    local password_root
    password_root=$(pwgen -s 18 1)
    local password_target
    password_target=$(pwgen -s 18 1)
    echo "root:$password_root" | chpasswd
    echo "$TARGET_USER:$password_target" | chpasswd
    printf "\n\e[1;33m--- 🔑 IMPORTANT: Generated Passwords ---\e[0m\n"
    printf "\e[32m*\e[0m User \e[1;32m%-12s\e[0m -> Password: \e[1;37m%s\e[0m\n" "Root" "$password_root"
    printf "\e[32m*\e[0m User \e[1;32m%-12s\e[0m -> Password: \e[1;37m%s\e[0m\n" "$TARGET_USER" "$password_target"
    printf "\e[1;33m------------------------------------------\e[0m\n"
    log_success "Password Configuration Complete"
}

install_packages() {
    log_info "Starting Package Installation"
    declare -A pkg_categories=(
        ["Text Editor"]="vim"
        ["Network Tools"]="nfs-common tcpdump traceroute iperf ethtool geoip-bin socat speedtest-cli bridge-utils"
        ["Security Tools"]="apparmor-utils"
        ["Compression"]="unzip xz-utils bzip2 pigz"
        ["Scripting"]="sshpass python3-apt"
        ["Monitoring"]="screen htop sysstat stress lm-sensors nload smartmontools"
        ["Disk Utilities"]="hdparm dosfstools cryptsetup uuid rsync"
        ["Connectivity"]="net-tools"
        ["Power Management"]="pm-utils acpi acpid fwupd"
        ["Resource Control"]="cpulimit"
        ["Network Firmware"]="firmware-misc-nonfree firmware-realtek firmware-atheros"
        ["Additional Utilities"]="tree"
    )
    for category in "${!pkg_categories[@]}"; do
        log_step "Installing ${category}..."
        run_apt install ${pkg_categories[$category]}
    done
    log_success "Package Installation Complete"
}

create_directories() {
    log_info "Creating System Directories"
    mkdir -p /mnt/{Temp,Local/{Container/{A,B},USB/{A,B}},Remote/Servers}
    mkdir -p /root/{Temp,.services/scheduled,.crypt}
    chmod 600 /root/.crypt
    mkdir -p /var/log/rsync
    chown "$TARGET_USER:$TARGET_USER" -R /var/log/rsync
    su - "$TARGET_USER" -c "mkdir -p /home/$TARGET_USER/{Temp,.services/scheduled,.crypt}"
    log_success "Directory Creation Complete"
}

setup_ssh() {
    log_info "Starting SSH Configuration"
    run_apt install openssh-server sshfs autossh

    if [ -f "sshd_config" ]; then
        cp sshd_config /etc/ssh/ && chmod 644 /etc/ssh/sshd_config
        log_step "Custom 'sshd_config' applied."
    else
        log_warning "Custom 'sshd_config' not found. Using default."
    fi

    rm -f /etc/motd && touch /etc/motd

    log_step "Generating SSH keys for root and $TARGET_USER..."
    # --- Root SSH Setup ---
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    
    # Adicionado: Remove a chave existente para forçar a sobrescrita
    rm -f /root/.ssh/id_rsa /root/.ssh/id_rsa.pub
    
    # O comando ssh-keygen agora executa sem interrupção
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N '' < /dev/null
    touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys

    # --- Target User SSH Setup ---
    local user_home
    user_home=$(getent passwd "$TARGET_USER" | cut -d: -f6)

    # A mesma lógica é aplicada para o usuário-alvo
    su - "$TARGET_USER" -c "mkdir -p ~/.ssh && \
                           rm -f ~/.ssh/id_rsa ~/.ssh/id_rsa.pub && \
                           ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N '' < /dev/null && \
                           touch ~/.ssh/authorized_keys"
                           
    chmod 700 "$user_home/.ssh"
    chmod 600 "$user_home/.ssh/authorized_keys"
    
    log_success "SSH Configuration Complete"
}

setup_spawn_service() {
    log_info "Starting Spawn Service Configuration"
    cp -r spawn /etc/ && chmod 700 /etc/spawn/CT/*.sh
    local user_home
    user_home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    ln -sf /etc/spawn/CT/spawn.sh "$user_home"/.spawn
    chown -h "$TARGET_USER":"$TARGET_USER" "$user_home"/.spawn
    ln -sf /etc/spawn/CT/spawn.sh /root/.spawn
    log_success "Spawn Service Configuration Complete"
}

# --- Network Services Functions ---
setup_dhcp() {
    log_step "Configuring DHCP (KEA)"
    run_apt install kea-dhcp4-server
    cp DHCP/kea-dhcp4.conf /etc/kea/
}

setup_ntp() {
    log_step "Configuring NTP (Chrony)"
    run_apt install chrony
    # Using a heredoc is cleaner than sed for appending multi-line configurations
    cat >> /etc/chrony/chrony.conf <<-EOF

	# Servidores NTP Upstream
	pool b.st1.ntp.br iburst
	pool a.st1.ntp.br iburst
	pool 200.186.125.195 iburst

	# Interface de escuta e resposta
	allow all
	EOF
    sed -i '/^pool 2\.debian\.pool\.ntp\.org iburst/d' /etc/chrony/chrony.conf
    systemctl restart chrony
}

setup_dns() {
    log_step "Configuring DNS (BIND9)"
    run_apt install bind9 bind9-utils bind9-doc dnsutils
    rm -rf /etc/bind
    mkdir -p /etc/bind/{zones,keys}
    chown -R bind:bind /etc/bind
    chmod 2755 /etc/bind && chmod 755 /etc/bind/zones && chmod 750 /etc/bind/keys
    
    rndc-confgen -a -c /etc/bind/rndc.key >/dev/null
    chown bind:bind /etc/bind/rndc.key && chmod 640 /etc/bind/rndc.key
    
    ( cd /etc/bind/keys
      dnssec-keygen -a ECDSAP256SHA256 -n ZONE "$DOMAIN" >/dev/null
      dnssec-keygen -a ECDSAP256SHA256 -n ZONE -f KSK "$DOMAIN" >/dev/null
      chown bind:bind ./* && chmod 600 ./*.private && chmod 644 ./*.key
    )
    
    cat > /etc/bind/named.conf <<-EOF
	include "/etc/bind/rndc.key";
	include "/etc/bind/named.conf.options";
	include "/etc/bind/named.conf.local";
	EOF

    cat > /etc/bind/named.conf.options <<-EOF
	options {
	    directory "/var/cache/bind";
	    recursion yes; allow-query { any; };
	    listen-on { any; }; listen-on-v6 { none; };
	    forwarders { 1.1.1.1; 8.8.8.8; 9.9.9.9; };
	    forward only; dnssec-validation auto;
	};
	EOF
    
    local new_serial
    new_serial=$(date '+%Y%m%d%H')
    local key_files
    key_files=$(find /etc/bind/keys -type f -name "K${DOMAIN}.*.key" | sort)
    local zsk_key
    zsk_key=$(echo "$key_files" | head -1)
    local ksk_key
    ksk_key=$(echo "$key_files" | tail -1)

    cat > "/etc/bind/zones/db.$DOMAIN" <<-EOF
	\$TTL    86400
	@       IN      SOA     ns1.$DOMAIN. admin.$DOMAIN. (
	                        $new_serial ; Serial
	                        3600       ; Refresh
	                        1800       ; Retry
	                        604800     ; Expire
	                        86400      ; Minimum TTL
	                )
	        IN      NS      ns1.$DOMAIN.
	ns1     IN      A       0.0.0.0
	@       IN      A       0.0.0.0
	\$INCLUDE "$zsk_key"
	\$INCLUDE "$ksk_key"
	EOF
    chown bind:bind "/etc/bind/zones/db.$DOMAIN"
    
    ( cd /etc/bind/zones
      dnssec-signzone -A -3 "$(head /dev/urandom | tr -dc A-F0-9 | head -c8)" -N INCREMENT -o "$DOMAIN" -t -K ../keys "db.$DOMAIN" >/dev/null
    )
    chown bind:bind "/etc/bind/zones/db.$DOMAIN.signed"
    
    cat > /etc/bind/named.conf.local <<-EOF
	zone "$DOMAIN" {
	    type master;
	    file "/etc/bind/zones/db.$DOMAIN.signed";
	    allow-transfer { none; };
	};
	EOF
    
    chown -R bind:bind /etc/bind
    named-checkconf
    systemctl restart named && rndc reload
    systemctl disable --now named --quiet
}

setup_network_services() {
    log_info "Starting Network Services Configuration"
    setup_dhcp
    setup_ntp
    setup_dns
    log_success "Network Services Configuration Complete"
}

setup_firewall() {
    log_info "Starting Firewall Setup"
    run_apt install nftables
    systemctl disable --now nftables --quiet
    cp -r systemd/scripts/firewall /root/.services/
    chmod 700 /root/.services/firewall/*
    log_success "Firewall Setup Complete"
}

# --- Hypervisor Functions ---
setup_kvm() {
    log_step "Configuring KVM Hypervisor"
    run_apt install qemu-kvm libvirt0 libvirt-daemon-system
    systemctl disable --now libvirtd --quiet
    usermod -aG libvirt "$TARGET_USER"
    local cpu_vendor
    cpu_vendor=$(lscpu | grep 'Vendor ID' | awk '{print $3}')
    case "$cpu_vendor" in
        GenuineIntel)
            echo 'options kvm_intel nested=1' > /etc/modprobe.d/kvm.conf
            modprobe -r kvm_intel && modprobe kvm_intel
            ;;
        AuthenticAMD)
            echo 'options kvm_amd nested=1' > /etc/modprobe.d/kvm.conf
            modprobe -r kvm_amd && modprobe kvm_amd
            ;;
    esac
    mkdir -p /var/log/virsh && chown "$TARGET_USER":"$TARGET_USER" -R /var/log/virsh
    cp systemd/scripts/virtual-machine.sh /root/.services/ && chmod 700 /root/.services/virtual-machine.sh
}

setup_lxc() {
    log_step "Configuring LXC Containers"
    run_apt install lxc
    sed -i '/^\s*}$/i \ \ /mnt\/Local\/Container\/A\/lxc\/** rw,\n\ \ mount options=(rw, move) -> /mnt\/Local\/Container\/A\/lxc\/**,' /etc/apparmor.d/usr.bin.lxc-copy && apparmor_parser -r /etc/apparmor.d/usr.bin.lxc-copy >/dev/null
    systemctl disable --now lxc lxc-net --quiet && systemctl mask lxc-net --quiet
    rm -f /etc/default/lxc-net
    cat > /etc/lxc/default.conf <<-EOF
	lxc.net.0.type = veth
	lxc.net.0.link = br_tap110
	lxc.net.0.flags = up
	lxc.apparmor.profile = generated
	lxc.apparmor.allow_nesting = 1
	EOF
    mkdir -p /var/log/lxc && chown "$TARGET_USER":"$TARGET_USER" -R /var/log/lxc
    cp systemd/scripts/container.sh /root/.services/ && chmod 700 /root/.services/container.sh
}

setup_hypervisor() {
    log_info "Starting Hypervisor Setup"
    setup_kvm
    setup_lxc
    log_success "Hypervisor Setup Complete"
}

setup_trigger_service() {
    log_info "Starting Systemd Trigger Service Setup"
    cp systemd/trigger.service /etc/systemd/system/
    systemctl enable trigger --quiet
    mkdir -p /root/.services
    cp systemd/scripts/main.sh /root/.services/
    chmod 700 /root/.services/main.sh
    log_success "Systemd Service Setup Complete"
}

setup_grub() {
    log_info "Starting GRUB Configuration"
    cat > /etc/default/grub <<-EOF
	GRUB_DEFAULT=0
	GRUB_TIMEOUT=0
	GRUB_DISTRIBUTOR=\`lsb_release -i -s 2> /dev/null || echo Debian\`
	GRUB_CMDLINE_LINUX_DEFAULT=""
	GRUB_CMDLINE_LINUX=""
	EOF
    update-grub >/dev/null
    log_success "GRUB Configuration Complete"
}

schedule_post_reboot_cleanup() {
    log_info "Scheduling Post-Reboot Cleanup"
    local initial_user
    initial_user=$(grep ':1000:' /etc/passwd | cut -f1 -d:)
    cat > /etc/init.d/later <<-EOF
	#!/bin/bash
	### BEGIN INIT INFO
	# Provides:          later
	# Required-Start:    \$all
	# Required-Stop:
	# Default-Start:     2 3 4 5
	# Default-Stop:
	# Short-Description: Post-reboot cleanup procedures.
	### END INIT INFO
	pkill -u $initial_user
	userdel -r $initial_user
	rm -rf /root/Spiral-UTM-main
	update-rc.d later remove
	rm -f /etc/init.d/later
	EOF
    chmod +x /etc/init.d/later
    update-rc.d later defaults >/dev/null
    log_success "Post-Reboot Cleanup Scheduled"
}

finalize_setup() {
    log_info "Finalizing Setup"
    run_apt autoremove
    rm -f /etc/network/interfaces
    printf "\n\e[1;32m✅ INSTALLATION COMPLETED SUCCESSFULLY!\e[0m\n"
    local response
    read -p $'\n\e[33m?\e[0m DO YOU WANT TO RESTART NOW? (y/n): ' response
    if [[ "${response,,}" == "y" ]]; then
        log_step "RESTARTING..."
        # systemctl reboot
    else
        log_step "Task complete. Please reboot the system later to apply all changes."
    fi
}

# ==============================================================================
# MAIN ORCHESTRATION
# ==============================================================================
main() {
    update_system
    setup_interfaces
    prompt_for_domain
    configure_global_settings
    configure_hostname
    setup_target_user
    set_passwords
    install_packages
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