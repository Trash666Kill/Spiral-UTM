#!/bin/bash

# Disable bash history
unset HISTFILE

# Execution directory
cd $PWD/dep

update() {
    printf "\e[32m*\e[0m UPDATING SYSTEM PACKAGES\n"

    # Updates the list of available packages
    apt-get -y update > /dev/null 2>&1

    # Performs the update of installed packages
    apt-get -y upgrade > /dev/null 2>&1
}

interface() {
    # Installing required packages for calculation
    apt-get -y install bc > /dev/null 2>&1
    printf "\e[32m*\e[0m SELECTING WAN AND LAN INTERFACES, WAIT...\n"

    # Target IP for ping
    TARGET_IP="8.8.8.8"

    # Variables for WAN selection
    WAN0=""
    BEST_LATENCY=9999.0

    # Iterate over active interfaces to find WAN (Internet)
    for IFACE in $(ip -o link show | awk -F': ' '/state UP/ && ($2 ~ /^(eth|en|enp)/) {sub(/@.*/, "", $2); print $2}'); do
        LATENCY=$(ping -I "$IFACE" -4 -c 3 "$TARGET_IP" 2>/dev/null | awk -F'/' 'END {print $5}') || continue

        if [[ -n "$LATENCY" && $(echo "$LATENCY < $BEST_LATENCY" | bc -l) -eq 1 ]]; then
            BEST_LATENCY="$LATENCY"
            WAN0="$IFACE"
        fi
    done

    if [[ -z "$WAN0" ]]; then
        printf "\033[31m*\033[0m ERROR: NO VALID WAN INTERFACE FOUND.\n"
        exit 1
    fi

    printf "\e[32m*\e[0m WAN0 INTERFACE: \033[32m%s\033[0m (Latency: %s ms)\n" "$WAN0" "$BEST_LATENCY"

    # LAN Selection logic
    mapfile -t DOWN_INTERFACES < <(ip -o link show | awk -F': ' '/state DOWN/ && ($2 ~ /^(eth|en|enp)/) {sub(/@.*/, "", $2); print $2}')
    LAN0=""

    if [[ ${#DOWN_INTERFACES[@]} -gt 0 ]]; then
        printf "\e[32m*\e[0m AVAILABLE INACTIVE INTERFACES FOR LAN0:\n"
        for i in "${!DOWN_INTERFACES[@]}"; do
            printf "    \e[33m%d)\e[0m %s\n" "$((i+1))" "${DOWN_INTERFACES[$i]}"
        done
        read -p "  ENTER THE NUMBER FOR LAN0: " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ && "$CHOICE" -ge 1 && "$CHOICE" -le "${#DOWN_INTERFACES[@]}" ]]; then
            LAN0="${DOWN_INTERFACES[$((CHOICE-1))]}"
            printf "\e[32m*\e[0m LAN0 INTERFACE SET TO: \033[32m%s\033[0m\n" "$LAN0"
        else
            printf "\e[33m*\e[0m WARNING: INVALID OPTION. NO LAN0 CONFIGURED.\n"
        fi
    fi

    # Write variables to /etc/environment
    printf "\e[32m*\e[0m WRITING NETWORK VARIABLES TO /etc/environment\n"
    touch /etc/environment
    sed -i '/^WAN0=/d' /etc/environment
    sed -i '/^LAN0=/d' /etc/environment
    
    # Writing ONLY the interface name as requested
    echo "WAN0=$WAN0" >> /etc/environment
    if [[ -n "${LAN0-}" ]]; then
      echo "LAN0=$LAN0" >> /etc/environment
    fi
}

domain() {
    printf "\e[32m*\e[0m DOMAIN CONFIGURATION\n"
    read -p "PLEASE ENTER THE DOMAIN NAME (e.g., example.local): " DOMAIN_INPUT
    DOMAIN=$(echo "$DOMAIN_INPUT" | tr '[:upper:]' '[:lower:]' | xargs)
}

hostname() {
    # Generates a new hostname
    HOSTNAME="utm$(shuf -i 10000-99999 -n 1)"

    printf "\e[32m*\e[0m GENERATED HOSTNAME: \033[32m%s\033[0m\n" "$HOSTNAME"

    hostnamectl set-hostname "$HOSTNAME"
    
    rm /etc/hosts
    printf "127.0.0.1       localhost
127.0.1.1       $HOSTNAME

::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters" > /etc/hosts
}

global_settings() {
    TIMEZONE="America/Sao_Paulo"
    timedatectl set-timezone "$TIMEZONE"
}

target_user() {
    apt-get -y install sudo > /dev/null 2>&1
    sed -i '$ a unset HISTFILE\nexport HISTSIZE=0\nexport HISTFILESIZE=0\nexport HISTCONTROL=ignoreboth' /etc/profile

    printf "\e[32m*\e[0m CREATING USER \e[32mSysOp\e[0m\n"
    
    TARGET_USER="sysop"
    TARGET_UID="1001"
    TARGET_GID="1001"

    if ! getent group "$TARGET_USER" >/dev/null; then
        groupadd -g "$TARGET_GID" "$TARGET_USER"
    fi
    if ! id "$TARGET_USER" >/dev/null 2>&1; then
        useradd -m -u "$TARGET_UID" -g "$TARGET_GID" -c "SysOp" -s /bin/bash "$TARGET_USER"
    fi
    usermod -aG sudo "$TARGET_USER"
}

passwords() {
    apt-get -y install pwgen > /dev/null 2>&1

    PASSWORD_ROOT=$(pwgen -s 18 1)
    PASSWORD_TARGET=$(pwgen -s 18 1)

    echo "root:$PASSWORD_ROOT" | chpasswd
    echo "$TARGET_USER:$PASSWORD_TARGET" | chpasswd

    echo -e "\033[32m*\033[0m GENERATED PASSWORD FOR \033[32mSysOp\033[0m USER: \033[32m\"$PASSWORD_TARGET\"\033[0m"
    echo -e "\033[32m*\033[0m GENERATED PASSWORD FOR \033[32mRoot\033[0m USER: \033[32m\"$PASSWORD_ROOT\"\033[0m"
}

packages() {
    text_editor() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: TEXT EDITOR\n"
        apt-get -y install vim > /dev/null 2>&1
    }

