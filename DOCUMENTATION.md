# Hydra Terminal - BLE Payment Terminal Documentation

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Hardware Requirements](#hardware-requirements)
4. [Software Dependencies](#software-dependencies)
5. [Installation & Setup](#installation--setup)
6. [BLE Protocol Implementation](#ble-protocol-implementation)
7. [API Integration](#api-integration)
8. [Payment Flow](#payment-flow)
9. [Usage Guide](#usage-guide)
10. [Troubleshooting](#troubleshooting)
11. [Development](#development)
12. [Known Limitations](#known-limitations)

## Overview

The Hydra Terminal is a Bluetooth Low Energy (BLE) payment terminal for the Hydrapay micropayments system. It runs on a Raspberry Pi Zero 2W and shows the merchant's pending payment request to the payer's phone. It is a display device: it never moves money, never signs anything and never authorizes a payment.

Milestone 3 (USDM and BTC payments) runs on **Cardano preprod** only, with BTC bridged from **Bitcoin testnet3**, against the custodial demo backend `https://blazar-api.cardano.vip` (`blazar-hydra`).

### Key Features

- **Backend-driven**: polls the backend for the merchant's pending payment request; there is no local server and no merchant connection to the terminal
- **Read-only BLE**: exposes the request through four read-only characteristics, including the backend `paymentId`
- **Exact amounts**: the amount is passed through verbatim as an integer string in base units (ADA and USDM 6 decimals, BTC 8)
- **ADA, USDM and BTC**: any asset the backend accepts; the terminal has no asset-specific code
- **Raspberry Pi Compatible**: optimized for Raspberry Pi Zero 2W hardware

## Architecture

```
┌─────────────────┐  POST /payments   ┌──────────────────────┐
│  Merchant web   │──────────────────►│                      │
└─────────────────┘                   │                      │
                                      │   Hydra Pay backend  │
┌─────────────────┐  GET /terminal/   │   (custodial, owns   │
│  Hydra Terminal │  pending-payment  │   the payment state) │
│  (BLE server)   │──────────────────►│                      │
└────────┬────────┘  GET /payments/:id│                      │
         │ BLE read (value1..4)       │                      │
┌────────▼────────┐  POST /payments/  │                      │
│   Mobile App    │  :id/authorize    │                      │
│   (BLE client)  │──────────────────►│                      │
└─────────────────┘                   └──────────┬───────────┘
                                                 │ NewTx / SnapshotConfirmed
                                      ┌──────────▼───────────┐
                                      │  Hydra head (preprod)│
                                      └──────────────────────┘
```

### Component Responsibilities

- **Merchant web**: creates the payment request (asset and exact amount) and watches it until it is final
- **Hydra Terminal**:
  - polls the backend for the merchant's pending request
  - advertises it over BLE as read-only characteristics
  - watches the payment until it is `confirmed`, `failed` or `expired`, then stops advertising
- **Mobile App**: reads the request over BLE, checks it against the backend record, and the payer authorizes it with an authenticated call to the backend
- **Backend**: owns the payment record, executes the authorized payment in the Hydra head and reports `confirmed` only after the Hydra snapshot that contains the transaction is confirmed

## Hardware Requirements

### Primary Hardware

![Raspberry pi zero w2](assets/rbpizw2.jpeg)

- **Raspberry Pi Zero 2W** (recommended)
  - ARM Cortex-A53 quad-core 64-bit processor
  - 512MB RAM
  - Built-in WiFi and Bluetooth 4.2
  - MicroSD card slot (minimum 8GB, Class 10)

### Hardware Setup

1. **SD Card Preparation**:

   - Flash Raspberry Pi OS Lite (64-bit recommended)
   - Enable SSH and WiFi during initial setup
   - Configure static IP if needed for network stability

2. **Bluetooth Configuration**:

   - Ensure Bluetooth is enabled in system settings
   - Configure Bluetooth to run without authentication for BLE advertising
   - Set up proper permissions for BLE operations

3. **Network Configuration**:

   - Stable WiFi connection with outbound HTTPS access to the backend
   - No inbound port is needed: the terminal only makes outgoing requests

4. **Power Requirements**:
   - 5V/2.5A power supply (USB-C)
   - Consider UPS for critical deployments

### Optional Hardware

- **Display**: Small LCD for status monitoring
- **LED Indicators**: Visual feedback for payment status
- **Enclosure**: Weatherproof case for outdoor deployment
- **NFC tag**: an NTAG213/215 sticker on the case (see [NFC Tag](#nfc-tag)); the Pi does not drive it

## Software Dependencies

### System Requirements

- **Operating System**: Linux (Raspberry Pi OS recommended)
- **Node.js**: Version 18 or higher (the built-in `fetch` is used)
- **npm**: Version 8.x or higher
- **Bluetooth Stack**: BlueZ 5.50 or higher

### Node.js Dependencies

```json
{
  "bleno": "npm:@abandonware/bleno@^0.6.2"
}
```

- **bleno**: BLE peripheral library for Node.js (abandonware fork with continued support)
- **nodemon** (dev only): auto-restart for `npm run dev`

## Installation & Setup

The quickest path is the one-shot script; see [INSTALLATION.md](./INSTALLATION.md) for the step-by-step alternative.

```bash
git clone <repository-url> blazar-pay-termial && cd blazar-pay-termial
API_BASE_URL=https://<backend> TERMINAL_API_KEY=<device key> ./scripts/raspberry-pi-setup.sh
```

It installs the system packages and Node.js, applies Bluetooth boot fixes, deploys `src/`, writes `.env` and enables the `hydra-terminal` systemd service (the unit reads `.env` through `EnvironmentFile`).

### Configuration

Copy `.env.example` to `.env` (ignored by git) and set:

| Variable | Required | Notes |
|---|---|---|
| `API_BASE_URL` | yes | Backend base URL, e.g. `https://blazar-api.cardano.vip`. No default |
| `TERMINAL_API_KEY` | yes | Device key of the merchant account, issued by the backend operator, sent as `Authorization: Bearer`. No default |
| `TERMINAL_POLL_INTERVAL_MS` | no | Poll interval, default 1000 |

If a required variable is missing, the process exits at start with `Missing required env: ...`.

### Bluetooth Configuration

```bash
# Enable Bluetooth service
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

# Add user to bluetooth group
sudo usermod -a -G bluetooth $USER

# Allow Node.js to use raw BLE sockets
sudo setcap cap_net_raw+eip $(eval readlink -f `which node`)
```

## BLE Protocol Implementation

### Service UUID

```
Service UUID: 1d4ddcb2-279d-42e2-a95a-274352a25248
```

### Characteristics

All characteristics are **read-only** UTF-8 strings, set from the backend payment record.

| # | UUID | Name | Value |
|---|---|---|---|
| value1 | `a781af9a-9a04-4422-9d78-9014497ccdc0` | Merchant Address | Merchant's Cardano address |
| value2 | `61b64163-35fa-438a-810c-018d1a719667` | Payment Amount | `amountBaseUnits`, verbatim (integer string in base units, never converted) |
| value3 | `52f34145-0363-4f4e-9fab-a133e8e5b0b1` | Asset Unit | `lovelace`, or policy id + asset name hex |
| value4 | `44f2e2a5-f323-44a2-bfbb-4afe3ef2b3ba` | Payment Id | Backend `paymentId` (UUID) |

The former write characteristic for the client address (`9b16159d-…`) is retired: a BLE write never moves money. The phone reads value1..4, loads `GET /payments/:paymentId` from the backend and aborts if the values differ from the backend record.

### BLE Advertising

- **Device Name**: "Hydra TERM"
- **Service UUIDs**: `1d4ddcb2-279d-42e2-a95a-274352a25248`
- **Connectable**: Yes
- **When**: only while a payment request is pending; advertising stops when the payment is final

### NFC Tag

Phones can also find the terminal's payment by tapping a static NFC tag, with BLE as the alternative. The tag holds one NDEF URI record:

```
myapp://home/nfc?terminal=<terminal account id>
```

`<terminal account id>` is the `id` returned by `POST /accounts` when the terminal's merchant account was created. Write it once with a phone app such as NFC Tools (Write → URL/URI), or emulate it with a Flipper Zero (NFC → Add manually → NTAG215 → Emulate, then write the record from the phone). The app calls `GET /terminals/:id/pending-payment` with the payer's Firebase token and gets the same request the terminal is advertising. The tag never changes and the terminal software does nothing for it.

## API Integration

Every request sends `Authorization: Bearer <TERMINAL_API_KEY>`. The backend maps the device key to the merchant account; a terminal key cannot authorize payments.

| Endpoint | Purpose | Response |
|---|---|---|
| `GET /terminal/pending-payment` | The merchant's oldest unexpired request in state `created` | 200 `Payment`, or 204 when nothing is pending |
| `GET /payments/:id` | State of the advertised payment | 200 `Payment` |

`Payment` fields used by the terminal: `paymentId`, `merchantAddress`, `assetUnit`, `amountBaseUnits`, `state`, `expiresAt`. States: `created → authorized → submitted → confirmed`, or `failed` / `expired`. A request expires 120 s after it is created, and a new request from the merchant expires the previous unpaid one.

## Payment Flow

1. The merchant creates a request in the merchant web (`POST /payments`, state `created`).
2. The terminal's poll (`GET /terminal/pending-payment`, every `TERMINAL_POLL_INTERVAL_MS`) returns it. The terminal sets value1..4 and starts advertising "Hydra TERM".
3. The payer's phone, held close to the terminal, connects, reads value1..4 and disconnects.
4. The phone cross-checks the values with `GET /payments/:paymentId` and shows the amount from the backend. The payer taps Pay; the phone calls `POST /payments/:paymentId/authorize` with the payer's Firebase ID token. This authenticated call is the payer's consent.
5. The backend submits the Hydra transaction and sets `confirmed` once the snapshot containing it is confirmed.
6. The terminal polls `GET /payments/:paymentId` and logs every state change. On `confirmed`, `failed`, `expired` or when `expiresAt` passes, it stops advertising, clears its services and goes back to polling.

The merchant web and the phone read the same backend record, so they show the same result.

## Usage Guide

### Starting the Terminal

```bash
# Production mode
npm start

# Development mode with auto-restart
npm run dev

# As a service (after scripts/raspberry-pi-setup.sh)
sudo systemctl start hydra-terminal.service
```

### Monitoring

```bash
sudo journalctl -u hydra-terminal.service -f
```

Typical log lines:

```
[boot] polling https://<backend> every 1000ms
[poll] new payment <paymentId> created
[payment <paymentId>] created -> confirmed
[session] <paymentId> ended: confirmed
```

## Troubleshooting

### Common Issues

#### 1. Terminal exits at start

`Missing required env: ...`: create `.env` from `.env.example` and set `API_BASE_URL` and `TERMINAL_API_KEY`.

#### 2. BLE Advertising Not Working

```bash
# Check Bluetooth status
sudo systemctl status bluetooth

# Restart Bluetooth service
sudo systemctl restart bluetooth

# Check BLE permissions
sudo setcap cap_net_raw+eip $(eval readlink -f `which node`)
```

Remember that the terminal advertises only while a request is pending.

#### 3. Permission Denied Errors

```bash
# Add user to bluetooth group
sudo usermod -a -G bluetooth $USER
# Logout and login again

# Set proper capabilities for Node.js
sudo setcap cap_net_raw+eip $(eval readlink -f `which node`)
```

#### 4. API Connection Issues

```bash
set -a; . ./.env; set +a
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TERMINAL_API_KEY" \
  "$API_BASE_URL/terminal/pending-payment"
```

- `204`: connected, nothing pending; `200`: a request is pending
- `401` / `403`: the device key is wrong or not mapped to a merchant account
- `000`: no network or wrong `API_BASE_URL`
- `[poll] error: pending-payment HTTP <code>` in the log points to the same causes

### Debug Commands

```bash
# Check BLE devices
sudo hcitool lescan

# Monitor Bluetooth logs
sudo journalctl -u bluetooth -f

# Check Node.js process
ps aux | grep node
```

## Development

### Project Structure

```
blazar-pay-termial/
├── src/
│   ├── index.js           # Entry point: env check, poll loop, BLE session
│   ├── payment.js         # Pure payment logic: config, pending-payment fetch, watcher (no BLE)
│   ├── characteristics.js # Four read-only BLE characteristics
│   └── load-env.js        # Loads .env
├── test/
│   └── payment.test.js    # Unit tests (node --test)
├── scripts/
│   ├── raspberry-pi-setup.sh     # One-shot Pi setup and systemd service
│   └── raspberry-pi-validate.sh  # Checks a Pi installation
├── .env.example
└── package.json
```

### Development Setup

1. Clone the repository
2. Install dependencies: `npm install`
3. `cp .env.example .env` and set `API_BASE_URL` and `TERMINAL_API_KEY`
4. Run in development mode: `npm run dev`

### Testing

```bash
npm test
```

The unit tests mock `fetch` and need no BLE adapter: config fail-fast, value2 passed through verbatim (including a 30-digit amount), pending-payment parsing with the Bearer header and 204, session end on `confirmed` / `failed` / `expired`, and end at `expiresAt`.

For an end-to-end check, create a request in the merchant web and pay it with the mobile app; the log shows the state changes and the merchant web shows the same final state.

### Security Considerations

- BLE data is public and unencrypted. It contains only the request (merchant address, amount, asset, payment id); nothing secret is advertised and nothing is accepted over BLE.
- Use an `https://` `API_BASE_URL`; the device key is sent on every poll.
- Keep `TERMINAL_API_KEY` only in `.env` on the device (ignored by git).

## Known Limitations

- Testnet/preprod only; custodial demo backend. One merchant, one terminal per merchant account.
- Contactless transport: BLE. Proximity is a phone-side RSSI heuristic.
- The device key has the full scope of the merchant account (it can also create payment requests); protect the SD card.
- The local expiry check uses the Pi clock; keep NTP time sync enabled.
- The terminal has been unit-tested; a BLE session on a Raspberry Pi against the live backend has not been recorded yet.

---

_For updates and additional information, refer to the project repository._
