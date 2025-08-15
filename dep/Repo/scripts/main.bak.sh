#!/bin/bash

# - Description: Orchestrates the execution of network.sh and firewall.sh scripts.
# - Ensures firewall.sh runs only if network.sh executes successfully.
# - Exits with an error if any script is missing or fails.
# - To add new scripts, copy and edit a variable and function, such as network or firewall.

# Close on any error
set -e

# Paths to the scripts
NETWORK_SCRIPT="/root/.services/network.sh"
FIREWALL_SCRIPT="/root/.services/firewall.sh"

network() {
    if [[ -f "$NETWORK_SCRIPT" ]]; then
        if [[ -x "$NETWORK_SCRIPT" ]]; then
            printf "\e[33m*\e[0m Running $NETWORK_SCRIPT...\n"
            bash "$NETWORK_SCRIPT"
            if [[ $? -ne 0 ]]; then
                printf "\e[31m*\e[0m Error: $NETWORK_SCRIPT failed to execute successfully.\n"
                exit 1
            fi
        else
            printf "\e[31m*\e[0m Error: $NETWORK_SCRIPT does not have execute permission.\n"
            exit 1
        fi
    else
        printf "\e[31m*\e[0m Error: $NETWORK_SCRIPT not found.\n"
        exit 1
    fi
}

firewall() {
    if [[ -f "$FIREWALL_SCRIPT" ]]; then
        if [[ -x "$FIREWALL_SCRIPT" ]]; then
            printf "\e[33m*\e[0m Running $FIREWALL_SCRIPT...\n"
            bash "$FIREWALL_SCRIPT"
            if [[ $? -ne 0 ]]; then
                printf "\e[31m*\e[0m Error: $FIREWALL_SCRIPT failed to execute successfully.\n"
                exit 1
            fi
        else
            printf "\e[31m*\e[0m Error: $FIREWALL_SCRIPT does not have execute permission.\n"
            exit 1
        fi
    else
        printf "\e[31m*\e[0m Error: $FIREWALL_SCRIPT not found.\n"
        exit 1
    fi
}

dns() {
    local SERVICE=dnsmasq
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

dhcp() {
    local SERVICE=kea-dhcp4-server
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

ntp() {
    local SERVICE=chrony
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

ssh() {
    local SERVICE=ssh
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

others() {
    # Red power LED - 1 = ON, 0 = OFF
    echo 0 | tee /sys/class/leds/PWR/brightness
    echo 0 | tee /sys/class/leds/ACT/brightness
}

# Main function to orchestrate the setup
main() {
    # Array of commands
    commands=("network" "ssh" "ntp" "firewall" "dns" "dhcp" "others")
    
    # Execute each command with delay
    for cmd in "${commands[@]}"; do
        $cmd
        sleep 4
    done
}

# Execute main function
main

printf '\e[32m*\e[0m All scripts and services executed successfully!\n'
exit 0