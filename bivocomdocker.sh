#!/bin/bash

# install_all.sh
# Script to install curl, nano, docker, node-red, restreamer, and tailscale in docker

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Base directory
BASE_DIR="$HOME/docker-apps"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root. Run as a regular user with sudo privileges."
    exit 1
fi

# Function to install packages using apt (Debian/Ubuntu)
install_packages() {
    print_status "Installing curl and nano..."
    
    sudo apt update
    sudo apt install -y curl nano
}

# Function to install Docker
install_docker() {
    print_status "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        print_status "Docker is already installed"
        return
    fi

    # Install Docker using official Docker repository
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Add user to docker group and set proper permissions
    sudo usermod -aG docker $USER
    
    print_status "Docker installed. Setting up permissions..."
}

# Function to create directory structure
create_directories() {
    print_status "Creating directory structure in $BASE_DIR..."
    
    # Create base directory
    mkdir -p "$BASE_DIR"
    
    # Create separate directories for each service
    mkdir -p "$BASE_DIR/nodered"
    mkdir -p "$BASE_DIR/restreamer"
    mkdir -p "$BASE_DIR/tailscale"
    
    print_status "Directories created:"
    echo "  - Node-RED:    $BASE_DIR/nodered/"
    echo "  - Restreamer:  $BASE_DIR/restreamer/"
    echo "  - Tailscale:   $BASE_DIR/tailscale/"
}

# Function to create docker-compose.yml for each service
create_docker_compose_files() {
    print_status "Creating docker-compose.yml files for each service..."
    
    # Node-RED docker-compose
    cat > "$BASE_DIR/nodered/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  nodered:
    image: nodered/node-red:latest
    container_name: nodered
    restart: unless-stopped
    ports:
      - "1880:1880"
    volumes:
      - ./data:/data
    environment:
      - TZ=UTC
    networks:
      - nodered-network

networks:
  nodered-network:
    driver: bridge
EOF

    # Restreamer docker-compose
    cat > "$BASE_DIR/restreamer/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  restreamer:
    image: datarhei/restreamer:latest
    container_name: restreamer
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./data:/restreamer/data
    environment:
      - RS_USERNAME=admin
      - RS_PASSWORD=restreamer
    networks:
      - restreamer-network

networks:
  restreamer-network:
    driver: bridge
EOF

    # Tailscale docker-compose
    cat > "$BASE_DIR/tailscale/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
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
    networks:
      - tailscale-network

networks:
  tailscale-network:
    driver: bridge
EOF

    print_status "docker-compose.yml files created in each service directory"
}

# Function to set proper permissions
set_permissions() {
    print_status "Setting proper permissions for Docker directories..."
    
    # Set ownership to current user for all directories
    sudo chown -R $USER:$USER "$BASE_DIR"
    
    # Set proper permissions
    chmod -R 755 "$BASE_DIR"
    
    # Ensure Docker socket has proper permissions (if needed)
    if [ -S /var/run/docker.sock ]; then
        sudo chmod 666 /var/run/docker.sock || true
    fi
    
    print_status "Permissions set successfully"
}

# Function to start all services
start_services() {
    print_status "Starting all Docker services from their respective directories..."
    
    # Create data directories for each service
    mkdir -p "$BASE_DIR/nodered/data"
    mkdir -p "$BASE_DIR/restreamer/data"
    mkdir -p "$BASE_DIR/tailscale/var/lib"
    mkdir -p "$BASE_DIR/tailscale/state"
    
    # Start Node-RED
    print_status "Starting Node-RED..."
    cd "$BASE_DIR/nodered"
    docker compose up -d
    
    # Start Restreamer
    print_status "Starting Restreamer..."
    cd "$BASE_DIR/restreamer"
    docker compose up -d
    
    # Start Tailscale
    print_status "Starting Tailscale..."
    cd "$BASE_DIR/tailscale"
    docker compose up -d
    
    # Wait a moment for services to start
    sleep 5
    
    print_status "Checking service status..."
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Function to display final information
show_final_info() {
    echo ""
    print_status "=== INSTALLATION COMPLETE ==="
    echo ""
    print_status "Services installed and running in separate directories:"
    echo "  - Node-RED:     $BASE_DIR/nodered/"
    echo "  - Restreamer:   $BASE_DIR/restreamer/"
    echo "  - Tailscale:    $BASE_DIR/tailscale/"
    echo ""
    print_status "Access URLs:"
    echo "  - Node-RED:     http://localhost:1880"
    echo "  - Restreamer:   http://localhost:8080"
    echo "    Username: admin"
    echo "    Password: restreamer"
    echo ""
    print_status "Tailscale setup:"
    echo "  To complete Tailscale setup, run:"
    echo "  docker exec -it tailscale tailscale up"
    echo ""
    print_warning "IMPORTANT: You need to log out and back in for Docker permissions to work properly,"
    print_warning "or run: newgrp docker"
    echo ""
    print_status "Management commands:"
    echo "  View all containers:    docker ps"
    echo "  Stop Node-RED:         cd $BASE_DIR/nodered && docker compose down"
    echo "  Stop Restreamer:       cd $BASE_DIR/restreamer && docker compose down"
    echo "  Stop Tailscale:        cd $BASE_DIR/tailscale && docker compose down"
    echo "  Update services:       cd service_dir && docker compose pull && docker compose up -d"
    echo ""
}

# Main execution
main() {
    print_status "Starting installation process..."
    
    # Install basic packages
    install_packages
    
    # Install Docker
    install_docker
    
    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Create directory structure
    create_directories
    
    # Create docker-compose files
    create_docker_compose_files
    
    # Set permissions
    set_permissions
    
    # Start services
    start_services
    
    # Show final information
    show_final_info
    
    print_status "Installation completed successfully!"
    print_status "All services are running in separate directories under: $BASE_DIR"
}

# Run main function
main "$@"