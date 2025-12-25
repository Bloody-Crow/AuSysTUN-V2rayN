# v2rayN Automatic System Tunnel

This project provides a background automation tool for v2rayN users on Linux (specifically Fedora) and macOS. It ensures that when TUN mode is activated in the v2rayN client, the entire operating system is correctly routed through the tunnel without DNS leaks or routing conflicts.

## What this script does

On many Linux and macOS distributions, enabling TUN mode in a GUI client does not automatically update the system routing table or secure the DNS. This results in "Split Tunneling" where some apps bypass the VPN, or "DNS Leaks" where your ISP can still monitor your activity.

This script installs a background daemon that:
1. Automatically detects your v2rayN configuration file location.
2. Monitors the active server IP.
3. Updates the system default route to force all traffic through the tunnel.
4. Implements a loop-breaker to ensure the VPN connection itself remains stable.
5. Locks system DNS settings to 1.1.1.1 within the tunnel to prevent leaks.
6. Adjusts MTU and MSS settings to prevent connection drops in restricted network environments.

## Safety and Profile

This tool is designed to be low-profile and secure:
- Resource Usage: The daemon sleeps for 5-second intervals, using negligible CPU and less than 5MB of RAM.
- Local Only: No data is collected or sent to any external server. All logic happens locally on your machine.
- Non-Intrusive: It does not modify your v2rayN installation files. It only reads the configuration to apply system-level networking rules.

## Installation

To install the tool, open your terminal and run the following commands:

git clone https://github.com/YourUsername/v2rayN-Automatic-System-Tunnel.git
cd v2rayN-Automatic-System-Tunnel
chmod +x v2rayn-autosystemtunnel-linux-macos.sh
sudo ./v2rayn-autosystemtunnel-linux-macos.sh

## Requirements

- Linux: Fedora 43 or similar (uses systemd and resolvectl).
- macOS: Homebrew must be installed (for jq).
- v2rayN: The client must be installed and run at least once so a configuration file exists.

## Uninstallation

To remove the tool and revert all system changes:

Linux:
sudo systemctl stop vpn-auto
sudo systemctl disable vpn-auto
sudo rm /etc/systemd/system/vpn-auto.service
sudo rm /usr/local/bin/vpn-smart-daemon.sh
sudo rm /etc/sudoers.d/vpn-fixer

macOS:
sudo launchctl unload -w /Library/LaunchDaemons/com.vpn.auto.plist
sudo rm /Library/LaunchDaemons/com.vpn.auto.plist
sudo rm /usr/local/bin/vpn-smart-daemon.sh
