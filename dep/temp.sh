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