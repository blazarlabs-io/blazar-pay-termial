const test = require("node:test");
const assert = require("node:assert");
const { loadConfig, paymentValues, fetchPending, watchPayment, exclusive } = require("../src/payment");

const cfg = { baseUrl: "http://x", apiKey: "k", pollMs: 0 };
const pay = {
  paymentId: "44f2e2a5-f323-44a2-bfbb-4afe3ef2b3ba",
  merchantAddress: "addr_test1abc",
  assetUnit: "lovelace",
  amountBaseUnits: "123456789012345678901234567890",
  state: "created",
  expiresAt: "2099-01-01T00:00:00Z",
};
const resp = (status, body) => ({ status, ok: status < 300, json: async () => body });

test("loadConfig fails fast without env", () => {
  assert.throws(() => loadConfig({}), /API_BASE_URL, TERMINAL_API_KEY/);
  assert.equal(loadConfig({ API_BASE_URL: "https://a/", TERMINAL_API_KEY: "k" }).baseUrl, "https://a");
});

test("value2 is amountBaseUnits verbatim", () => {
  const v = paymentValues(pay);
  assert.equal(v.value2, pay.amountBaseUnits);
  assert.equal(v.value4, pay.paymentId);
});

test("pending-payment parsing and Bearer auth", async () => {
  let seen;
  const f = async (url, o) => ((seen = [url, o.headers.Authorization]), resp(200, pay));
  assert.deepEqual(await fetchPending(cfg, f), pay);
  assert.deepEqual(seen, ["http://x/terminal/pending-payment", "Bearer k"]);
  assert.equal(await fetchPending(cfg, async () => resp(204)), null);
  await assert.rejects(fetchPending(cfg, async () => resp(200, { ...pay, amountBaseUnits: 5 })), /amountBaseUnits/);
});

test("session ends on terminal states", async () => {
  for (const end of ["confirmed", "failed", "expired"]) {
    const states = ["submitted", end];
    const f = async () => resp(200, { state: states.shift() });
    assert.equal(await watchPayment(cfg, pay, { fetchFn: f, log() {} }), end);
  }
});

test("session ends at expiresAt", async () => {
  const f = async () => resp(200, { state: "created" });
  const p = { ...pay, expiresAt: new Date(1000).toISOString() };
  let t = 0;
  const r = await watchPayment(cfg, p, { fetchFn: f, now: () => (t += 600), log() {} });
  assert.equal(r, "expired");
});

test("loadConfig refuses cleartext http except on localhost (the device key rides on every request)", () => {
  assert.throws(() => loadConfig({ API_BASE_URL: "http://api.example", TERMINAL_API_KEY: "k" }), /https/);
  assert.equal(loadConfig({ API_BASE_URL: "http://localhost:3001", TERMINAL_API_KEY: "k" }).baseUrl, "http://localhost:3001");
});

test("requests carry a timeout, so a hung poll cannot block the terminal", async () => {
  let o;
  await fetchPending(cfg, async (_u, opts) => ((o = opts), resp(204)));
  assert.ok(o.signal instanceof AbortSignal);
});

test("an authorized payment is followed past expiresAt (only `created` expires locally)", async () => {
  const states = ["authorized", "submitted", "confirmed"];
  const f = async () => resp(200, { state: states.shift() });
  const p = { ...pay, expiresAt: new Date(0).toISOString() };
  let t = 0; // authorized just before the deadline, then the clock runs past it
  assert.equal(await watchPayment(cfg, p, { fetchFn: f, now: () => (t += 4000), log() {} }), "confirmed");
});

test("exclusive: overlapping interval ticks never run two sessions", async () => {
  let runs = 0;
  let release;
  const tick = exclusive(() => ((runs += 1), new Promise((r) => (release = r))));
  const first = tick();
  await tick();
  assert.equal(runs, 1);
  release();
  await first;
  const again = tick();
  release();
  await again;
  assert.equal(runs, 2);
});
