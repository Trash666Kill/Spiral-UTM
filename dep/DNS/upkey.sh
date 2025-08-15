#!/bin/bash

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Read domain from named.conf.local
NAMED_CONF="/etc/bind/named.conf.local"
if [[ ! -f "$NAMED_CONF" ]]; then
    echo "Error: $NAMED_CONF not found."
    exit 1
fi

DOMAIN=$(grep 'zone' "$NAMED_CONF" | awk '{print $2}' | tr -d '";' | head -1 | tr '[:upper:]' '[:lower:]')
if [[ -z "$DOMAIN" ]]; then
    echo "Error: Could not extract domain from $NAMED_CONF."
    exit 1
fi

# Extract zone file path
ZONE_FILE=$(grep 'file' "$NAMED_CONF" | awk '{print $2}' | tr -d '";' | head -1)
if [[ -z "$ZONE_FILE" || ! -f "$ZONE_FILE" ]]; then
    echo "Error: Zone file for $DOMAIN not found."
    exit 1
fi
ZONE_FILE_BASE=$(basename "$ZONE_FILE" .signed)
ZONE_FILE_PATH="/etc/bind/zones/$ZONE_FILE_BASE"

# Create or clear keys directory
KEYS_DIR="/etc/bind/keys"
if [[ -d "$KEYS_DIR" ]]; then
    rm -f "$KEYS_DIR"/*
else
    mkdir -p "$KEYS_DIR"
fi
chown bind:bind "$KEYS_DIR"
chmod 750 "$KEYS_DIR"

# Generate DNSSEC keys
cd "$KEYS_DIR"
dnssec-keygen -a ECDSAP256SHA256 -n ZONE "$DOMAIN" || { echo "Failed to generate ZSK"; exit 1; }
dnssec-keygen -a ECDSAP256SHA256 -n ZONE -f KSK "$DOMAIN" || { echo "Failed to generate KSK"; exit 1; }
chown bind:bind *
chmod 600 *.private
chmod 644 *.key

# Get key filenames
KEY_FILES=$(ls -t "$KEYS_DIR"/K${DOMAIN}.*.key 2>/dev/null)
ZSK_KEY=$(echo "$KEY_FILES" | tail -1)
KSK_KEY=$(echo "$KEY_FILES" | head -1)
if [[ -z "$ZSK_KEY" || -z "$KSK_KEY" ]]; then
    echo "Error: Could not find DNSSEC key files for $DOMAIN."
    exit 1
fi

# Get current serial and generate new serial
CURRENT_SERIAL=$(grep -E '^[[:space:]]*[0-9]+[[:space:]]*;[[:space:]]*Serial' "$ZONE_FILE_PATH" | awk '{print $1}')
echo "Current serial: $CURRENT_SERIAL"
NEW_SERIAL=$(printf "%04d%02d%02d%02d" $(date -u '+%Y %m %d %H'))
if [[ -n "$CURRENT_SERIAL" && "$NEW_SERIAL" -le "$CURRENT_SERIAL" ]]; then
    NEW_SERIAL=$((CURRENT_SERIAL + 1))
fi
echo "New serial: $NEW_SERIAL"
if [[ ! "$NEW_SERIAL" =~ ^[0-9]{10,12}$ ]]; then
    echo "Error: Invalid serial format: $NEW_SERIAL"
    exit 1
fi

# Update zone file
TEMP_ZONE=$(mktemp)
cp "$ZONE_FILE_PATH" "$TEMP_ZONE"
sed -i "s/^[ \t]*[0-9]\+[ \t]*;[ \t]*Serial/$NEW_SERIAL ; Serial/" "$TEMP_ZONE"
sed -i '/$INCLUDE.*key/d; /; Include DNSSEC keys/d' "$TEMP_ZONE"
sed -i ':a; /^[ \t]*$/{$d; N; ba}' "$TEMP_ZONE"
echo -n "$(cat "$TEMP_ZONE")" > "$TEMP_ZONE"
echo '' >> "$TEMP_ZONE"
echo '; Include DNSSEC keys' >> "$TEMP_ZONE"
echo '$INCLUDE "'"$ZSK_KEY"'"' >> "$TEMP_ZONE"
echo '$INCLUDE "'"$KSK_KEY"'"' >> "$TEMP_ZONE"
mv "$TEMP_ZONE" "$ZONE_FILE_PATH"
chown bind:bind "$ZONE_FILE_PATH"
chmod 644 "$ZONE_FILE_PATH"

# Sign zone (suppress detailed output)
dnssec-signzone -A -3 $(head /dev/urandom | tr -dc A-F0-9 | head -c8) -N INCREMENT -o "$DOMAIN" -K "$KEYS_DIR" "$ZONE_FILE_PATH" > /dev/null || { echo "Failed to sign zone"; exit 1; }
chown bind:bind "$ZONE_FILE_PATH.signed"
chmod 644 "$ZONE_FILE_PATH.signed"

# Check RNDC configuration
if [[ ! -f "/etc/bind/rndc.conf" && ! -f "/etc/bind/rndc.key" ]]; then
    echo "Error: RNDC configuration missing (/etc/bind/rndc.conf or /etc/bind/rndc.key not found)."
    echo "Run 'rndc-confgen -a' to generate RNDC configuration and try again."
    exit 1
fi

# Reload named service
rndc reload || { echo "Failed to reload named service"; exit 1; }

echo "DNSSEC setup completed for $DOMAIN."