    network_tools() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: NETWORK TOOLS\n"
        TOOLS="nfs-common tcpdump traceroute iperf ethtool geoip-bin socat speedtest-cli bridge-utils"
        apt-get -y install $TOOLS > /dev/null 2>&1
    }

    security() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: SECURITY TOOLS\n"
        apt-get -y install apparmor-utils > /dev/null 2>&1
    }

    compression() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: COMPRESSION\n"
        apt-get -y install unzip xz-utils bzip2 pigz > /dev/null 2>&1
    }

    scripting() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: SCRIPTING\n"
        apt-get -y install sshpass python3-apt > /dev/null 2>&1
    }

    monitoring() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: MONITORING\n"
        MON="screen htop sysstat stress lm-sensors nload smartmontools"
        apt-get -y install $MON > /dev/null 2>&1
    }

    disk_utils() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: DISK UTILITIES\n"
        DISK="hdparm dosfstools cryptsetup uuid uuid-runtime rsync"
        apt-get -y install $DISK > /dev/null 2>&1
    }

    connectivity() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: CONNECTIVITY\n"
        apt-get -y install net-tools > /dev/null 2>&1
    }

    power_mgmt() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: POWER MANAGEMENT\n"
        apt-get -y install pm-utils acpi acpid fwupd > /dev/null 2>&1
    }

    resource_ctrl() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: RESOURCE CONTROL\n"
        apt-get -y install cpulimit > /dev/null 2>&1
    }

    firmware() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: FIRMWARE\n"
        FIRM="firmware-misc-nonfree firmware-realtek firmware-atheros"
        apt-get -y install $FIRM > /dev/null 2>&1
    }

    extra() {
        printf "\e[32m*\e[0m INSTALLING PACKAGE CATEGORY: EXTRA UTILITIES\n"
        apt-get -y install tree > /dev/null 2>&1
    }

    # Call
    text_editor
    network_tools
    security
    compression
    scripting
    monitoring
    disk_utils
    connectivity
    power_mgmt
    resource_ctrl
    firmware
    extra
}

directories() {
    printf "\e[32m*\e[0m CREATING SYSTEM DIRECTORIES\n"
    mkdir -p /mnt/{Temp,Local/{Container/{A,B},USB/{A,B}},Remote/Servers}
    mkdir -p /root/{Temp,.services/scheduled,.crypt}
    chmod 600 /root/.crypt
    
    mkdir -p /var/log/rsync
    chown "$TARGET_USER:$TARGET_USER" -R /var/log/rsync
    su - "$TARGET_USER" -c "mkdir -p /home/$TARGET_USER/{Temp,.services/scheduled,.crypt}"
}

