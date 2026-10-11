#!/bin/bash

# Hydra Terminal Setup Script
# This script installs all dependencies and requirements for the Hydra Terminal BLE payment system
# Author: Hydra Terminal Team
# Version: 1.0.0

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Check if sudo is available
check_sudo() {
    if ! command -v sudo &> /dev/null; then
        log_error "sudo is not available. Please install sudo or run as root."
        exit 1
    fi
}

# Detect OS and architecture
detect_system() {
    log_info "Detecting system information..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        OS_VERSION=$VERSION_ID
    else
        log_error "Cannot detect operating system. This script supports Ubuntu, Debian, and Raspberry Pi OS."
        exit 1
    fi
    
    ARCH=$(uname -m)
    
    log_info "OS: $OS $OS_VERSION"
    log_info "Architecture: $ARCH"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if package is installed
package_installed() {
    if command_exists dpkg; then
        dpkg -l | grep -q "^ii  $1 "
    else
        log_warning "Cannot check if package $1 is installed (dpkg not found)"
        return 1
    fi
}

# Update package lists
update_packages() {
    log_info "Updating package lists..."
    sudo apt update
    log_success "Package lists updated"
}

# Install system dependencies
install_system_dependencies() {
    log_info "Installing system dependencies..."
    
    local packages=(
        "build-essential"
        "python3-dev"
        "python3-pip"
        "make"
        "gcc"
        "g++"
        "curl"
        "wget"
        "git"
        "unzip"
        "libc6-dev"
        "libssl-dev"
        "libffi-dev"
        "libbluetooth-dev"
        "bluez"
        "bluez-tools"
        "bluetooth"
        "libudev-dev"
        "libusb-1.0-0-dev"
        "libnss3-dev"
        "libatk-bridge2.0-dev"
        "libdrm2"
        "libxcomposite1"
        "libxdamage1"
        "libxrandr2"
        "libgbm1"
        "libxss1"
        "libasound2"
    )
    
    local packages_to_install=()
    
    for package in "${packages[@]}"; do
        if package_installed "$package"; then
            log_info "Package $package is already installed"
        else
            packages_to_install+=("$package")
        fi
    done
    
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "Installing packages: ${packages_to_install[*]}"
        sudo apt install -y "${packages_to_install[@]}"
        log_success "System dependencies installed"
    else
        log_success "All system dependencies are already installed"
    fi
}

# Install NVM
install_nvm() {
    log_info "Installing NVM (Node Version Manager)..."
    
    if [ -d "$HOME/.nvm" ]; then
        log_info "NVM is already installed"
        return 0
    fi
    
    # Download and install NVM
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    
    # Source NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    log_success "NVM installed successfully"
}

# Install Node.js via NVM
install_nodejs() {
    log_info "Installing Node.js via NVM..."
    
    # Source NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    # Check if Node.js is already installed
    if command_exists node; then
        local current_version=$(node --version)
        log_info "Node.js is already installed: $current_version"
        
        # Check if version is 16+
        local major_version=$(echo $current_version | cut -d'.' -f1 | sed 's/v//')
        if [ "$major_version" -ge 16 ]; then
            log_success "Node.js version is compatible (16+)"
            return 0
        else
            log_warning "Node.js version $current_version is too old. Installing Node.js 18..."
        fi
    fi
    
    # Install Node.js 18 LTS
    nvm install 18
    nvm use 18
    nvm alias default 18
    
    # Verify installation
    if command_exists node && command_exists npm; then
        log_success "Node.js $(node --version) and npm $(npm --version) installed successfully"
    else
        log_error "Failed to install Node.js"
        exit 1
    fi
}

# Configure Bluetooth
configure_bluetooth() {
    log_info "Configuring Bluetooth for BLE operations..."
    
    # Enable Bluetooth service
    sudo systemctl enable bluetooth
    sudo systemctl start bluetooth
    
    # Add user to bluetooth group
    sudo usermod -a -G bluetooth $USER
    
    # Configure Bluetooth for BLE advertising
    local bluetooth_config="/etc/bluetooth/main.conf"
    if [ -f "$bluetooth_config" ]; then
        # Backup original config
        sudo cp "$bluetooth_config" "$bluetooth_config.backup"
        
        # Configure Bluetooth for BLE
        sudo tee -a "$bluetooth_config" > /dev/null <<EOF

# Hydra Terminal BLE Configuration
[General]
ControllerMode = dual
DiscoverableTimeout = 0
PairableTimeout = 0
EOF
        log_success "Bluetooth configuration updated"
    else
        log_warning "Bluetooth configuration file not found at $bluetooth_config"
    fi
}

# Set up Node.js capabilities
setup_nodejs_capabilities() {
    log_info "Setting up Node.js capabilities for BLE operations..."
    
    # Source NVM to get Node.js path
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    local node_path=$(which node)
    
    if [ -n "$node_path" ]; then
        # Set capabilities for BLE operations
        sudo setcap cap_net_raw+eip "$node_path"
        log_success "Node.js capabilities set for BLE operations"
    else
        log_error "Node.js not found. Please ensure Node.js is installed."
        exit 1
    fi
}

# Install Node.js dependencies
install_nodejs_dependencies() {
    log_info "Installing Node.js dependencies..."
    
    # Source NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Check if package.json exists
    if [ ! -f "package.json" ]; then
        log_error "package.json not found. Please run this script from the project directory."
        exit 1
    fi
    
    # Install dependencies
    npm install
    
    log_success "Node.js dependencies installed"
}

# Validate BLE functionality
validate_ble() {
    log_info "Validating BLE functionality..."
    
    # Check if Bluetooth is running
    if ! systemctl is-active --quiet bluetooth; then
        log_error "Bluetooth service is not running"
        return 1
    fi
    
    # Check if hcitool is available
    if ! command_exists hcitool; then
        log_error "hcitool not found. Please install bluez-tools"
        return 1
    fi
    
    # Check if BLE is supported
    if ! sudo hcitool lescan --duplicates &>/dev/null; then
        log_warning "BLE scanning test failed. This might be normal if no BLE devices are nearby."
    else
        log_success "BLE functionality validated"
    fi
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service for Hydra Terminal..."
    
    local service_file="/etc/systemd/system/hydra-terminal.service"
    local current_dir=$(pwd)
    local user=$(whoami)
    
    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Hydra Terminal BLE Payment Service
After=bluetooth.service network.target
Wants=bluetooth.service

[Service]
Type=simple
User=$user
WorkingDirectory=$current_dir
ExecStart=/home/$user/.nvm/versions/node/v18.0.0/bin/node src/index.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=NVM_DIR=/home/$user/.nvm
Environment=PATH=/home/$user/.nvm/versions/node/v18.0.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    sudo systemctl daemon-reload
    
    log_success "Systemd service created at $service_file"
    log_info "To enable the service: sudo systemctl enable hydra-terminal.service"
    log_info "To start the service: sudo systemctl start hydra-terminal.service"
}

# Create environment setup script
create_env_setup() {
    log_info "Creating environment setup script..."
    
    cat > setup-env.sh << 'EOF'
#!/bin/bash
# Hydra Terminal Environment Setup
# Source this file to set up the environment for development

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Use Node.js 18
nvm use 18

echo "Hydra Terminal environment loaded"
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"
EOF

    chmod +x setup-env.sh
    log_success "Environment setup script created: setup-env.sh"
}

# Main installation function
main() {
    log_info "Starting Hydra Terminal setup..."
    log_info "This script will install all dependencies and configure the system for BLE operations"
    
    # Pre-flight checks
    check_root
    check_sudo
    detect_system
    
    # Installation steps
    update_packages
    install_system_dependencies
    install_nvm
    install_nodejs
    configure_bluetooth
    setup_nodejs_capabilities
    install_nodejs_dependencies
    
    # Validation
    validate_ble
    
    # Post-installation setup
    create_systemd_service
    create_env_setup
    
    log_success "Hydra Terminal setup completed successfully!"
    
    echo ""
    log_info "Next steps:"
    echo "1. Logout and login again to apply group changes"
    echo "2. Configure your API endpoint in .env (API_BASE_URL, TERMINAL_API_KEY; see .env.example)"
    echo "3. Test the installation: npm run dev"
    echo "4. (Optional) Enable the systemd service: sudo systemctl enable hydra-terminal.service"
    echo ""
    log_info "For development, source the environment: source setup-env.sh"
    echo ""
    log_warning "Important: You may need to reboot the system for all Bluetooth changes to take effect."
}

# Run main function
main "$@"
