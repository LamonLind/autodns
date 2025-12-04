#!/bin/bash

# Colors for styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Installation directory
INSTALL_DIR="/opt/dnstt"
CONFIG_FILE="/etc/dnstt/config"
MENU_CMD="/usr/local/bin/dnstt"

# Display banner
echo -e "${CYAN}"
echo "╔═══════════════════════════════════════╗"
echo "║       DNSTT Server Installer          ║"
echo "║      Automated DNS Tunnel Setup       ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Please run as root (use sudo)${NC}"
    exit 1
fi

# Install dependencies
echo -e "${YELLOW}[*] Installing dependencies...${NC}"
apt-get update -qq
apt-get install -y git screen iptables iptables-persistent wget > /dev/null 2>&1

# Install golang using direct download
echo -e "${YELLOW}[*] Installing golang...${NC}"
GO_V="1.25.5"
wget -q https://dl.google.com/go/go${GO_V}.linux-amd64.tar.gz
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to download golang${NC}"
    exit 1
fi

sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go${GO_V}.linux-amd64.tar.gz
rm go${GO_V}.linux-amd64.tar.gz

# Add Go to PATH in ~/.profile if not already present
if ! grep -q "/usr/local/go/bin" ~/.profile 2>/dev/null; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
fi

# Export PATH for current session
export PATH=$PATH:/usr/local/go/bin

echo -e "${GREEN}Go ${GO_V} Installed.${NC}"
echo -e "${YELLOW}Note: Restart your terminal or run 'source ~/.profile' to apply changes.${NC}"

# Verify installation
if command -v /usr/local/go/bin/go > /dev/null 2>&1; then
    GO_VERSION=$(/usr/local/go/bin/go version)
    echo -e "${GREEN}✓ ${GO_VERSION}${NC}"
else
    echo -e "${RED}Error: Go installation verification failed${NC}"
    exit 1
fi

# Create directories
echo -e "${YELLOW}[*] Creating installation directories...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "/etc/dnstt"

# Clone and build dnstt
if [ ! -d "$INSTALL_DIR/dnstt" ]; then
    echo -e "${YELLOW}[*] Cloning dnstt from source...${NC}"
    cd "$INSTALL_DIR"
    git clone https://www.bamsoftware.com/git/dnstt.git > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to clone dnstt repository${NC}"
        exit 1
    fi
fi

# Build dnstt-server
echo -e "${YELLOW}[*] Building dnstt-server...${NC}"
cd "$INSTALL_DIR/dnstt/dnstt-server"
/usr/local/go/bin/go build > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to build dnstt-server${NC}"
    exit 1
fi

# Generate server keys
echo -e "${YELLOW}[*] Generating server keys...${NC}"
./dnstt-server -gen-key -privkey-file "$INSTALL_DIR/server.key" -pubkey-file "$INSTALL_DIR/server.pub" > /dev/null 2>&1

# Read the public key
PUBKEY=$(cat "$INSTALL_DIR/server.pub")
echo -e "${GREEN}✓ Public key generated: $PUBKEY${NC}"

# Prompt for nameserver
echo ""
echo -e "${CYAN}Enter name server (e.g., ns.example.com):${NC}"
read -p "> " NAMESERVER

if [ -z "$NAMESERVER" ]; then
    echo -e "${RED}Error: Nameserver cannot be empty${NC}"
    exit 1
fi

# Default port
DEFAULT_PORT=22
PORT=$DEFAULT_PORT

# Save configuration
echo -e "${YELLOW}[*] Saving configuration...${NC}"
cat > "$CONFIG_FILE" <<EOF
# DNSTT Configuration
NAMESERVER=$NAMESERVER
PORT=$PORT
INSTALL_DIR=$INSTALL_DIR
PUBKEY=$PUBKEY
EOF

# Set up iptables rules
echo -e "${YELLOW}[*] Setting up iptables rules...${NC}"

# Detect primary network interface
PRIMARY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$PRIMARY_IFACE" ]; then
    PRIMARY_IFACE="eth0"  # Fallback to eth0 if detection fails
fi

iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -i "$PRIMARY_IFACE" -p udp --dport 53 -j REDIRECT --to-ports 5300

# Save iptables rules to persist on reboot
echo -e "${YELLOW}[*] Saving iptables rules for persistence...${NC}"
if command -v netfilter-persistent > /dev/null; then
    netfilter-persistent save > /dev/null 2>&1
elif command -v iptables-save > /dev/null; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    # Ensure rules are restored on boot
    if [ ! -f /etc/network/if-pre-up.d/iptables ]; then
        mkdir -p /etc/network/if-pre-up.d
        cat > /etc/network/if-pre-up.d/iptables <<'IPTABLESEOF'
#!/bin/sh
/sbin/iptables-restore < /etc/iptables/rules.v4
IPTABLESEOF
        chmod +x /etc/network/if-pre-up.d/iptables
    fi
fi

# Create systemd service for auto-start on reboot
echo -e "${YELLOW}[*] Creating systemd service for auto-start...${NC}"
cat > /etc/systemd/system/dnstt.service <<SERVICEEOF
[Unit]
Description=DNSTT DNS Tunnel Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/dnstt/dnstt-server
EnvironmentFile=$CONFIG_FILE
ExecStart=/usr/bin/screen -DmS dnstt $INSTALL_DIR/dnstt/dnstt-server/dnstt-server -udp :5300 -privkey-file $INSTALL_DIR/server.key \${NAMESERVER} 127.0.0.1:\${PORT}
ExecStop=/usr/bin/screen -S dnstt -X quit
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Enable systemd service
systemctl daemon-reload
systemctl enable dnstt.service > /dev/null 2>&1

