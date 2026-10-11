#!/usr/bin/env bash
#
# Hydrapay Raspberry Pi terminal — one-shot setup
#
# Installs system dependencies, Node.js, Bluetooth boot fixes, the BLE terminal
# agent, and systemd units so the terminal starts on boot.
#
# Usage (on the Pi, as a normal user with sudo):
#   API_BASE_URL=https://<backend> ./scripts/raspberry-pi-setup.sh   (prompts for the device key, input hidden)
#
# Run from a git checkout of this repo (src/ is the single source deployed).
#
# Environment (all optional):
#   API_BASE_URL        — REQUIRED backend base URL (no default)
#   TERMINAL_API_KEY    — REQUIRED terminal device key (no default)
#   INSTALL_DIR         — install path (default: $HOME/blazar-pay-termial)
#   TERMINAL_USER       — systemd service user (default: current user)
#   NODE_MAJOR          — Node.js major version if apt install needed (default: 20)
#   SKIP_APT            — set to 1 to skip apt packages (already provisioned)
#   SKIP_START          — set to 1 to install but not enable/start services
#
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

API_BASE_URL="${API_BASE_URL:-}"
TERMINAL_API_KEY="${TERMINAL_API_KEY:-}"
# Prefer typing the key at a hidden prompt over putting it on the command line (shell history)
if [[ -z "$TERMINAL_API_KEY" && -t 0 ]]; then
  read -rsp "Terminal device key (input hidden): " TERMINAL_API_KEY; echo
fi
TERMINAL_POLL_INTERVAL_MS="${TERMINAL_POLL_INTERVAL_MS:-1000}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/blazar-pay-termial}"
TERMINAL_USER="${TERMINAL_USER:-$(whoami)}"
NODE_MAJOR="${NODE_MAJOR:-20}"
SKIP_APT="${SKIP_APT:-0}"
SKIP_START="${SKIP_START:-0}"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
TERMINAL_SOURCE="$(dirname "$SCRIPT_DIR")"

usage() {
  cat <<EOF
Hydrapay Raspberry Pi terminal setup

Installs Bluetooth + Node.js dependencies, deploys the terminal agent to:
  ${INSTALL_DIR}

Options (environment variables):
  API_BASE_URL=${API_BASE_URL:-<required>}
  TERMINAL_API_KEY=<required>
  INSTALL_DIR=${INSTALL_DIR}
  TERMINAL_USER=${TERMINAL_USER}
  NODE_MAJOR=${NODE_MAJOR}
  SKIP_APT=1          Skip apt install
  SKIP_START=1        Do not enable/start systemd services

After setup:
  sudo journalctl -u hydra-terminal.service -f
  ./scripts/raspberry-pi-validate.sh   (from merchant repo, or re-run with --validate)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required"
  fi
  if ! sudo -n true 2>/dev/null; then
    log "This script needs sudo for apt, systemd, and Bluetooth. You may be prompted for your password."
  fi
}

check_platform() {
  if [[ "$(id -u)" -eq 0 ]]; then
    die "Run as a normal user (e.g. pi), not root. The script uses sudo where needed."
  fi

  local arch
  arch="$(uname -m)"
  case "$arch" in
    armv7l|aarch64|arm64) ;;
    *)
      warn "Expected ARM (Raspberry Pi). Detected: $arch — continuing anyway."
      ;;
  esac

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    log "OS: ${PRETTY_NAME:-$NAME}"
  fi
}

apt_install() {
  local packages=("$@")
  log "Installing: ${packages[*]}"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

install_system_packages() {
  [[ "$SKIP_APT" == "1" ]] && { warn "SKIP_APT=1 — skipping apt packages"; return; }

  log "Installing system packages for BLE + native Node modules..."
  apt_install \
    ca-certificates \
    curl \
    git \
    rsync \
    build-essential \
    python3 \
    python3-dev \
    pkg-config \
    libbluetooth-dev \
    bluez \
    bluez-tools \
    bluetooth \
    libudev-dev \
    libusb-1.0-0-dev
  ok "System packages installed"
}

node_major_version() {
  node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1
}

install_nodejs() {
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node_major_version)"
    if [[ -n "$major" && "$major" -ge 18 ]]; then
      ok "Node.js $(node -v) already installed"
      return
    fi
    warn "Node.js $(node -v) is too old (need >= 18)"
  fi

  log "Installing Node.js ${NODE_MAJOR}.x via NodeSource..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
  apt_install nodejs
  ok "Node.js $(node -v) installed"
}

configure_bluetooth() {
  log "Configuring Bluetooth..."

  sudo systemctl enable bluetooth.service
  sudo systemctl start bluetooth.service

  sudo usermod -aG bluetooth "$TERMINAL_USER" || true

  local conf="/etc/bluetooth/main.conf"
  if [[ -f "$conf" ]] && ! grep -q "Hydrapay terminal BLE" "$conf" 2>/dev/null; then
    sudo cp "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"
    sudo tee -a "$conf" >/dev/null <<'EOF'

# Hydrapay terminal BLE
[General]
ControllerMode = dual
DiscoverableTimeout = 0
PairableTimeout = 0
EOF
    ok "Appended BLE settings to $conf"
  fi

  local bt_unit="/etc/systemd/system/bluetooth-enable.service"
  sudo tee "$bt_unit" >/dev/null <<'EOF'
[Unit]
Description=Unblock and power on Bluetooth (Hydrapay terminal)
After=bluetooth.service
Before=bluetooth.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/rfkill unblock bluetooth
ExecStart=/usr/bin/bluetoothctl power on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable bluetooth-enable.service
  sudo systemctl start bluetooth-enable.service

  ok "Bluetooth enabled (rfkill unblock + power on)"
}

