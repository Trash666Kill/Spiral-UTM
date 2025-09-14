#!/bin/bash

# Close on any error (Optional)
#set -e

# Function to establish tunnel for port 4533
tunnel_port_4533() {
    local REMOTE_HOST="frlfryiwad7efpapvov5wnqzbf.com.br"
    local REMOTE_PORT=4635
    local REMOTE_USER="root"
    local SERVER_ALIVE_INTERVAL=60
    local LOCAL_IP="172.16.10.2"
    local LOCAL_PORT=4533
    local STRICT_HOST_KEY_CHECKING="true"

    autossh -M 0 -f -N -T \
        -R ${LOCAL_PORT}:${LOCAL_IP}:${LOCAL_PORT} \
        -p ${REMOTE_PORT} \
        ${REMOTE_USER}@${REMOTE_HOST} \
        -o StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING} \
        -o ServerAliveInterval=${SERVER_ALIVE_INTERVAL}
}

# Function to establish tunnel for port 8096
tunnel_port_8096() {
    local REMOTE_HOST="frlfryiwad7efpapvov5wnqzbf.com.br"
    local REMOTE_PORT=4635
    local REMOTE_USER="root"
    local SERVER_ALIVE_INTERVAL=60
    local LOCAL_IP="172.16.10.2"
    local LOCAL_PORT=8096
    local STRICT_HOST_KEY_CHECKING="true"

    autossh -M 0 -f -N -T \
        -R ${LOCAL_PORT}:${LOCAL_IP}:${LOCAL_PORT} \
        -p ${REMOTE_PORT} \
        ${REMOTE_USER}@${REMOTE_HOST} \
        -o StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING} \
        -o ServerAliveInterval=${SERVER_ALIVE_INTERVAL}
}

# Main function to orchestrate the tunnels
main() {
    TUNNELS="
    tunnel_port_4533
    tunnel_port_8096
    "

    for TUNNEL in $TUNNELS
    do
        $TUNNEL
        sleep 4
    done
}

# Execute main function
main