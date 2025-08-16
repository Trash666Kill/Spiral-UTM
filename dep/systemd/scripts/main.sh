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
VIRTUAL_MACHINE_SCRIPT="/root/.services/virtual-machine.sh"
CONTAINER_SCRIPT="/root/.services/container.sh"

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

virtual_machine() {
    if [[ -f "$VIRTUAL_MACHINE_SCRIPT" ]]; then
        if [[ -x "$VIRTUAL_MACHINE_SCRIPT" ]]; then
            printf "\e[33m*\e[0m Running $VIRTUAL_MACHINE_SCRIPT...\n"
            bash "$VIRTUAL_MACHINE_SCRIPT"
            if [[ $? -ne 0 ]]; then
                printf "\e[31m*\e[0m Error: $VIRTUAL_MACHINE_SCRIPT failed to execute successfully.\n"
                exit 1
            fi
        else
            printf "\e[31m*\e[0m Error: $VIRTUAL_MACHINE_SCRIPT does not have execute permission.\n"
            exit 1
        fi
    else
        printf "\e[31m*\e[0m Error: $VIRTUAL_MACHINE_SCRIPT not found.\n"
        exit 1
    fi
}

container() {
    if [[ -f "$CONTAINER_SCRIPT" ]]; then
        if [[ -x "$CONTAINER_SCRIPT" ]]; then
            printf "\e[33m*\e[0m Running $CONTAINER_SCRIPT...\n"
            bash "$CONTAINER_SCRIPT"
            if [[ $? -ne 0 ]]; then
                printf "\e[31m*\e[0m Error: $CONTAINER_SCRIPT failed to execute successfully.\n"
                exit 1
            fi
        else
            printf "\e[31m*\e[0m Error: $CONTAINER_SCRIPT does not have execute permission.\n"
            exit 1
        fi
    else
        printf "\e[31m*\e[0m Error: $CONTAINER_SCRIPT not found.\n"
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
    network
    ssh
    ntp
    firewall
    dhcp
    dns
    virtual_machine
    container
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