set_node_capabilities() {
  local node_bin
  node_bin="$(command -v node || true)"
  [[ -z "$node_bin" ]] && die "node not found after install"

  node_bin="$(readlink -f "$node_bin")"
  if sudo setcap cap_net_raw+eip "$node_bin" 2>/dev/null; then
    ok "Set cap_net_raw on $node_bin"
  else
    warn "Could not set cap_net_raw on node (BLE may still work via BlueZ)"
  fi
}

deploy_terminal_app() {
  [[ -n "$API_BASE_URL" && -n "$TERMINAL_API_KEY" ]] || die "API_BASE_URL and TERMINAL_API_KEY are required"
  [[ -d "$TERMINAL_SOURCE/src" ]] || die "Terminal source missing at $TERMINAL_SOURCE"

  log "Deploying terminal agent to ${INSTALL_DIR}..."
  mkdir -p "$INSTALL_DIR"
  rsync -a --delete \
    --include '/src/***' --include '/package.json' --include '/package-lock.json' \
    --exclude '*' \
    "$TERMINAL_SOURCE/" "$INSTALL_DIR/"
  ok "Application files copied"
}

write_env_file() {
  local env_file="${INSTALL_DIR}/.env"
  log "Writing ${env_file}"
  cat >"$env_file" <<EOF
# Generated by scripts/raspberry-pi-setup.sh on $(date -Iseconds)
API_BASE_URL=${API_BASE_URL}
TERMINAL_API_KEY=${TERMINAL_API_KEY}
TERMINAL_POLL_INTERVAL_MS=${TERMINAL_POLL_INTERVAL_MS}
EOF
  chmod 600 "$env_file"
  ok "Environment file written"
}

install_npm_dependencies() {
  log "Installing npm dependencies (native bleno build may take a few minutes)..."
  cd "$INSTALL_DIR"
  npm install --omit=dev
  ok "npm install complete"
}

install_systemd_services() {
  local node_bin
  node_bin="$(readlink -f "$(command -v node)")"

  log "Installing hydra-terminal.service..."
  sudo tee /etc/systemd/system/hydra-terminal.service >/dev/null <<EOF
[Unit]
Description=Blazar Pay Hydra Terminal (BLE + HTTP polling)
After=network-online.target bluetooth-enable.service
Wants=network-online.target bluetooth-enable.service

[Service]
Type=simple
User=${TERMINAL_USER}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=-${INSTALL_DIR}/.env
ExecStart=${node_bin} ${INSTALL_DIR}/src/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload

  if [[ "$SKIP_START" != "1" ]]; then
    sudo systemctl enable hydra-terminal.service
    sudo systemctl restart hydra-terminal.service
    ok "hydra-terminal.service enabled and started"
  else
    warn "SKIP_START=1 — not starting hydra-terminal.service"
  fi
}

smoke_test() {
  log "Smoke tests..."

  if systemctl is-active --quiet bluetooth; then
    ok "bluetooth.service is active"
  else
    warn "bluetooth.service is not active"
  fi

  if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    ok "Bluetooth adapter powered on"
  else
    warn "Bluetooth adapter not powered on — try: sudo rfkill unblock bluetooth && sudo bluetoothctl power on"
  fi

  local code
  # Header via stdin so the device key never appears in the process list
  code="$(printf 'Authorization: Bearer %s\n' "${TERMINAL_API_KEY}" | curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
    -H @- "${API_BASE_URL}/terminal/pending-payment" || echo "000")"
  if [[ "$code" == "204" || "$code" == "200" ]]; then
    ok "Backend reachable (${API_BASE_URL}) HTTP ${code}"
  else
    warn "Backend returned HTTP ${code} — check API_BASE_URL, TERMINAL_API_KEY and Wi‑Fi"
  fi

  if [[ "$SKIP_START" != "1" ]]; then
    sleep 2
    if systemctl is-active --quiet hydra-terminal.service; then
      ok "hydra-terminal.service is running"
      sudo journalctl -u hydra-terminal.service -n 5 --no-pager || true
    else
      warn "hydra-terminal.service failed — run: sudo journalctl -u hydra-terminal.service -n 30"
    fi
  fi
}

main() {
  log "Hydrapay Raspberry Pi terminal setup"
  require_sudo
  check_platform
  install_system_packages
  install_nodejs
  configure_bluetooth
  set_node_capabilities
  deploy_terminal_app
  write_env_file
  install_npm_dependencies
  install_systemd_services
  smoke_test

  echo ""
  ok "Setup complete."
  echo ""
  echo "  Install dir : ${INSTALL_DIR}"
  echo "  Backend     : ${API_BASE_URL}"
  echo ""
  echo "Useful commands:"
  echo "  sudo systemctl status hydra-terminal.service"
  echo "  sudo journalctl -u hydra-terminal.service -f"
  echo "  sudo systemctl restart hydra-terminal.service"
  echo ""
  warn "If you were added to the bluetooth group, log out and back in (or reboot) before testing BLE."
}

main "$@"
