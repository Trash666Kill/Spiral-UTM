#!/bin/bash
# - SCRIPT TO BUILD A PRODUCTION AND DEVELOPMENT FIREWALL FOLLOWING THE SPIRAL PATTERN

environment () {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root."
        exit 1
    fi

    # Disable Bash history
    unset HISTFILE

    # Restrict permissions
    umask 077

    connectiontest() {
        # Test the connectivity to the Debian repositories
        printf "\e[32m*\e[0m TRYING TO CONNECT TO THE INTERNET, WAIT...\n"
        if ! ping -4 -c 4 debian.org &>/dev/null; then
            printf "ERROR: UNABLE TO CONNECT TO \e[32mDEBIAN REPOSITORIES\e[0m\n"
            exit 1
        fi
    }

    # Call
    connectiontest
}

domain() {
    # Normalize hostname to lowercase
    CURRENT_HOSTNAME=$(hostname)
    LOWER_HOSTNAME=$(echo "$CURRENT_HOSTNAME" | tr '[:upper:]' '[:lower:]')

    # Function to validate domain name
    validate_domain() {
        local domain=$1
        if [[ $domain =~ ^[a-zA-Z0-9.-]+$ ]]; then
            return 0
        else
            return 1
        fi
    }

    # Prompt for domain name
    prompt() {
        while true; do
            read -p "Enter the domain name (e.g., example.local): " DOMAIN
            if [[ -z "$DOMAIN" ]]; then
                echo "Domain name cannot be empty. Please provide a valid domain."
                continue
            fi
            DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]') # Convert input to lowercase
            if validate_domain "$DOMAIN"; then
                break
            else
                echo "Invalid domain name. Use only alphanumeric characters, hyphens, and dots."
            fi
        done
    }

    # Set environment domain
    envdom() {
        sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$LOWER_HOSTNAME.$DOMAIN/" /etc/hosts
    }

    # Call
    prompt
    envdom
}

# Packages
packages() {
    printf "\e[32m*\e[0m INSTALLING PACKAGES\n"
    DEPENDENCIES="bind9 bind9-utils bind9-doc dnsutils tcpdump cron"
    apt -y install $DEPENDENCIES > /dev/null 2>&1
}

# Creating directories and setting the necessary permissions
directories() {
    rm -r /etc/bind && mkdir -p /etc/bind/{zones,keys} && chmod 2755 /etc/bind && cd /etc/bind
    chown bind:bind * && chmod 755 zones && chmod 750 keys
}

# Generating files
bind9() {
    rndc() {
        # Generate RNDC key
        rndc-confgen -a && chown bind:bind rndc.key && chmod 640 rndc.key
    }

    dnssec() {
        # Generate DNSSEC key
        cd keys
        dnssec-keygen -a ECDSAP256SHA256 -n ZONE "$DOMAIN" || { echo "Failed to generate ZSK"; exit 1; }
        dnssec-keygen -a ECDSAP256SHA256 -n ZONE -f KSK "$DOMAIN" || { echo "Failed to generate KSK"; exit 1; }
        chown bind:bind * && chmod 600 *.private && chmod 644 *.key
cd ../zones
    }

    named() {
    cd ../
    printf 'include "/etc/bind/rndc.key";\ninclude "/etc/bind/named.conf.options";\ninclude "/etc/bind/named.conf.local";\n' > named.conf && chown bind:bind named.conf && chmod 644 named.conf
    }

    options() {
        printf 'options {\n    directory "/var/cache/bind";\n    recursion yes; # Enable recursion for forwarding\n    allow-query { any; }; # Allow queries from any source\n    listen-on { any; }; # Listen on all interfaces\n    listen-on-v6 { none; }; # Disable IPv6 (optional)\n    forwarders {\n        1.1.1.1; # Cloudflare\n        8.8.8.8; # Google\n        9.9.9.9; # Quad9\n    };\n    forward only; # Use only forwarders for external queries\n    dnssec-validation auto; # Validate responses from other zones\n};\n' > named.conf.options && chown bind:bind named.conf.options && chmod 644 named.conf.options
    }

    zone() {
        # Calculate serial based on UTC date and time
        NEW_SERIAL=$(date '+%Y%m%d%H')

        # Listening address
        ADDRESS="0.0.0.0"

        # Get key filenames dynamically (case-insensitive)
        KEY_FILES=$(find /etc/bind/keys -type f -iname "K${DOMAIN}.*.key" | sort)
        ZSK_KEY=$(echo "$KEY_FILES" | head -1)
        KSK_KEY=$(echo "$KEY_FILES" | tail -1)

        printf '$TTL    86400\n@       IN      SOA     ns1.%s. admin.%s. (\n                        %s ; Serial\n                        3600       ; Refresh\n                        1800       ; Retry\n                        604800     ; Expire\n                        86400      ; Minimum TTL\n                )\n; Name servers\n        IN      NS      ns1.%s.\nns1     IN      A       %s\n\n; Zone records\n@       IN      A       %s\n;SRV01   IN      A       172.16.10.1 ; Redirect SRV01 to 172.16.10.1\n;SRV02   IN      A       172.16.10.2 ; Redirect SRV02 to 172.16.10.2\n\n; Include DNSSEC keys\n$INCLUDE "%s"\n$INCLUDE "%s"\n' "$DOMAIN" "$DOMAIN" "$NEW_SERIAL" "$DOMAIN" "$ADDRESS" "$ADDRESS" "$ZSK_KEY" "$KSK_KEY" > zones/"db.$DOMAIN" && chown bind:bind zones/"db.$DOMAIN" && chmod 644 zones/"db.$DOMAIN"

        # Sign the zone
        dnssec-signzone -A -3 $(head /dev/urandom | tr -dc A-F0-9 | head -c8) -N INCREMENT -o "$DOMAIN" -t -K keys zones/"db.$DOMAIN" && chown bind:bind zones/"db.$DOMAIN.signed" && chmod 644 zones/"db.$DOMAIN.signed"
    }

    zone_config() {
        printf 'zone "%s" {\n    type master;\n    file "/etc/bind/zones/db.%s.signed";\n    allow-transfer { none; };\n};\n' "$DOMAIN" "$DOMAIN" > named.conf.local && chown bind:bind named.conf.local && chmod 644 named.conf.local
    }

    # Call
    rndc
    dnssec
    named
    options
    zone
    zone_config
}

finalizing() {
    systemctl restart named --quiet
    sleep 3
    rndc status
    rndc reload
    rndc stop
    systemctl disable --now named --quiet
}

# Main function to orchestrate the setup
main() {
    environment
    domain
    packages
    directories
    bind9
    finalizing
}

# Execute main function
main