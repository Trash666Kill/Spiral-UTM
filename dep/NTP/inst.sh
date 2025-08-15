apt remove --purge systemd-timesyncd
apt install chrony
systemctl disable --now chrony
cp /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
echo "America/Sao_Paulo" >  /etc/timezone
sed -i '/^pool 2\.debian\.pool\.ntp\.org iburst/d' /etc/chrony/chrony.conf
printf '# Servidores NTP Upstream
pool b.st1.ntp.br iburst
pool a.st1.ntp.br iburst
pool 200.186.125.195 iburst

# Interface de escuta e resposta
allow all' >> /etc/chrony/chrony.conf
systemctl restart chrony


#!/bin/bash

# Placeholder variables for demonstration.
# In a real script, these would be set by other functions.
INTERFACE="enp1s0"
TIMEZONE="America/Sao_Paulo"
HOSTNAME="my-utm"
TARGET_USER="sysop"


# Main function to configure various network services.
setup_network_services() {
    # --- Nested function for NTP Configuration (Using Chrony) ---
    setup_ntp() {
        printf "\n\e[1;36m---  Configuring NTP (Chrony)  ---\e[0m\n"

        printf "\n\e[32m*\e[0m Removing existing time service (systemd-timesyncd)...\n"
        if apt-get remove --purge -y systemd-timesyncd > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[33mℹ️  Could not remove package (it may not have been installed).\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Installing new time service (chrony)...\n"
        if apt-get install -y chrony > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error: Failed to install chrony.\e[0m\n"
            return 1 # Stop this sub-function if chrony can't be installed
        fi
        
        printf "\n\e[32m*\e[0m Disabling chrony service temporarily...\n"
        if systemctl disable --now chrony --quiet; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error\e[0m\n"
        fi
        
        printf "\n\e[32m*\e[0m Setting system timezone to 'America/Sao_Paulo'...\n"
        if cp /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime && echo "America/Sao_Paulo" > /etc/timezone; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error: Failed to set timezone files.\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Configuring chrony NTP servers...\n"
        # Define the content to be added to the config file
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
        # First remove the default debian pool, then append the new configuration
        if sed -i '/^pool 2\.debian\.pool\.ntp\.org iburst/d' /etc/chrony/chrony.conf && printf "%s" "$CHRONY_CONFIG_ADDITIONS" >> /etc/chrony/chrony.conf; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error: Failed to modify /etc/chrony/chrony.conf.\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Restarting chrony service to apply changes...\n"
        if systemctl restart chrony; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error: Failed to restart chrony service.\e[0m\n"
        fi
    }

    # --- Nested function for DNS Configuration ---
    setup_dns() {
        # This function remains as it was in the previous step
        printf "\n\e[1;36m---  Configuring DNS (Dnsmasq)  ---\e[0m\n"

        printf "\n\e[32m*\e[0m Installing dnsmasq and utilities...\n"
        if apt-get -y install dnsmasq dnsutils tcpdump > /dev/null 2>&1; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[33mℹ️  Could not install packages (they may already be installed).\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Disabling dnsmasq service (if active)...\n"
        if systemctl disable --now dnsmasq --quiet; then
             printf "  \e[32m✅ Success\e[0m\n"
        else
             printf "  \e[31m❗ Error\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Removing default dnsmasq configuration...\n"
        rm /etc/dnsmasq.conf > /dev/null 2>&1
        printf "  \e[32m✅ Success\e[0m\n"

        printf "\n\e[32m*\e[0m Copying main dnsmasq configuration...\n"
        if cp systemd/scripts/main.conf /etc/dnsmasq.d/; then
             printf "  \e[32m✅ Success\e[0m\n"
        else
             printf "  \e[31m❗ Error: Failed to copy main.conf.\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Setting local domain based on hostname...\n"
        if [ -z "$HOSTNAME" ]; then
            printf "  \e[31m❗ Error: HOSTNAME variable is not set.\e[0m\n"
        elif sed -i "s/domain=.*/domain=$HOSTNAME.local/" /etc/dnsmasq.d/main.conf; then
             printf "  \e[32m✅ Success\e[0m\n"
        else
             printf "  \e[31m❗ Error: Failed to set domain in main.conf.\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Creating dnsmasq configuration sub-directories...\n"
        if mkdir -p /etc/dnsmasq.d/config; then
             printf "  \e[32m✅ Success\e[0m\n"
        else
             printf "  \e[31m❗ Error\e[0m\n"
        fi
        
        printf "\n\e[32m*\e[0m Creating local hosts file for dnsmasq...\n"
        if printf '10.0.10.254 %s.local' "$HOSTNAME" > /etc/dnsmasq.d/config/hosts; then
             printf "  \e[32m✅ Success\e[0m\n"
        else
             printf "  \e[31m❗ Error\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Creating upstream DNS server file for dnsmasq...\n"
        if grep '^nameserver' /etc/resolv.conf | awk '{print "nameserver " $2}' | tee /etc/dnsmasq.d/config/resolv > /dev/null; then
             printf "  \e[32m✅ Success\e[0m\n"
        else
             printf "  \e[31m❗ Error\e[0m\n"
        fi

        printf "\n\e[32m*\e[0m Creating IP reservations file for dnsmasq...\n"
        if touch /etc/dnsmasq.d/config/reservations; then
             printf "  \e[32m✅ Success\e[0m\n"
        else
             printf "  \e[31m❗ Error\e[0m\n"
        fi
    }

    # --- Main function execution starts here ---
    printf "\n\e[1;34m--- Starting Network Configuration ---\e[0m\n"

    printf "\n\e[32m*\e[0m Copying network script...\n"
    if cp systemd/scripts/network.sh /root/.services/ && chmod 700 /root/.services/network.sh; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error\e[0m\n"
    fi

    printf "\n\e[32m*\e[0m Installing dhcpcd package...\n"
    if apt-get -y install dhcpcd > /dev/null 2>&1; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[33mℹ️  Could not install package (it may already be installed).\e[0m\n"
    fi

    printf "\n\e[32m*\e[0m Disabling conflicting network services...\n"
    if systemctl disable networking --quiet && systemctl disable ModemManager --quiet && systemctl disable wpa_supplicant --quiet && systemctl disable dhcpcd --quiet && systemctl disable NetworkManager-wait-online --quiet && systemctl disable NetworkManager.service --quiet; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error: Failed to disable one or more services.\e[0m\n"
    fi

    printf "\n\e[32m*\e[0m Configuring dhcpcd...\n"
    if sed -i -e '$a\' -e '\n# Custom\n#Try DHCP on all interfaces\nallowinterfaces br_vlan710\n\n# Waiting time to try to get an IP (in seconds)\ntimeout 0  # 0 means try indefinitely' /etc/dhcpcd.conf; then
        printf "  \e[32m✅ Success\e[0m\n"
    else
        printf "  \e[31m❗ Error\e[0m\n"
    fi

    printf "\n\e[32m*\e[0m Updating network script with interface details...\n"
    if [ -z "$INTERFACE" ]; then
        printf "  \e[31m❗ Error: INTERFACE variable is not set.\e[0m\n"
    else
        local MAC
        MAC=$(ip link show "$INTERFACE" | awk '/ether/ {print $2}')
        if sed -i "s/NIC0=.*/NIC0=\"$INTERFACE\"/" /root/.services/network.sh && sed -i "/ip link set dev br_vlan710 address/s/$/ $MAC/" /root/.services/network.sh; then
            printf "  \e[32m✅ Success\e[0m\n"
        else
            printf "  \e[31m❗ Error: Failed to update network script with interface details.\e[0m\n"
        fi
    fi

    # Call nested functions
    setup_ntp
    setup_dns

    printf "\n\e[1;34m--- Network Configuration Complete ---\e[0m\n"
}

# --- How to Use ---
setup_network_services