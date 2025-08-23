setup_firewall() {
    log_info "Starting Firewall Setup"
    
    # Install required dependencies
    run_apt install nftables rsyslog

    # Configure firewall services and scripts
    systemctl disable --now nftables --quiet
    cp -r systemd/scripts/firewall /root/.services/
    chmod 700 /root/.services/firewall/*
    chattr +i /root/.services/firewall/a.sh

    # --- Added Logging Logic ---

    log_info "Configuring rsyslog for nftables logging..."
    # Create the rsyslog configuration file to filter nftables logs
    cat <<EOF > /etc/rsyslog.d/50-nftables.conf
# /etc/rsyslog.d/50-nftables.conf
:msg, contains, "INPUT_DROP: " /var/log/nftables.log
:msg, contains, "OUTPUT_DROP: " /var/log/nftables.log
:msg, contains, "FORWARD_DROP: " /var/log/nftables.log
& stop
EOF

    log_info "Setting up log rotation for nftables..."
    # Create the configuration file for nftables log rotation
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