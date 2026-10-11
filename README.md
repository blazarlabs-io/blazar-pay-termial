# hydra-terminal

This repository is part of the Hydrapay micropayments system. More specifically, this is the code which runs on the BLE terminal or contactless payment terminal.

[QUICK START](./QUICK_START.md)

[INSTALLATION](./INSTALLATION.md)

[GENERAL DOCUMENTATION](./DOCUMENTATION.md)

[ONBOARDING](./ONBOARDING.md)

## License

The terminal's original source code is licensed under the [Apache License 2.0](LICENSE), like the other HydraPay repositories and consistent with the Project Catalyst open-source commitment. Bundled dependencies in `node_modules` and any other third-party files retain their own licences and notices.

## Configuration (M3)

Set `API_BASE_URL` and `TERMINAL_API_KEY` (both required, no defaults; see `.env.example`).
The terminal polls `GET /terminal/pending-payment`, advertises the payment over read-only BLE
characteristics (value1 merchantAddress, value2 amountBaseUnits verbatim, value3 assetUnit,
value4 paymentId), polls `GET /payments/:id` until confirmed, failed or expired, then ends the session.
Run `npm test` for the unit tests. See QUICK_START.md.

M3 runs on Cardano preprod only (BTC bridged from Bitcoin testnet3) against the custodial demo
backend `https://blazar-api.cardano.vip`. Contactless transport: a static NFC tag on the case (see DOCUMENTATION.md, NFC Tag) and BLE. The terminal never authorizes,
signs or sends payments, and nothing is written to it over BLE. Node.js 18+ is required.
One-shot setup on a Raspberry Pi:

```bash
API_BASE_URL=https://<backend> TERMINAL_API_KEY=<device key> ./scripts/raspberry-pi-setup.sh
```
