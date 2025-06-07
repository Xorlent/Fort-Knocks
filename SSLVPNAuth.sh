#!/bin/bash

# Configuration file path
CONFIG_FILE="$HOME/.vpn_config"
KEYCHAIN_NAME="VPNAuth"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default salt value
SALT="default-salt-value"

# Function to get value from keychain
get_keychain_value() {
    local key="$1"
    security find-generic-password -a "$USER" -s "$key" -w 2>/dev/null
}

# Function to save value to keychain
save_to_keychain() {
    local key="$1"
    local value="$2"
    security add-generic-password -a "$USER" -s "$key" -w "$value" 2>/dev/null
}

# Function to prompt for credentials
prompt_for_credentials() {
    # Prompt for username
    read -p "Enter username: " USERNAME
    while [ -z "$USERNAME" ]; do
        echo "Error: Username is required"
        read -p "Enter username: " USERNAME
    done

    # Prompt for VPNAuth key
    read -sp "Enter pre-shared key: " VPNAUTH
    echo
    while [ -z "$VPNAUTH" ]; do
        echo "Error: Pre-shared key is required"
        read -sp "Enter pre-shared key: " VPNAUTH
        echo
    done

    # Prompt for URI
    read -p "Enter VPN URL (e.g., https://vpn-auth.organization.workers.dev): " URI
    while [ -z "$URI" ]; do
        echo "Error: VPN URL is required"
        read -p "Enter VPN URL: " URI
    done
}

# Function to save credentials
save_credentials() {
    local username=$1
    local vpn_auth=$2
    local base_uri=$3
    
    save_to_keychain "vpn_username" "$username"
    save_to_keychain "vpn_auth" "$vpn_auth"
    save_to_keychain "vpn_uri" "$base_uri"
    
    touch "$CONFIG_FILE"
    echo -e "${GREEN}Credentials saved securely to Keychain${NC}"
}

# Function to create SHA256 hash
create_hash() {
    local input=$1
    printf "%s" "$input" | shasum -a 256 | cut -d' ' -f1
}

# Function to make HTTP request
make_request() {
    local uri=$1
    local vpn_auth=$2
    
    response=$(curl -4 -s -w "\n%{http_code}" "$uri" -H "VPNAuth: $vpn_auth")
    http_code=$(echo "$response" | tail -n1)
    content=$(echo "$response" | sed '$d')
    
    case $http_code in
        200)
            echo -e "${GREEN}Success! Please wait up to 2 minutes before connecting to the SSLVPN. Your session will be valid for 8 hours.${NC}"
            ;;
        401)
            echo -e "${RED}Authentication failed. Invalid pre-shared key.${NC}"
            ;;
        429)
            echo -e "${YELLOW}Rate limit exceeded. Try again later.${NC}"
            ;;
        404)
            echo -e "${RED}Invalid username hash or key not found.${NC}"
            ;;
        *)
            echo -e "${RED}Error occurred: HTTP $http_code${NC}"
            echo -e "${RED}Response: $content${NC}"
            ;;
    esac
}

# Check for saved credentials
SAVED_USERNAME=$(get_keychain_value "vpn_username")
SAVED_VPNAUTH=$(get_keychain_value "vpn_auth")
SAVED_URI=$(get_keychain_value "vpn_uri")

if [ -n "$SAVED_USERNAME" ] && [ -n "$SAVED_VPNAUTH" ] && [ -n "$SAVED_URI" ]; then
    read -p "Use saved credentials? (y/n): " USE_SAVED
    if [ "$USE_SAVED" = "y" ]; then
        USERNAME="$SAVED_USERNAME"
        VPNAUTH="$SAVED_VPNAUTH"
        URI="$SAVED_URI"
    else
        prompt_for_credentials
        read -p "Save these credentials? (y/n): " SAVE_CREDS
        if [ "$SAVE_CREDS" = "y" ]; then
            save_credentials "$USERNAME" "$VPNAUTH" "$URI"
        fi
    fi
else
    prompt_for_credentials
    read -p "Save these credentials? (y/n): " SAVE_CREDS
    if [ "$SAVE_CREDS" = "y" ]; then
        save_credentials "$USERNAME" "$VPNAUTH" "$URI"
    fi
fi

# Create salted input
SALTED_INPUT="${USERNAME}:${SALT}"

# Calculate SHA-256 hash using UTF-8 encoding
HASH=$(printf '%s' "$SALTED_INPUT" | openssl dgst -sha256 -hex | cut -d' ' -f2)

# Construct the URL
URL="${URI%/}/$HASH"

# Make the request
make_request "$URL" "$VPNAUTH"
