#!/bin/bash

# - Description: Orchestrates network and firewall configuration for virtual machines.
# - Executes network.sh and firewall.sh, with an optional function to restart services.
# - Ensures each script has execute permission and exits on errors using set -e.
# - To add new scripts or services, copy and edit functions like network or others.

# Close on any error
set -e

# Paths to the scripts
NETWORK_SCRIPT="/root/.services/network.sh"
FIREWALL_FOLDER="/root/.services/firewall"

set_printk() {
    local PARAM="kernel.printk"
    local VALUE="4 4 1 7"

    # Attempt to set the kernel parameter value
    sysctl -w "$PARAM"="$VALUE"

    # Check the exit code of the last command
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to set parameter %s.\n" "$PARAM"
        printf "  Check if you are running the command with root privileges (sudo).\n"
        return 1 # Returns an error, but does not close the terminal
    fi

    printf "\e[32m✔\e[0m Parameter '%s' successfully set to '%s'.\n" "$PARAM" "$VALUE"
}

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

ssh() {
    local SERVICE=ssh
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

# Function to orchestrate the firewall levels
firewall() {
    # Array of firewall scripts
    scripts=(
        "$FIREWALL_FOLDER/a.sh"
        "$FIREWALL_FOLDER/b.sh"
    )

    # Loop through each script and execute it
    for script in "${scripts[@]}"; do
        bash "$script"
        sleep 6
    done
}

dhcp() {
    local SERVICE=kea-dhcp4-server
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

dns() {
    local SERVICE=named
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

others() {
    local SERVICE=
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

# Main function to orchestrate the setup
main() {
    SERVICES="
    set_printk
    network
    ssh
    ntp
    firewall
    dhcp
    dns
    "

    for SERVICE in $SERVICES
    do
        $SERVICE
        sleep 4
    done
}

# Execute main function
main

printf '\e[32m*\e[0m All scripts and services executed successfully!\n'
exit 0