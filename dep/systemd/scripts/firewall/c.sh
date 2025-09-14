#!/bin/bash

# Close on any error (Optional)
#set -e

wireguard() {

}

autossh() {
    local AUTOSSH_SCRIPT="/root/.services/firewall/autossh.sh"
    # Filter Rules
    nft add rule inet firelux output tcp dport 4635 accept
    nft add rule inet firelux output tcp dport 4533 accept
    nft add rule inet firelux output tcp dport 8096 accept
    nft add rule inet firelux output tcp dport 9091 accept
    nft add rule inet firelux output tcp dport 8080 accept

    # Call
    sleep 2
    bash "$AUTOSSH_SCRIPT"
}

# Main function to orchestrate the setup
main() {
    RULES="
    wireguard
    autossh
    "

    for RULE in $RULES
    do
        $RULE
        sleep 4
    done
}

# Execute main function
#main