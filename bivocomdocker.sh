#!/bin/bash

# bivcomdocker.sh - BIVCOM Docker Installation Script
# Automatically installs Docker, Node-RED, Restreamer, and Tailscale
# GitHub: https://github.com/iyon09/bivcomdocker

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BASE_DIR="$HOME/bivcom-docker"
LOG_FILE="$BASE_DIR/installation.log"

# Print functions
print_status() { echo -e "${GREEN}[INFO]${NC} $1"; echo "$(date): [INFO] $1" >> "$LOG_FILE"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; echo "$(date): [WARN] $1" >> "$LOG_FILE"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; echo "$(date): [ERROR] $1" >> "$LOG_FILE"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; echo "$(date): [STEP] $1" >> "$LOG_FILE"; }

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root. Run as a regular user with sudo privileges."
    exit 1
fi

# Create base directory and log file
mkdir -p "$BASE_DIR"
touch "$LOG_FILE"

print_step "=== BIVCOM DOCKER INSTALLATION STARTED ==="
print_status "Installation log: $LOG_FILE"
print_status "Installation directory: $BASE_DIR"

# Install required packages
install_packages() {
    print_step "Installing required packages (curl, nano, git)..."
    sudo apt update >> "$LOG_FILE" 2>&1
    sudo apt install -y curl nano git >> "$LOG_FILE" 2>&1
    print_status "Packages installed successfully"
}

# Install Docker
install_docker() {
    print_step "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        print_status "Docker is already installed"
        return
    fi

    sudo apt update >> "$LOG_FILE" 2>&1
    sudo apt install -y ca-certificates curl gnupg lsb-release >> "$LOG_FILE" 2>&1
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$LOG_FILE" 2>&1
    
    # Set up repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt update >> "$LOG_FILE" 2>&1
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >> "$LOG_FILE" 2>&1
    
    # Add user to docker group
    sudo usermod -aG docker $USER >> "$LOG_FILE" 2>&1
    print_status "Docker installed successfully"
}

# Create directory structure
create_directories() {
    print_step "Creating directory structure..."
    mkdir -p "$BASE_DIR/nodered" "$BASE_DIR/restreamer" "$BASE_DIR/tailscale"
    print_status "Directories created in: $BASE_DIR"
}

# Create docker-compose files
create_docker_compose_files() {
    print_step "Creating docker-compose files..."
    
    # Node-RED
    cat > "$BASE_DIR/nodered/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  nodered:
    image: nodered/node-red:latest
    container_name: bivcom-nodered
    restart: unless-stopped
    ports:
      - "1880:1880"
    volumes:
      - ./data:/data
    environment:
      - TZ=UTC
    networks:
      - bivcom-network

networks:
  bivcom-network:
    driver: bridge
EOF

    # Restreamer
    cat > "$BASE_DIR/restreamer/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  restreamer:
    image: datarhei/restreamer:latest
    container_name: bivcom-restreamer
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./data:/restreamer/data
    environment:
      - RS_USERNAME=admin
      - RS_PASSWORD=L@ranet2025
      - RS_STORAGE_DIR=/restreamer/data
    networks:
      - bivcom-network

networks:
  bivcom-network:
    driver: bridge
EOF

    # Tailscale
    cat > "$BASE_DIR/tailscale/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: bivcom-tailscale
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - ./var/lib:/var/lib
      - ./state:/state
      - /dev/net/tun:/dev/net/tun
    environment:
      - TS_STATE_DIR=/state
      - TS_USERSPACE=false
      - TS_ACCEPT_DNS=true
      - TS_AUTHKEY=your-auth-key-here
    networks:
      - bivcom-network

networks:
  bivcom-network:
    driver: bridge
EOF

    print_status "Docker compose files created"
}

# Set permissions
set_permissions() {
    print_step "Setting permissions..."
    sudo chown -R $USER:$USER "$BASE_DIR" >> "$LOG_FILE" 2>&1
    chmod -R 755 "$BASE_DIR" >> "$LOG_FILE" 2>&1
    print_status "Permissions set successfully"
}

# Start services
start_services() {
    print_step "Starting Docker services..."
    
    # Start Docker service
    sudo systemctl start docker >> "$LOG_FILE" 2>&1
    sudo systemctl enable docker >> "$LOG_FILE" 2>&1
    
    # Create data directories
    mkdir -p "$BASE_DIR/nodered/data" "$BASE_DIR/restreamer/data" "$BASE_DIR/tailscale/var/lib" "$BASE_DIR/tailscale/state"
    
    # Start services
    print_status "Starting Node-RED..."
    cd "$BASE_DIR/nodered" && docker compose up -d >> "$LOG_FILE" 2>&1
    
    print_status "Starting Restreamer..."
    cd "$BASE_DIR/restreamer" && docker compose up -d >> "$LOG_FILE" 2>&1
    
    print_status "Starting Tailscale..."
    cd "$BASE_DIR/tailscale" && docker compose up -d >> "$LOG_FILE" 2>&1
    
    sleep 5
    print_status "Services started successfully"
}

# Display final information
show_final_info() {
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    echo ""
    print_step "=== INSTALLATION COMPLETE ==="
    echo ""
    print_status "Services are now running:"
    print_status "  - Node-RED:     http://$IP_ADDRESS:1880"
    print_status "  - Restreamer:   http://$IP_ADDRESS:8080"
    print_status "     Username: admin"
    print_status "     Password: bivcom2024"
    echo ""
    print_status "Tailscale setup:"
    print_status "  1. Get auth key from: https://login.tailscale.com/admin/settings/keys"
    print_status "  2. Edit: $BASE_DIR/tailscale/docker-compose.yml"
    print_status "  3. Replace: TS_AUTHKEY=your-auth-key-here with your actual key"
    print_status "  4. Restart: cd $BASE_DIR/tailscale && docker compose up -d"
    echo ""
    print_warning "IMPORTANT: Log out and back in or run: newgrp docker"
    print_warning "           This is required for Docker permissions to work properly"
    echo ""
    print_status "Installation log: $LOG_FILE"
    print_status "All files are in: $BASE_DIR"
    echo ""
}

# Main execution
main() {
    print_step "Starting installation process..."
    install_packages
    install_docker
    create_directories
    create_docker_compose_files
    set_permissions
    start_services
    show_final_info
    print_step "=== BIVCOM DOCKER INSTALLATION COMPLETED SUCCESSFULLY ==="
}

# Run main
main "$@"
