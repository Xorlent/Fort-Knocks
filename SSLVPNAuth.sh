#!/bin/bash

# Configuration file path
CONFIG_FILE="$HOME/.vpn_config"
KEYCHAIN_NAME="VPNAuth"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to get value from keychain
get_from_keychain() {
    local key=$1
    security find-generic-password -a "$USER" -s "${KEYCHAIN_NAME}_${key}" -w 2>/dev/null
}

# Function to save value to keychain
save_to_keychain() {
    local key=$1
    local value=$2
    security add-generic-password -a "$USER" -s "${KEYCHAIN_NAME}_${key}" -w "$value" 2>/dev/null
}

# Function to get stored credentials
get_stored_credentials() {
    if [ -f "$CONFIG_FILE" ]; then
        username=$(get_from_keychain "username")
        vpn_auth=$(get_from_keychain "vpnauth")
        base_uri=$(get_from_keychain "uri")
        
        if [ -n "$username" ] && [ -n "$vpn_auth" ] && [ -n "$base_uri" ]; then
            return 0
        fi
    fi
    return 1
}

# Function to save credentials
save_credentials() {
    local username=$1
    local vpn_auth=$2
    local base_uri=$3
    
    save_to_keychain "username" "$username"
    save_to_keychain "vpnauth" "$vpn_auth"
    save_to_keychain "uri" "$base_uri"
    
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
            echo -e "${YELLOW}Rate limit exceeded. Try again in 8 hours.${NC}"
            ;;
        404)
            echo -e "${RED}Invalid username hash or key not found.${NC}"
            ;;
        500)
            echo -e "${RED}Server error occurred. Details:${NC}"
            echo -e "${RED}URI: $uri${NC}"
            echo -e "${RED}Response: $content${NC}"
            ;;
        *)
            echo -e "${RED}Error occurred: HTTP $http_code${NC}"
            echo -e "${RED}Response: $content${NC}"
            ;;
    esac
}

# Main script
if get_stored_credentials; then
    read -p "Found stored credentials. Use them? (Y/N): " use_stored
    if [ "${use_stored:0:1}" = "Y" ] || [ "${use_stored:0:1}" = "y" ]; then
        username=$(get_from_keychain "username")
        vpn_auth=$(get_from_keychain "vpnauth")
        base_uri=$(get_from_keychain "uri")
    fi
fi

if [ -z "$username" ] || [ -z "$vpn_auth" ] || [ -z "$base_uri" ]; then
    read -p "Enter username: " username
    read -p "Enter pre-shared key: " vpn_auth
    read -p "Enter base URL (e.g., https://vpn-auth.organization.workers.dev): " base_uri
    
    read -p "Save credentials for future use? (Y/N): " save_creds
    if [ "${save_creds:0:1}" = "Y" ] || [ "${save_creds:0:1}" = "y" ]; then
        save_credentials "$username" "$vpn_auth" "$base_uri"
    fi
fi

# Create hash and make request
hash=$(create_hash "$username")
uri="${base_uri}/${hash}"

make_request "$uri" "$vpn_auth"
