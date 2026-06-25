require("./load-env");
const bleno = require("bleno");
const characteristics = require("./characteristics");

const MERCHANT_BASE_URL =
  process.env.MERCHANT_BASE_URL || "http://192.168.0.103:3000";
const POLL_INTERVAL_MS = Number(process.env.TERMINAL_POLL_INTERVAL_MS) || 1000;

const BlenoPrimaryService = bleno.PrimaryService;

let busy = false;
let blenoListenersAttached = false;
let activeCharacteristics = null;

function attachBlenoListenersOnce() {
  if (blenoListenersAttached) return;
  blenoListenersAttached = true;

  bleno.on("stateChange", (state) => {
    console.log("[BLE] stateChange:", state);
    if (state === "poweredOn") {
      if (activeCharacteristics) {
        bleno.startAdvertising("Hydra TERM", [characteristics.SERVICE_UUID]);
      }
    } else {
      bleno.stopAdvertising();
    }
  });

  bleno.on("advertisingStart", (error) => {
    if (error) {
      console.error("[BLE] advertisingStart error:", error);
      return;
    }
    if (!activeCharacteristics) return;
    const { Char1, Char2, Char3, Char4 } = activeCharacteristics;
    bleno.setServices([
      new BlenoPrimaryService({
        uuid: characteristics.SERVICE_UUID,
        characteristics: [Char1, Char2, Char3, Char4],
      }),
    ]);
  });

  bleno.on("disconnect", () => {
    console.log("[BLE] central disconnected");
  });
}

function startBleSession(payment) {
  activeCharacteristics = characteristics.setupCharacteristics(payment);
  attachBlenoListenersOnce();

  if (bleno.state === "poweredOn") {
    bleno.startAdvertising("Hydra TERM", [characteristics.SERVICE_UUID]);
  } else {
    console.log(
      "[BLE] adapter not poweredOn yet (",
      bleno.state,
      ") — will advertise on stateChange",
    );
  }
}

function endBleSession() {
  activeCharacteristics = null;
  bleno.stopAdvertising();
  bleno.setServices([]);
  busy = false;
}

async function pollOnce() {
  if (busy) return;
  try {
    const res = await fetch(`${MERCHANT_BASE_URL}/api/terminal/pending-payment`);
    if (res.status === 204) return;
    if (!res.ok) {
      console.error("[poll] non-OK status", res.status);
      return;
    }
    const payment = await res.json();
    console.log("[poll] new payment", payment.paymentId);
    busy = true;
    startBleSession(payment);
  } catch (err) {
    console.error("[poll] error:", err.message);
  }
}

// Exposed so characteristics.js can mark the session done after reporting.
function releaseSession() {
  endBleSession();
}

module.exports = { releaseSession, MERCHANT_BASE_URL };

console.log(`[boot] polling ${MERCHANT_BASE_URL} every ${POLL_INTERVAL_MS}ms`);
setInterval(pollOnce, POLL_INTERVAL_MS);
