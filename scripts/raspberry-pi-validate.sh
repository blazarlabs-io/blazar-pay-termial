#!/usr/bin/env bash
#
# Validate Hydrapay Raspberry Pi terminal setup.
#
# Usage:
#   ./scripts/raspberry-pi-validate.sh
#   INSTALL_DIR=~/blazar-pay-termial ./scripts/raspberry-pi-validate.sh
#
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "${GREEN}[PASS]${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; WARN=$((WARN + 1)); }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }

INSTALL_DIR="${INSTALL_DIR:-${HOME}/blazar-pay-termial}"

info "Validating Hydrapay terminal (INSTALL_DIR=${INSTALL_DIR})"
echo ""

if command -v node >/dev/null 2>&1; then
  major="$(node -v | sed 's/^v//' | cut -d. -f1)"
  if [[ "$major" -ge 18 ]]; then
    pass "Node.js $(node -v)"
  else
    fail "Node.js $(node -v) — need >= 18"
  fi
else
  fail "Node.js not installed"
fi

for pkg in bluez libbluetooth-dev build-essential python3; do
  if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
    pass "apt package: $pkg"
  else
    fail "apt package missing: $pkg"
  fi
done

if systemctl is-active --quiet bluetooth; then
  pass "bluetooth.service active"
else
  fail "bluetooth.service not active"
fi

if systemctl is-enabled --quiet bluetooth-enable.service 2>/dev/null; then
  pass "bluetooth-enable.service enabled"
else
  warn "bluetooth-enable.service not enabled"
fi

if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
  pass "Bluetooth adapter powered on"
else
  fail "Bluetooth adapter not powered on"
fi

if groups | grep -qw bluetooth; then
  pass "User in bluetooth group"
else
  warn "User not in bluetooth group (re-login after setup)"
fi

if [[ -f "${INSTALL_DIR}/package.json" && -f "${INSTALL_DIR}/src/index.js" ]]; then
  pass "Terminal app installed at ${INSTALL_DIR}"
else
  fail "Terminal app missing at ${INSTALL_DIR}"
fi

if [[ -d "${INSTALL_DIR}/node_modules/bleno" ]]; then
  pass "bleno npm package installed"
else
  fail "bleno not installed — run: cd ${INSTALL_DIR} && npm install"
fi

if [[ -f "${INSTALL_DIR}/.env" ]]; then
  pass ".env exists"
  # shellcheck disable=SC1091
  source "${INSTALL_DIR}/.env" 2>/dev/null || true
  url="${MERCHANT_BASE_URL:-${MERCHANT_API_BASE_URL:-}}"
  if [[ -n "$url" ]]; then
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
      "${url}/api/terminal/pending-payment" 2>/dev/null || echo 000)"
    if [[ "$code" == "204" || "$code" == "200" ]]; then
      pass "Merchant API ${url} → HTTP ${code}"
    else
      fail "Merchant API ${url} → HTTP ${code}"
    fi
  else
    warn "MERCHANT_BASE_URL not set in .env"
  fi
else
  fail ".env missing"
fi

if systemctl is-enabled --quiet hydra-terminal.service 2>/dev/null; then
  pass "hydra-terminal.service enabled"
else
  fail "hydra-terminal.service not enabled"
fi

if systemctl is-active --quiet hydra-terminal.service 2>/dev/null; then
  pass "hydra-terminal.service running"
else
  fail "hydra-terminal.service not running"
fi

echo ""
info "Summary: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
if [[ "$FAIL" -eq 0 ]]; then
  echo -e "${GREEN}Terminal looks ready.${NC}"
  exit 0
fi
echo -e "${RED}Fix failures above, then re-run this script.${NC}"
exit 1