# Create menu command
echo -e "${YELLOW}[*] Installing dnstt menu command...${NC}"
cat > "$MENU_CMD" <<'MENUEOF'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CONFIG_FILE="/etc/dnstt/config"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Configuration file not found${NC}"
    exit 1
fi

source "$CONFIG_FILE"

# Function to check if dnstt is running
check_running() {
    systemctl is-active --quiet dnstt.service
    return $?
}

# Function to start dnstt
start_dnstt() {
    if check_running; then
        echo -e "${YELLOW}DNSTT is already running${NC}"
        return
    fi
    
    systemctl start dnstt.service
    sleep 1
    
    if check_running; then
        echo -e "${GREEN}✓ DNSTT started successfully${NC}"
    else
        echo -e "${RED}✗ Failed to start DNSTT${NC}"
    fi
}

# Function to stop dnstt
stop_dnstt() {
    if ! check_running; then
        echo -e "${YELLOW}DNSTT is not running${NC}"
        return
    fi
    
    systemctl stop dnstt.service
    echo -e "${GREEN}✓ DNSTT stopped${NC}"
}

# Function to restart dnstt
restart_dnstt() {
    echo -e "${YELLOW}Restarting DNSTT...${NC}"
    systemctl restart dnstt.service
    sleep 1
    
    if check_running; then
        echo -e "${GREEN}✓ DNSTT restarted successfully${NC}"
    else
        echo -e "${RED}✗ Failed to restart DNSTT${NC}"
    fi
}

# Function to change port
change_port() {
    echo ""
    echo -e "${CYAN}Select port:${NC}"
    echo -e "  ${YELLOW}1.${NC} Port 22 (SSH)"
    echo -e "  ${YELLOW}2.${NC} Port 80 (HTTP)"
    echo -e "  ${YELLOW}3.${NC} Port 443 (HTTPS)"
    echo ""
    read -p "Enter choice [1-3]: " choice
    
    case $choice in
        1) NEW_PORT=22 ;;
        2) NEW_PORT=80 ;;
        3) NEW_PORT=443 ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            return
            ;;
    esac
    
    # Update config file
    sed -i "s/PORT=.*/PORT=$NEW_PORT/" "$CONFIG_FILE"
    PORT=$NEW_PORT
    
    echo -e "${GREEN}✓ Port changed to $NEW_PORT${NC}"
    
    # Reload systemd and restart service
    systemctl daemon-reload
    restart_dnstt
}

# Display menu
while true; do
    clear
    
    # Get running status
    if check_running; then
        STATUS="${GREEN}● RUNNING${NC}"
    else
        STATUS="${RED}● STOPPED${NC}"
    fi
    
    # Display header
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    DNSTT SERVER MANAGEMENT                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Display configuration
    echo -e "${BOLD}${PURPLE}Configuration:${NC}"
    echo -e "${CYAN}┌────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${YELLOW}Public Key  :${NC} ${GREEN}$PUBKEY${NC}"
    echo -e "${CYAN}│${NC} ${YELLOW}Name Server :${NC} ${GREEN}$NAMESERVER${NC}"
    echo -e "${CYAN}│${NC} ${YELLOW}DNSTT Port  :${NC} ${GREEN}$PORT${NC}"
    echo -e "${CYAN}│${NC} ${YELLOW}Status      :${NC} $STATUS"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    # Display menu options
    echo -e "${BOLD}${BLUE}Menu Options:${NC}"
    echo -e "  ${YELLOW}1.${NC} Restart DNSTT"
    echo -e "  ${YELLOW}2.${NC} Stop DNSTT"
    echo -e "  ${YELLOW}3.${NC} Change Port (22/80/443)"
    echo -e "  ${YELLOW}0.${NC} Exit"
    echo ""
    
    read -p "Enter your choice: " choice
    
    case $choice in
        1)
            restart_dnstt
            read -p "Press Enter to continue..."
            ;;
        2)
            stop_dnstt
            read -p "Press Enter to continue..."
            ;;
        3)
            change_port
            read -p "Press Enter to continue..."
            ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            read -p "Press Enter to continue..."
            ;;
    esac
done
MENUEOF

chmod +x "$MENU_CMD"

# Start dnstt service
echo -e "${YELLOW}[*] Starting DNSTT server...${NC}"
systemctl start dnstt.service

sleep 2

# Check if running
if systemctl is-active --quiet dnstt.service; then
    echo -e "${GREEN}✓ DNSTT server started successfully${NC}"
    echo -e "${GREEN}✓ DNSTT will automatically start on reboot${NC}"
else
    echo -e "${RED}✗ Failed to start DNSTT server${NC}"
fi

# Display completion message
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Installation Complete!            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Configuration saved to: ${YELLOW}$CONFIG_FILE${NC}"
echo -e "${CYAN}Public Key: ${GREEN}$PUBKEY${NC}"
echo -e "${CYAN}Name Server: ${GREEN}$NAMESERVER${NC}"
echo -e "${CYAN}Port: ${GREEN}$PORT${NC}"
echo ""
echo -e "${YELLOW}To manage DNSTT, run: ${BOLD}dnstt${NC}"
echo ""
