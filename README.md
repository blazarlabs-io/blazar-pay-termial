# hydra-terminal

This repository is part of the Hydrapay micropayments system. More specifically, this is the code which runs on the BLE terminal or contactless payment terminal.

[QUICK START](./QUICK_START.md)

[INSTALLATION](./INSTALLATION.md)

[GENERAL DOCUMENTATION](./DOCUMENTATION.md)

[ONBOARDING](./ONBOARDING.md)

## Notes

* Works on RPi OS Legacy (Bookworm) 64-bit Lite.
* Use `setup.sh` and not manual steps from `DOCUMENTATION.md`.
* Additionally install `libnode108` with APT.
* GPIO pin name may be different in kernel, use `cat /sys/kernel/debug/gpio` to find the correlation.
* To disable the LED on startup add `gpio=99=op,dh` for each pin (replace 99), at the end of `/boot/firmware/config.txt` 