ssh() {
    printf "\e[32m*\e[0m SETTING UP SSH\n"

    # Install the required packages
    apt-get -y install openssh-server sshfs autossh > /dev/null 2>&1

    # Remove existing SSH configuration
    rm /etc/ssh/sshd_config

    # Add new SSH configuration file with custom parameters
    cp sshd_config /etc/ssh/ && chmod 644 /etc/ssh/sshd_config

    # Remove the old motd file and create a new empty one
    rm /etc/motd && touch /etc/motd

    # Adjust root .ssh folder permissions to ensure security
    chmod 600 /root/.ssh

    # Create root SSH key and adjust permissions of authorized keys folder
    touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
    ssh-keygen -t rsa -b 4096 -N '' <<<$'\n' > /dev/null 2>&1
    sed -i "s/@debian$/@$HOSTNAME/" /root/.ssh/id_rsa.pub

    # Create SSH key for specified user and adjust permissions of .ssh folder
    su - "$TARGET_USER" -c "echo | ssh-keygen -t rsa -b 4096 -N '' <<<$'\n'" > /dev/null 2>&1
    su - "$TARGET_USER" -c "sed -i 's/@debian$/@$HOSTNAME/' /home/"$TARGET_USER"/.ssh/id_rsa.pub"
    chmod 700 /home/"$TARGET_USER"/.ssh

    # Create the user's authorized_keys file and adjust permissions
    su - "$TARGET_USER" -c "echo | touch /home/"$TARGET_USER"/.ssh/authorized_keys"
    chmod 600 /home/"$TARGET_USER"/.ssh/authorized_keys
}

