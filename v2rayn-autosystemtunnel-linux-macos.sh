#!/bin/bash

###############################################################################
# Script Name: v2rayn-autosystemtunnel-linux-macos.sh
# Repository: v2rayN Automatic System Tunnel
# Author: The Bloody-Crow
#
# Description:
# This script automates system-wide tunneling for v2rayN users on Linux (Fedora)
# and macOS. It functions by monitoring the v2rayN configuration file and
# dynamically updating the system routing table and DNS settings.
#
# Technical Overview:
# 1. OS Detection: Identifies if the system is Linux or macOS.
# 2. Config Discovery: Performs a deep search to locate the v2rayN config.json.
# 3. Smart Daemon: Installs a background process that:
#    - Detects server changes in v2rayN.
#    - Resolves the server IP and creates a bypass route (Loop-Breaker).
#    - Forces the system default route to the TUN interface.
#    - Locks DNS settings to prevent leaks.
#    - Applies MTU and MSS clamping for connection stability.
###############################################################################

# --- UNIVERSAL SYSTEM DETECTION ---
OS_TYPE="$(uname)"
USERNAME=$(logname || whoami)
HOME_DIR=$(eval echo ~$USERNAME)
DAEMON_PATH="/usr/local/bin/vpn-smart-daemon.sh"

# Installation requires root privileges to modify network stacks and services.
if [[ $EUID -ne 0 ]]; then
   echo "Error: This installer must be run with sudo."
   exit 1
fi

echo "Initiating v2rayN Automatic System Tunnel Installation for $OS_TYPE"

# --- CONFIGURATION DISCOVERY ---
# This function searches for a config.json file located within a 'v2rayN' folder.
# It prioritizes the user's Home directory for speed, then searches system paths.
find_config() {
    local paths_to_search=("$HOME_DIR" "/etc" "/opt" "/usr/local")
    for search_path in "${paths_to_search[@]}"; do
        if [ -d "$search_path" ]; then
            result=$(find "$search_path" -maxdepth 6 -name "config.json" -path "*/v2rayN/*" 2>/dev/null | head -n 1)
            if [ ! -z "$result" ]; then
                echo "$result"
                return 0
            fi
        fi
    done
    return 1
}

FOUND_CONFIG=$(find_config)

if [ -z "$FOUND_CONFIG" ]; then
    echo "Error: Could not locate v2rayN/config.json automatically."
    echo "Please ensure v2rayN is installed and has been launched at least once."
    exit 1
else
    echo "Configuration located at: $FOUND_CONFIG"
fi

# --- DEPENDENCY MANAGEMENT ---
echo "Checking and installing dependencies..."
if [[ "$OS_TYPE" == "Linux" ]]; then
    dnf install jq bind-utils -y -q
elif [[ "$OS_TYPE" == "Darwin" ]]; then
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required. Please install via Homebrew: brew install jq"
        exit 1
    fi
fi

# --- DAEMON GENERATION ---
# This section writes the background monitor script. The path found during 
# installation is hardcoded here to minimize CPU usage during polling.
echo "Generating background daemon..."
cat << EOF > $DAEMON_PATH
#!/bin/bash
OS_TYPE="\$(uname)"
V2RAY_CONFIG="$FOUND_CONFIG"
LAST_SERVER_IP=""
TUN_DEV="singbox_tun"

# Linux Routing Logic: Uses ip-route and systemd-resolved.
apply_linux() {
    WIFI_IF=\$(ip route show default | awk '/default/ {print \$5}' | head -n1)
    GW=\$(ip route show default | awk '/default/ {print \$3}' | head -n1)
    [ ! -z "\$1" ] && ip route del "\$1" 2>/dev/null
    ip route add "\$2" via "\$GW" dev "\$WIFI_IF" 2>/dev/null
    ip route add default dev "\$TUN_DEV" metric 1 2>/dev/null || ip route replace default dev "\$TUN_DEV" metric 1
    resolvectl dns "\$TUN_DEV" 1.1.1.1 2>/dev/null
    resolvectl domain "\$TUN_DEV" ~. 2>/dev/null
    resolvectl default-route "\$TUN_DEV" yes 2>/dev/null
    ip link set dev "\$TUN_DEV" mtu 1280 2>/dev/null
    nft add table ip filter 2>/dev/null
    nft add chain ip filter forward '{ type filter hook forward priority 0; policy accept; }' 2>/dev/null
    nft add rule ip filter forward tcp flags syn tcp option maxseg size set 1200 2>/dev/null
}

