# Blazar Terminal - Quick Start Guide

## Quick Setup (5 minutes)

### 1. Prerequisites

- Raspberry Pi Zero 2W with Raspberry Pi OS
- Node.js 18+ installed (the terminal uses the built-in `fetch`)
- Bluetooth enabled

### 2. Installation

```bash
# Install dependencies
npm install

# Configure Bluetooth permissions
sudo setcap cap_net_raw+eip $(eval readlink -f `which node`)
sudo usermod -a -G bluetooth $USER
```

### 3. Configuration

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

### 4. Run

```bash
npm start          # or: npm run dev (auto-restart)
```

Or install everything, including the systemd service, in one step on the Pi:

```bash
API_BASE_URL=https://<backend> TERMINAL_API_KEY=<device key> ./scripts/raspberry-pi-setup.sh
sudo journalctl -u hydra-terminal.service -f
```

## Testing

### 1. Unit tests

```bash
npm test
```

### 2. Check the backend connection

```bash
set -a; . ./.env; set +a   # load API_BASE_URL and TERMINAL_API_KEY into the shell
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TERMINAL_API_KEY" \
  "$API_BASE_URL/terminal/pending-payment"
# 204 = connected, no pending request; 200 = a request is pending; 401/403 = wrong key
```

### 3. Check BLE advertising

Create a payment request in the merchant web, then:

```bash
sudo hcitool lescan
# Look for "Hydra TERM" device
```

The terminal advertises only while a request is pending.

### 4. Monitor Logs

```bash
sudo journalctl -u hydra-terminal.service -f
# [poll] new payment <paymentId> created
# [payment <paymentId>] created -> confirmed   (each state change is logged)
# [session] <paymentId> ended: confirmed
```

## Common Commands

```bash
# Start the terminal
npm start

# Check Bluetooth status
sudo systemctl status bluetooth

# Restart Bluetooth
sudo systemctl restart bluetooth

# Check BLE devices
sudo hcitool lescan

# Service logs
sudo journalctl -u hydra-terminal.service -f
```

## Troubleshooting

| Issue                    | Solution                                    |
| ------------------------ | ------------------------------------------- |
| BLE not advertising      | `sudo systemctl restart bluetooth`          |
| Permission denied        | `sudo setcap cap_net_raw+eip $(which node)` |
| API connection failed    | Check `API_BASE_URL`/`TERMINAL_API_KEY` in `.env` |
| `Missing required env: ...` at start | Set the variable in `.env` (see `.env.example`) |

## BLE Characteristics

| UUID                                   | Name             | Type  | Purpose                    |
| -------------------------------------- | ---------------- | ----- | -------------------------- |
| `a781af9a-9a04-4422-9d78-9014497ccdc0` | Merchant Address | Read  | Merchant's Cardano address |
| `61b64163-35fa-438a-810c-018d1a719667` | Payment Amount   | Read  | Amount, base units verbatim  |
| `52f34145-0363-4f4e-9fab-a133e8e5b0b1` | Asset Unit       | Read  | Asset identifier           |
| `44f2e2a5-f323-44a2-bfbb-4afe3ef2b3ba` | Payment Id       | Read  | Backend paymentId (UUID)   |

## Backend endpoints used

All calls send `Authorization: Bearer <TERMINAL_API_KEY>`.

- `GET /terminal/pending-payment` - oldest pending request of this merchant (200) or none (204)
- `GET /payments/:id` - state of the advertised payment, polled until `confirmed`, `failed` or `expired`

The terminal never authorizes or sends payments, and nothing is written to it over BLE.

For detailed documentation, see [DOCUMENTATION.md](./DOCUMENTATION.md)
