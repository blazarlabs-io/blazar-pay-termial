const { API_BASE_URL } = require("./services");
const Gpio = require("onoff").Gpio
const states = {
    idle:"IDLE",
    payment:"PAY",
    success:"OK",
    fail:"FAIL"
}

class LED {
    constructor(red, green, blue) {
        this.hasWiFi = false;
        this.state = states.idle;
        this.paymentSerial = 0;
        this.flashCounter = 0;

        this.pins = {
            red: new Gpio(red, 'out'),
            green: new Gpio(green, 'out'),
            blue: new Gpio(blue, 'out')
        };

        this.ledLoop = setInterval(this._startLEDLoop.bind(this), 100);
    }
    setWiFi(wifi) {
        this.hasWiFi = wifi;
    }
    startPayment() {
        this.state = states.payment;
        this.paymentSerial++;
        this.flashCounter = 0;
    }
    finishPayment(ok) {
        if (this.state !== states.payment) return;
        if (ok) this.state = states.success;
        else this.state = states.fail;
        const finishedSerial = this.paymentSerial;
        setTimeout(() => {
            if (this.paymentSerial !== finishedSerial) return;
            this.state = states.idle;
        }, 5000);
    }
    exit() {
        clearInterval(this.ledLoop);
        this.state = states.idle;
        this.hasWiFi = false;
        this._setLED(0,0,0);
        this.pins.red.unexport()
        this.pins.green.unexport()
        this.pins.blue.unexport()
    }
    _setLED(red, green, blue) {
        this.pins.red.writeSync(+!red);
        this.pins.green.writeSync(+!green);
        this.pins.blue.writeSync(+!blue);
    }

    _startLEDLoop() {
        switch (this.state) {
            case states.idle:
                if (this.hasWiFi) {
                    this._setLED(0,0,1);
                } else {
                    this._setLED(1,0,0);
                }
                break;
            case states.payment: 
                this.flashCounter = (this.flashCounter+1) % 4;
                if (this.flashCounter > (4/2)-1) {
                    this._setLED(0,1,0);
                } else {
                    this._setLED(0,0,0);
                }
                break;
            case states.success:
                this._setLED(0,1,0);
                break;
            case states.fail:
                this._setLED(1,1,0);
                break;
        }
    }
}

// Replace with LED pins from /sys/kernel/debug/gpio
const ledSingleton = new LED(526,527,530);

async function checkWiFi() {
    try {
        await fetch(API_BASE_URL, { signal: AbortSignal.timeout(1000) })
        ledSingleton.setWiFi(true);
    } catch {
        ledSingleton.setWiFi(false);
    }
}

setTimeout(checkWiFi, 2000);
setInterval(checkWiFi, 30000);

module.exports = {
    LED: ledSingleton
}