# macOS Routing Logic: Uses BSD route and networksetup.
apply_macos() {
    GW=\$(netstat -rn | grep default | awk '{print \$2}' | head -n1)
    WIFI_IF=\$(route get 8.8.8.8 | grep interface | awk '{print \$2}')
    [ ! -z "\$1" ] && route delete "\$1" 2>/dev/null
    route add "\$2" "\$GW" 2>/dev/null
    route add default -interface "\$TUN_DEV" 2>/dev/null
    SERV=\$(networksetup -listallnetworkservices | grep -Ei "Wi-Fi|Ethernet" | head -n1)
    networksetup -setdnsservers "\$SERV" 1.1.1.1 8.8.8.8 2>/dev/null
    ifconfig "\$TUN_DEV" mtu 1280 2>/dev/null
}

# Monitoring Loop: Checks for server changes every 5 seconds.
while true; do
    if [ -f "\$V2RAY_CONFIG" ]; then
        RAW_ADDR=\$(jq -r '.outbounds[] | select(.protocol != "dns" and .tag != "direct") | .settings.vnext[0].address // .settings.servers[0].address // .server' "\$V2RAY_CONFIG" | head -n1)
        if [ ! -z "\$RAW_ADDR" ] && [ "\$RAW_ADDR" != "null" ]; then
            [[ "\$RAW_ADDR" =~ ^[0-9.]+$ ]] && CURRENT_IP="\$RAW_ADDR" || CURRENT_IP=\$(dig +short "\$RAW_ADDR" | tail -n1)
            
            if [ "\$CURRENT_IP" != "\$LAST_SERVER_IP" ] && [ ! -z "\$CURRENT_IP" ]; then
                if [[ "\$OS_TYPE" == "Linux" ]]; then
                    apply_linux "\$LAST_SERVER_IP" "\$CURRENT_IP"
                else
                    apply_macos "\$LAST_SERVER_IP" "\$CURRENT_IP"
                fi
                LAST_SERVER_IP="\$CURRENT_IP"
            fi
        fi
    fi
    sleep 5
done
EOF

chmod +x $DAEMON_PATH

# --- SERVICE REGISTRATION ---
if [[ "$OS_TYPE" == "Linux" ]]; then
    echo "Configuring Linux systemd service..."
    cat << EOF > /etc/systemd/system/vpn-auto.service
[Unit]
Description=v2rayN Automatic System Tunnel Daemon
After=network.target

[Service]
ExecStart=$DAEMON_PATH
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    # Grants the daemon permission to modify network settings without password prompts.
    SUDOERS_FILE="/etc/sudoers.d/vpn-fixer"
    echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/sbin/ip, /usr/bin/resolvectl, /usr/sbin/nft, /usr/sbin/ifconfig" > $SUDOERS_FILE
    chmod 440 $SUDOERS_FILE
    
    # Disable Fedora connectivity-check to prevent VPN instability.
    echo -e "[connectivity]\nenabled=false" > /etc/NetworkManager/conf.d/20-connectivity-check.conf
    systemctl restart NetworkManager

    systemctl daemon-reload
    systemctl enable vpn-auto && systemctl start vpn-auto

elif [[ "$OS_TYPE" == "Darwin" ]]; then
    echo "Configuring macOS LaunchDaemon..."
    PLIST="/Library/LaunchDaemons/com.vpn.auto.plist"
    cat << EOF > $PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vpn.auto</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DAEMON_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
    launchctl load -w $PLIST
fi

echo "Installation complete. The background daemon is active."