network() {
    printf "\e[32m*\e[0m SETTING UP NETWORK\n"

    # Adding Network Configuration File
    cp systemd/scripts/network.sh /root/.services/ && chmod 700 /root/.services/network.sh

    # Disabling services (with full error suppression)
    systemctl disable networking --quiet 2>/dev/null || true
    systemctl disable ModemManager --quiet 2>/dev/null || true
    systemctl disable wpa_supplicant --quiet 2>/dev/null || true
    systemctl disable NetworkManager-wait-online --quiet 2>/dev/null || true
    systemctl disable NetworkManager.service --quiet 2>/dev/null || true

    dhcp() {
        printf "  - Configuring DHCP (KEA)\n"
        apt-get -y install kea-dhcp4-server > /dev/null 2>&1
        cp DHCP/kea-dhcp4.conf /etc/kea/ && chmod 755 /etc/kea
        systemctl disable --now kea-dhcp4-server --quiet
    }

    ntp() {
        printf "  - Configuring NTP (Chrony)\n"
        apt-get -y install chrony > /dev/null 2>&1
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
        systemctl disable --now chrony --quiet
    }

    dns() {
        printf "  - Configuring DNS (BIND9)\n"
        apt-get -y install bind9 bind9-utils bind9-doc dnsutils > /dev/null 2>&1
        rm -rf /etc/bind
        mkdir -p /etc/bind/{zones,keys}
        chown -R bind:bind /etc/bind
        chmod 2755 /etc/bind && chmod 755 /etc/bind/zones && chmod 750 /etc/bind/keys
        
        rndc-confgen -a -c /etc/bind/rndc.key >/dev/null 2>&1
        chown bind:bind /etc/bind/rndc.key && chmod 640 /etc/bind/rndc.key
        
        ( cd /etc/bind/keys
          dnssec-keygen -a ECDSAP256SHA256 -n ZONE "$DOMAIN" >/dev/null 2>&1
          dnssec-keygen -a ECDSAP256SHA256 -n ZONE -f KSK "$DOMAIN" >/dev/null 2>&1
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
	    listen-on { 10.0.6.1; }; listen-on-v6 { none; };
	    forwarders { 1.1.1.1; 8.8.8.8; 9.9.9.9; };
	    forward only; dnssec-validation auto;
	};
	EOF
        
        NEW_SERIAL=$(date '+%Y%m%d%H')
        KEY_FILES=$(find /etc/bind/keys -type f -name "K${DOMAIN}.*.key" | sort)
        ZSK_KEY=$(echo "$KEY_FILES" | head -1)
        KSK_KEY=$(echo "$KEY_FILES" | tail -1)

        cat > "/etc/bind/zones/db.$DOMAIN" <<-EOF
	\$TTL    86400
	@       IN      SOA     ns1.$DOMAIN. admin.$DOMAIN. (
	                        $NEW_SERIAL ; Serial
	                        3600       ; Refresh
	                        1800       ; Retry
	                        604800     ; Expire
	                        86400      ; Minimum TTL
	                )
	        IN      NS      ns1.$DOMAIN.
	ns1     IN      A       0.0.0.0
	@       IN      A       0.0.0.0
	\$INCLUDE "$ZSK_KEY"
	\$INCLUDE "$KSK_KEY"
	EOF
        chown bind:bind "/etc/bind/zones/db.$DOMAIN"
        
        ( cd /etc/bind/zones
          dnssec-signzone -A -3 "$(head /dev/urandom | tr -dc A-F0-9 | head -c8)" -N INCREMENT -o "$DOMAIN" -t -K ../keys "db.$DOMAIN" >/dev/null 2>&1
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

    dhcp
    ntp
    dns
}

firewall() {
    printf "\e[32m*\e[0m SETTING UP FIREWALL\n"
    apt-get -y install nftables rsyslog > /dev/null 2>&1

    systemctl disable --now nftables --quiet
    cp -r systemd/scripts/firewall /root/.services/
    chmod 700 /root/.services/firewall/* && chattr +i /root/.services/firewall/a.sh

    # Logging configuration
    cat <<EOF > /etc/rsyslog.d/50-nftables.conf
:msg, contains, "INPUT_DROP: " /var/log/nftables.log
:msg, contains, "OUTPUT_DROP: " /var/log/nftables.log
:msg, contains, "FORWARD_DROP: " /var/log/nftables.log
& stop
EOF

    cat <<'EOF' > /etc/logrotate.d/nftables
/var/log/nftables.log
{
    rotate 7
    daily
    missingok
    notifempty
    delaycompress
    compress
    postrotate
        systemctl restart rsyslog > /dev/null
    endscript
}
EOF
}

trigger() {
    printf "\e[32m*\e[0m SETTING UP MAIN SYSTEMD SERVICE\n"

    # Adding the main start service
    cp systemd/trigger.service /etc/systemd/system && systemctl enable trigger --quiet

    # Adding central configuration file
    cp systemd/scripts/main.sh /root/.services && chmod 700 /root/.services/main.sh
}

grub() {
    printf "\e[32m*\e[0m SETTING UP GRUB\n"

    # Remove the current GRUB configuration file (if it exists)
    rm -f /etc/default/grub

    # Create a new GRUB configuration file with custom parameters
    printf 'GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""' > /etc/default/grub && chmod 644 /etc/default/grub

    # Update GRUB configuration
    update-grub

    # Completion message
    if [ $? -eq 0 ]; then
        printf "\e[32m*\e[0m GRUB CONFIGURATION UPDATED SUCCESSFULLY\n"
    else
        printf "\e[31m*\e[0m ERROR: FAILED TO UPDATE GRUB CONFIGURATION\n"
    fi
}

later() {
    printf "\e[32m*\e[0m SCHEDULING SUBSEQUENT CONSTRUCTION PROCEDURES AFTER RESTART\n"

    # Grep for UID 1000 (temp ~ user)
    TARGET_USER=$(grep 1000 /etc/passwd | cut -f 1 -d ":")

    if [[ -z "$TARGET_USER" ]]; then
        printf "\e[33m* WARNING: No UID 1000 user found, skipping cleanup\e[0m\n"
        return  # Exit early if no user
    fi

    # Creates the startup script that will be executed after reboot
    printf '#!/bin/bash
### BEGIN INIT INFO
# Provides:          later
# Required-Start:    $all
# Required-Stop:     
# Default-Start:     2 3 4 5
# Default-Stop:      
# Short-Description: Procedures subsequent to instance construction only possible after reboot
### END INIT INFO

# End all processes for user %s
pkill -u %s

# Remove the user %s and its home directory
userdel -r %s

# Remove the WS folder from the /root directory
rm -rf /root/Spiral-UTM-main

# Remove the init.d script after it is executed
rm -f /etc/init.d/later' "$TARGET_USER" "$TARGET_USER" "$TARGET_USER" "$TARGET_USER" > /etc/init.d/later && chmod +x /etc/init.d/later

    # Add the script to the services that will start at boot
    update-rc.d later defaults
}

finish() {
    apt-get -y autoremove > /dev/null 2>&1
    rm -f /etc/network/interfaces
    systemctl disable networking --quiet

    printf "\e[32m*\e[0m INSTALLATION COMPLETED SUCCESSFULLY!\n"
    printf "  - Connect to port: \e[32m%s\e[0m\n" "$LAN0"
    printf "  - Set IP to: \e[32m169.254.0.2/30\e[0m\n"
    printf "  - Access via: \e[32mssh -p 444 sysop@169.254.0.1\e[0m\n"

    read -p "DO YOU WANT TO RESTART? (Y/N): " response
    response=${response^^}
    if [[ "$response" == "Y" ]]; then
        printf "\e[32m*\e[0m RESTARTING...\n"
        systemctl reboot
    elif [[ "$response" == "N" ]]; then
        printf "\e[32m*\e[0m WILL NOT BE RESTARTED.\n"
    else
        printf "\e[31m*\e[0m ERROR: PLEASE ANSWER WITH 'Y' FOR YES OR 'N' FOR NO.\n"
    fi
}

main() {
    update
    interface
    domain
    global_settings
    hostname
    target_user
    passwords
    packages
    directories
    ssh
    network
    firewall
    trigger
    grub
    later
    finish
}

# Execute main function
main