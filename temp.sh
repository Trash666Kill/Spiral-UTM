#!/bin/bash

# Close on any error
set -e

kernel_hardening() {
    echo "Applying Kernel Security Settings..."
    
    # Enable IP forwarding (Existing requirement)
    sysctl -w net.ipv4.ip_forward=1 > /dev/null

    # Anti-Spoofing: Enable strict reverse path filtering
    sysctl -w net.ipv4.conf.all.rp_filter=1 > /dev/null
    sysctl -w net.ipv4.conf.default.rp_filter=1 > /dev/null

    # Ignore ICMP Broadcasts (Smurf attack protection)
    sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 > /dev/null
    
    # Ignore Bogus ICMP errors
    sysctl -w net.ipv4.icmp_ignore_bogus_error_responses=1 > /dev/null

    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to apply kernel hardening.\n"
        exit 1
    fi
}

ids() {
    local SERVICE=firelux
    # Check if service exists before trying to restart to avoid breaking script if not installed yet
    if systemctl list-units --full -all | grep -Fq "$SERVICE.service"; then
        systemctl restart "$SERVICE"
    fi
}

# Restart nftables service
restart_nftables() {
    local SERVICE=nftables
    echo "Restarting $SERVICE..."
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

# Flush existing nftables rules
flush_nftables() {
    echo "Flushing ruleset..."
    nft flush ruleset
}

# Create main table
main_table() {
    echo "Creating table..."
    nft add table inet firelux
}

# Create chains with default drop policy
chains() {
    echo "Creating chains..."
    nft add chain inet firelux input { type filter hook input priority 0 \; policy drop \; }
    nft add chain inet firelux output { type filter hook output priority 0 \; policy drop \; }
    nft add chain inet firelux forward { type filter hook forward priority filter \; policy drop \; }
    nft add chain inet firelux prerouting { type nat hook prerouting priority 0 \; policy accept \; }
    nft add chain inet firelux postrouting { type nat hook postrouting priority srcnat \; policy accept \; }
}

# STATE SANITY (Drop Invalid)
# Silently discards broken packets before any logging; this saves IDS CPU.
drop_invalid() {
    echo "Configuring Invalid State Drops..."
    nft add rule inet firelux input ct state invalid drop
    nft add rule inet firelux forward ct state invalid drop
    nft add rule inet firelux output ct state invalid drop
}

# Main function for the whitelist system
whitelist() {
    echo "Configuring whitelist Sets..."

    manual() {
        nft add set inet firelux whitelist_manual { type ipv4_addr \; flags interval \; }
        nft add rule inet firelux input ip saddr @whitelist_manual accept
        nft add rule inet firelux forward ip saddr @whitelist_manual accept
    }

    # Call Child Functions
    manual
}

# Main function for the blacklist system
blacklist() {
    echo "Configuring Blacklist Sets..."

    # 1. PUNISHMENT (IDS) - Check FIRST (High Performance)
    punishment() {
        nft add set inet firelux blacklist_punishment { type ipv4_addr \; flags interval, timeout \; }
        nft add rule inet firelux input ip saddr @blacklist_punishment drop
        nft add rule inet firelux forward ip saddr @blacklist_punishment drop
    }

    # 2. DNS Manager (Priority & Bulk)
    domain() {
        priority() {
                nft add set inet firelux blacklist_priority { type ipv4_addr \; flags interval \; }
                nft add rule inet firelux input ip saddr @blacklist_priority drop
                nft add rule inet firelux output ip daddr @blacklist_priority drop
                nft add rule inet firelux forward ip saddr @blacklist_priority drop
        }

        bulk() {
                nft add set inet firelux blacklist_bulk { type ipv4_addr \; flags interval \; }
                nft add rule inet firelux input ip saddr @blacklist_bulk drop
                nft add rule inet firelux output ip daddr @blacklist_bulk drop
                nft add rule inet firelux forward ip saddr @blacklist_bulk drop
        }

        priority
        bulk
    }

    # 3. Static Lists
    auto() {
        nft add set inet firelux blacklist_auto { type ipv4_addr \; flags interval \; }
        nft add rule inet firelux input ip saddr @blacklist_auto drop
        nft add rule inet firelux forward ip saddr @blacklist_auto drop
    }

    manual() {
        nft add set inet firelux blacklist_manual { type ipv4_addr \; flags interval \; }
        nft add rule inet firelux input ip saddr @blacklist_manual drop
        nft add rule inet firelux forward ip saddr @blacklist_manual drop
    }

    # Order of Execution
    punishment
    domain
    manual
    auto
}

# Allow established and related connections (Stateful firewall)
established_related() {
    echo "Allowing established/related connections..."
    nft add rule inet firelux input ct state established,related accept
    nft add rule inet firelux output ct state established,related accept
    nft add rule inet firelux forward ct state established,related accept
}

# Configure host-specific rules
host() {
    echo "Configuring host rules..."
    # Filter Rules
    loopback() {
        nft add rule inet firelux input iif "lo" accept
        nft add rule inet firelux output oif "lo" accept
    }

    # Filter Rules
    icmp() {
        nft add rule inet firelux input icmp type { echo-request, echo-reply, destination-unreachable, time-exceeded } accept
        nft add rule inet firelux output icmp type { echo-request, echo-reply, destination-unreachable, time-exceeded } accept
    }

    # Filter Rules
    dns() {
        # Allow DNS output (Required for IDS/DNS Manager to fetch lists)
        nft add rule inet firelux output udp dport 53 accept
        nft add rule inet firelux output tcp dport 53 accept
    }

    # Filter Rules
    ntp() {
        nft add rule inet firelux output udp dport 123 accept
    }

    # Filter Rules
    web() {
        # Allow HTTP/HTTPS output (Required for IDS/DNS Manager to fetch lists)
        nft add rule inet firelux output tcp dport 80 accept
        nft add rule inet firelux output tcp dport 443 accept
    }

   # Azure WireServer
    azure_wireserver() {
        nft add rule inet firelux output ip daddr 168.63.129.16 tcp dport 32526 counter accept
        nft add rule inet firelux output ip daddr 168.63.129.16 tcp dport 80 counter accept
        nft add rule inet firelux output ip daddr 168.63.129.16 tcp dport 443 counter accept
    }

    # Call Child Functions
    loopback
    icmp
    dns
    ntp
    web
    azure_wireserver
}

# LOGGING (CPU PROTECTION) Logs packets that survived all drops above and hit the default policy.
# Adds Rate Limiting to prevent CPU DoS on the IDS Python script.
setup_logging() {
    echo "Setting up logging with Rate Limiting..."
    
    # Input: Limit to 20 logs/min with initial burst of 10
    nft add rule inet firelux input limit rate 20/minute burst 10 packets log prefix \"INPUT_DROP: \" level info
    
    # Forward: Same limit
    nft add rule inet firelux forward limit rate 20/minute burst 10 packets log prefix \"FORWARD_DROP: \" level info
    
    # Output: Usually less noisy, but good practice to limit
    nft add rule inet firelux output limit rate 20/minute burst 10 packets log prefix \"OUTPUT_DROP: \" level info
}

# Main function to orchestrate the setup
main() {
    RULES="
    kernel_hardening
    restart_nftables
    flush_nftables
    main_table
    chains
    drop_invalid
    whitelist
    blacklist
    established_related
    host
    setup_logging
    "

    for RULE in $RULES
    do
        $RULE
    done
    
    echo "Firewall applied successfully."
}

# Execute main function
main