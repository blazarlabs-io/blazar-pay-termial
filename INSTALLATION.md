# Hydra Terminal - Installation Guide

## Quick Installation

### 1. Run the Setup Script

```bash
# Make the script executable (if not already)
chmod +x setup.sh

# Run the setup script
./setup.sh
```

### 2. Validate Installation

```bash
# Run the validation script
./validate-setup.sh
```

### 3. Configure API Endpoint

Copy `.env.example` to `.env` and set the required values (there are no defaults; the terminal exits at start if either is missing):

```bash
cp .env.example .env
# API_BASE_URL=https://<backend>        (required)
# TERMINAL_API_KEY=<device key>         (required, sent as Bearer)
# TERMINAL_POLL_INTERVAL_MS=1000        (optional)
```

Flow: the terminal polls `GET /terminal/pending-payment`, advertises the payment over BLE
(read-only value1 merchantAddress, value2 amountBaseUnits verbatim, value3 assetUnit,
value4 paymentId), polls `GET /payments/:id` until confirmed, failed or expired, then ends the session.
The terminal never authorizes or sends payments. Run tests with `npm test`.

### 4. Start the Terminal

```bash
# Development mode
npm run dev

# Or as a service
sudo systemctl start hydra-terminal.service
```

## What the Setup Script Does

The `setup.sh` script automatically:

1. **Checks Prerequisites**: Verifies system compatibility and existing installations
2. **Updates System**: Updates package lists and system packages
3. **Installs Dependencies**: Installs all required system packages for BLE operations
4. **Installs NVM**: Sets up Node Version Manager for Node.js management
5. **Installs Node.js**: Installs Node.js 18 LTS via NVM
6. **Configures Bluetooth**: Sets up Bluetooth for BLE advertising and operations
7. **Sets Permissions**: Configures user groups and Node.js capabilities
8. **Installs NPM Packages**: Installs all Node.js dependencies
9. **Creates Service**: Sets up systemd service for production deployment
10. **Validates Setup**: Tests BLE functionality and system configuration

## Manual Installation Steps

If you prefer to install manually or the script fails:

### 1. System Dependencies

```bash
sudo apt update
sudo apt install -y build-essential python3-dev libbluetooth-dev bluez bluez-tools bluetooth libudev-dev curl wget git
```

### 2. Install NVM and Node.js

```bash
# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc

# Install Node.js 18
nvm install 18
nvm use 18
nvm alias default 18
```

### 3. Configure Bluetooth

```bash
# Enable Bluetooth
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

# Add user to bluetooth group
sudo usermod -a -G bluetooth $USER

# Configure Bluetooth for BLE
sudo tee -a /etc/bluetooth/main.conf << EOF

# Hydra Terminal BLE Configuration
[General]
ControllerMode = dual
DiscoverableTimeout = 0
PairableTimeout = 0
EOF
```

### 4. Set Node.js Capabilities

```bash
# Set capabilities for BLE operations
sudo setcap cap_net_raw+eip $(which node)
```

### 5. Install Dependencies

```bash
npm install
```

## Troubleshooting

### Common Issues

#### 1. Permission Denied

```bash
# Add user to bluetooth group
sudo usermod -a -G bluetooth $USER
# Logout and login again
```

#### 2. BLE Not Working

```bash
# Restart Bluetooth service
sudo systemctl restart bluetooth

# Check BLE support
sudo hcitool lescan
```

#### 3. Node.js Capabilities

```bash
# Set capabilities
sudo setcap cap_net_raw+eip $(which node)

# Verify capabilities
getcap $(which node)
```

#### 4. Port Already in Use

```bash
# Check what's using port 3000
sudo netstat -tulpn | grep :3000

# Kill the process if needed
sudo kill -9 <PID>
```

### Validation Commands

```bash
# Check system status
./validate-setup.sh

# Check Bluetooth
sudo systemctl status bluetooth
sudo hcitool lescan

# Check Node.js
node --version
npm --version

# Check capabilities
getcap $(which node)
```

## Production Deployment

### 1. Enable Service

```bash
sudo systemctl enable hydra-terminal.service
sudo systemctl start hydra-terminal.service
```

### 2. Check Service Status

```bash
sudo systemctl status hydra-terminal.service
```

### 3. View Logs

```bash
sudo journalctl -u hydra-terminal.service -f
```

## Development Environment

### 1. Source Environment

```bash
source setup-env.sh
```

### 2. Run in Development Mode

```bash
npm run dev
```

### 3. Test BLE Functionality

```bash
# In another terminal
sudo hcitool lescan
# Look for "Hydra TERM" device
```

## Security Considerations

1. **API Security**: Use HTTPS for production API endpoints
2. **Network Security**: Configure firewall rules if needed
3. **Bluetooth Security**: Consider BLE pairing for production
4. **Service Security**: Run service as non-root user (already configured)

## Support

If you encounter issues:

1. Run `./validate-setup.sh` to check system status
2. Check the logs: `sudo journalctl -u hydra-terminal.service`
3. Verify Bluetooth: `sudo systemctl status bluetooth`
4. Test BLE: `sudo hcitool lescan`

For additional help, refer to the main documentation in `DOCUMENTATION.md`.
