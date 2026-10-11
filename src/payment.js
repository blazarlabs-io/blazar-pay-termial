// Pure payment logic (no BLE), so it can be tested without bleno.
const TERMINAL_STATES = ["confirmed", "failed", "expired"];
const REQUEST_TIMEOUT_MS = 10_000;
const EXPIRY_SLACK_MS = 5_000; // the Pi has no RTC: let the backend report `expired` first

function loadConfig(env = process.env) {
  const missing = ["API_BASE_URL", "TERMINAL_API_KEY"].filter((k) => !env[k]);
  if (missing.length) {
    throw new Error(`Missing required env: ${missing.join(", ")}`);
  }
  const baseUrl = env.API_BASE_URL.replace(/\/+$/, "");
  const { protocol, hostname } = new URL(baseUrl);
  if (protocol !== "https:" && !["localhost", "127.0.0.1", "[::1]"].includes(hostname)) {
    throw new Error("API_BASE_URL must be https: every request carries the device key");
  }
  return {
    baseUrl,
    apiKey: env.TERMINAL_API_KEY,
    pollMs: Number(env.TERMINAL_POLL_INTERVAL_MS) || 1000,
  };
}

// BLE values value1..value4; amount is passed through verbatim, never converted.
function paymentValues(p) {
  return {
    value1: String(p.merchantAddress),
    value2: String(p.amountBaseUnits),
    value3: String(p.assetUnit),
    value4: String(p.paymentId),
  };
}

async function getJson(cfg, path, fetchFn) {
  const res = await fetchFn(`${cfg.baseUrl}${path}`, {
    headers: { Authorization: `Bearer ${cfg.apiKey}` },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  return res;
}

// Returns the pending Payment, or null on 204.
async function fetchPending(cfg, fetchFn = fetch) {
  const res = await getJson(cfg, "/terminal/pending-payment", fetchFn);
  if (res.status === 204) return null;
  if (!res.ok) throw new Error(`pending-payment HTTP ${res.status}`);
  const p = await res.json();
  for (const k of ["paymentId", "merchantAddress", "assetUnit", "amountBaseUnits"]) {
    if (typeof p[k] !== "string" || !p[k]) throw new Error(`pending-payment: bad ${k}`);
  }
  return p;
}

// Polls the payment until a terminal state; returns it. Only a `created` payment ends locally at
// expiresAt (backend unreachable): an authorized one may still confirm after it.
async function watchPayment(cfg, payment, opts = {}) {
  const { fetchFn = fetch, sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
    now = Date.now, log = console.log } = opts;
  const deadline = Date.parse(payment.expiresAt) + EXPIRY_SLACK_MS;
  let last = payment.state;
  while (true) {
    if (last === "created" && !(now() < deadline)) {
      log(`[payment ${payment.paymentId}] expiresAt reached`);
      return "expired";
    }
    try {
      const res = await getJson(cfg, `/payments/${payment.paymentId}`, fetchFn);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const { state } = await res.json();
      if (state !== last) {
        log(`[payment ${payment.paymentId}] ${last} -> ${state}`);
        last = state;
      }
      if (TERMINAL_STATES.includes(state)) return state;
    } catch (err) {
      log(`[payment ${payment.paymentId}] poll error: ${err.message}`);
    }
    await sleep(cfg.pollMs);
  }
}

// Skips a tick while the previous run is still going: setInterval ticks must not start a second session.
function exclusive(fn) {
  let running = false;
  return async () => {
    if (running) return;
    running = true;
    try {
      await fn();
    } finally {
      running = false;
    }
  };
}

module.exports = { loadConfig, paymentValues, fetchPending, watchPayment, exclusive, TERMINAL_STATES };
