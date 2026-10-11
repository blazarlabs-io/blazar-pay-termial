require("./load-env");
const { loadConfig, fetchPending, watchPayment, exclusive } = require("./payment");

let cfg;
try {
  cfg = loadConfig();
} catch (err) {
  console.error(`[boot] ${err.message} (see .env.example)`);
  process.exit(1);
}

const bleno = require("bleno");
const characteristics = require("./characteristics");

const BlenoPrimaryService = bleno.PrimaryService;

let blenoListenersAttached = false;
let activeCharacteristics = null;

function applyServices() {
  if (!activeCharacteristics) return;
  bleno.setServices([
    new BlenoPrimaryService({
      uuid: characteristics.SERVICE_UUID,
      characteristics: activeCharacteristics,
    }),
  ]);
}

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
    applyServices();
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
    // Register the service now too: after a stop/start pair on back-to-back sessions
    // "advertisingStart" may not fire again, which left the second payment without its GATT service.
    applyServices();
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
}

async function pollOnce() {
  let payment = null;
  try {
    payment = await fetchPending(cfg);
    if (!payment) return;
    console.log("[poll] new payment", payment.paymentId, payment.state);
    startBleSession(payment);
    const final = await watchPayment(cfg, payment);
    console.log(`[session] ${payment.paymentId} ended: ${final}`);
    endBleSession();
  } catch (err) {
    console.error("[poll] error:", err.message);
    if (payment) endBleSession();
  }
}

console.log(`[boot] polling ${cfg.baseUrl} every ${cfg.pollMs}ms`);
setInterval(exclusive(pollOnce), cfg.pollMs);
