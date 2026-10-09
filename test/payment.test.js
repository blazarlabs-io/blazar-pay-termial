const test = require("node:test");
const assert = require("node:assert");
const { loadConfig, paymentValues, fetchPending, watchPayment } = require("../src/payment");

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
  assert.equal(loadConfig({ API_BASE_URL: "http://a/", TERMINAL_API_KEY: "k" }).baseUrl, "http://a");
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
