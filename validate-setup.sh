#!/bin/bash

# Hydra Terminal Setup Validation Script
# This script validates that all prerequisites are met for the Hydra Terminal
# Author: Hydra Terminal Team
# Version: 1.0.0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((PASSED_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
    ((WARNING_CHECKS++))
}

log_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((FAILED_CHECKS++))
}

# Check function
check() {
    ((TOTAL_CHECKS++))
    local description="$1"
    local command="$2"
    local expected_result="$3"
    
    if eval "$command" &>/dev/null; then
        if [ "$expected_result" = "true" ] || [ -z "$expected_result" ]; then
            log_success "$description"
        else
            log_error "$description (unexpected result)"
        fi
    else
        if [ "$expected_result" = "false" ]; then
            log_success "$description"
        else
            log_error "$description"
        fi
    fi
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
        return 1
    fi
}

# Check system requirements
check_system() {
    log_info "Checking system requirements..."
    
    # Check OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        check "Operating System: $NAME $VERSION_ID" "true" "true"
    else
        log_error "Cannot detect operating system"
    fi
    
    # Check architecture
    local arch=$(uname -m)
    check "Architecture: $arch" "true" "true"
    
    # Check if running as non-root
    check "Running as non-root user" "[ $EUID -ne 0 ]" "true"
    
    # Check sudo availability
    check "sudo is available" "command_exists sudo" "true"
}

# Check Node.js and NVM
check_nodejs() {
    log_info "Checking Node.js and NVM..."
    
    # Check if NVM is installed
    check "NVM is installed" "[ -d \"$HOME/.nvm\" ]" "true"
    
    # Source NVM if available
    if [ -d "$HOME/.nvm" ]; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    fi
    
    # Check Node.js
    if command_exists node; then
        local node_version=$(node --version)
        local major_version=$(echo $node_version | cut -d'.' -f1 | sed 's/v//')
        
        check "Node.js is installed: $node_version" "true" "true"
        
        if [ "$major_version" -ge 16 ]; then
            log_success "Node.js version is compatible (16+)"
        else
            log_error "Node.js version $node_version is too old (requires 16+)"
        fi
    else
        log_error "Node.js is not installed"
    fi
    
    # Check npm
    check "npm is installed: $(npm --version)" "command_exists npm" "true"
}

# Check system dependencies
check_dependencies() {
    log_info "Checking system dependencies..."
    
    local packages=(
        "build-essential"
        "python3-dev"
        "libbluetooth-dev"
        "bluez"
        "bluez-tools"
        "bluetooth"
        "libudev-dev"
        "curl"
        "wget"
        "git"
    )
    
    for package in "${packages[@]}"; do
        check "Package $package is installed" "package_installed $package" "true"
    done
}

# Check Bluetooth functionality
check_bluetooth() {
    log_info "Checking Bluetooth functionality..."
    
    # Check if Bluetooth service is running
    check "Bluetooth service is running" "systemctl is-active --quiet bluetooth" "true"
    
    # Check if user is in bluetooth group
    check "User is in bluetooth group" "groups | grep -q bluetooth" "true"
    
    # Check if hcitool is available
    check "hcitool is available" "command_exists hcitool" "true"
    
    # Check if hciconfig is available
    check "hciconfig is available" "command_exists hciconfig" "true"
    
    # Check if BLE is supported (this might fail if no BLE devices are nearby)
    if command_exists hcitool; then
        if timeout 5 sudo hcitool lescan --duplicates &>/dev/null; then
            log_success "BLE scanning works"
        else
            log_warning "BLE scanning test failed (might be normal if no BLE devices nearby)"
        fi
    fi
}

# Check Node.js capabilities
check_capabilities() {
    log_info "Checking Node.js capabilities..."
    
    if command_exists node; then
        local node_path=$(which node)
        
        # Check if Node.js has required capabilities
        if command_exists getcap; then
            local capabilities=$(getcap "$node_path" 2>/dev/null || echo "")
            if echo "$capabilities" | grep -q "cap_net_raw"; then
                log_success "Node.js has cap_net_raw capability"
            else
                log_error "Node.js missing cap_net_raw capability"
            fi
        else
            log_warning "getcap not available, cannot check capabilities"
        fi
    fi
}

# Check project files
check_project() {
    log_info "Checking project files..."
    
    check "package.json exists" "[ -f package.json ]" "true"
    check "src/index.js exists" "[ -f src/index.js ]" "true"
    check "src/payment.js exists" "[ -f src/payment.js ]" "true"
    check "src/characteristics.js exists" "[ -f src/characteristics.js ]" "true"
    
    # Check if node_modules exists
    if [ -f package.json ]; then
        check "node_modules directory exists" "[ -d node_modules ]" "true"
        
        # Check specific dependencies
        if [ -d node_modules ]; then
            check "bleno package is installed" "[ -d node_modules/bleno ]" "true"
        fi
    fi
}

# Check network connectivity
check_network() {
    log_info "Checking network connectivity..."
    
    # The terminal only talks to the backend (no local server): check the backend is reachable
    API_URL=$(grep -E '^API_BASE_URL=' .env 2>/dev/null | cut -d= -f2-)
    if [ -n "$API_URL" ] && command_exists curl; then
        check "Backend reachable ($API_URL/health)" "curl -fsS -m 10 $API_URL/health" "true"
    else
        log_warning "API_BASE_URL not set or curl missing, cannot check the backend"
    fi
    
    # Check internet connectivity
    check "Internet connectivity" "ping -c 1 google.com" "true"
}

# Check API configuration
check_api_config() {
    log_info "Checking API configuration..."
    
    if [ -f .env ] && grep -q '^API_BASE_URL=.' .env && grep -q '^TERMINAL_API_KEY=.' .env; then
        log_success ".env has API_BASE_URL and TERMINAL_API_KEY"
    else
        log_error ".env missing API_BASE_URL or TERMINAL_API_KEY (see .env.example)"
    fi
}

# Generate report
generate_report() {
    echo ""
    log_info "Validation Report:"
    echo "==================="
    echo "Total checks: $TOTAL_CHECKS"
    echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
    echo -e "${YELLOW}Warnings: $WARNING_CHECKS${NC}"
    echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
    echo ""
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        log_success "All critical checks passed! The system is ready for Hydra Terminal."
        echo ""
        log_info "You can now run:"
        echo "  npm run dev"
        echo "  or"
        echo "  sudo systemctl start hydra-terminal.service"
    else
        log_error "Some checks failed. Please address the issues above before running Hydra Terminal."
        echo ""
        log_info "To fix issues, run:"
        echo "  ./setup.sh"
    fi
    
    if [ $WARNING_CHECKS -gt 0 ]; then
        echo ""
        log_warning "There are $WARNING_CHECKS warnings. These might not prevent the system from working but should be reviewed."
    fi
}

# Main validation function
main() {
    log_info "Starting Hydra Terminal validation..."
    echo ""
    
    check_system
    check_nodejs
    check_dependencies
    check_bluetooth
    check_capabilities
    check_project
    check_network
    check_api_config
    
    generate_report
}

# Run main function
main "$@"
