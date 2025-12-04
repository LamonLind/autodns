# AutoDNS - Automated DNSTT Server Setup

An automated installation and management system for DNSTT (DNS Tunnel) server.

## Features

- 🚀 One-command installation
- 🔐 Automatic key generation
- ⚙️ Automatic iptables configuration
- 🔄 Auto-restart on system reboot
- 📋 Interactive menu for server management
- 🎨 Stylish colored interface
- 🔄 Easy port switching (22/80/443)

## Installation

Run the installation script as root:

```bash
sudo ./install.sh
```

During installation, you will be prompted to enter your nameserver (e.g., `ns.example.com`).

The installer will:
1. Install required dependencies (git, golang, screen, iptables)
2. Clone and build dnstt from source
3. Generate server keys (private and public)
4. Configure iptables rules automatically (with persistence on reboot)
5. Create a systemd service for auto-start on reboot
6. Start the DNSTT server
7. Install the `dnstt` management command

## Usage

After installation, use the `dnstt` command to manage your server:

```bash
dnstt
```

This will open an interactive menu with the following options:

### Menu Options

1. **Restart** - Restart the DNSTT server
2. **Stop** - Stop the DNSTT server
3. **Change Port** - Switch between ports 22, 80, or 443 (automatically restarts)
0. **Exit** - Exit the menu

### Menu Display

The menu displays your current configuration:
- **Public Key** - Your server's public key
- **Name Server** - The configured nameserver
- **DNSTT Port** - The current forwarding port (22, 80, or 443)
- **Status** - Server running status (● RUNNING / ● STOPPED)

## Configuration

Configuration is stored in `/etc/dnstt/config`:
- Nameserver
- Port
- Installation directory
- Public key

## Technical Details

### Directories
- Installation: `/opt/dnstt`
- Configuration: `/etc/dnstt/config`
- Keys: `/opt/dnstt/server.key` and `/opt/dnstt/server.pub`

### Network Configuration
- UDP Port 5300: DNSTT server listening port
- Port 53: Redirected to 5300 via iptables NAT
- Configurable forward port: 22, 80, or 443 (local services)

### iptables Rules
```bash
# Accept UDP on port 5300
iptables -I INPUT -p udp --dport 5300 -j ACCEPT

# Redirect DNS traffic (port 53) to DNSTT (port 5300)
iptables -t nat -I PREROUTING -i eth0 -p udp --dport 53 -j REDIRECT --to-ports 5300
```

Rules are automatically saved and restored on reboot using `iptables-persistent`.

### Systemd Service

The installer creates a systemd service (`dnstt.service`) that:
- Automatically starts DNSTT on system boot
- Restarts the service if it crashes
- Can be managed using standard systemd commands:
  ```bash
  systemctl status dnstt    # Check status
  systemctl start dnstt     # Start service
  systemctl stop dnstt      # Stop service
  systemctl restart dnstt   # Restart service
  ```

The `dnstt` menu command provides a user-friendly interface for these operations.

## Requirements

- Linux system with root access
- Internet connection for downloading dnstt
- Go compiler (installed automatically)
- iptables support

## License

This is an automated installer for DNSTT. For DNSTT license and information, see:
https://www.bamsoftware.com/git/dnstt.git