const API_BASE_URL =
  process.env.HYDRA_API_URL ||
  process.env.HYDRA_API_BASE_URL ||
  "https://blazar-api.cardano.vip";

async function queryFunds(address) {
  const response = await fetch(
    `${API_BASE_URL}/query-funds?address=${encodeURIComponent(address)}`,
  );
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`query-funds ${response.status}: ${text.slice(0, 200)}`);
  }
  return response.json();
}

async function payMerchant(
  clientAddress,
  merchantAddress,
  amountToPay,
  txHash,
  outputIndex,
  assetUnit,
) {
  const payload = {
    merchant_address: merchantAddress,
    funds_utxo_ref: {
      hash: txHash,
      index: outputIndex,
    },
    amount: [
      [assetUnit, parseInt(amountToPay, 10)],
      ["lovelace", 3000000],
    ],
    signature: "",
  };
  const response = await fetch(`${API_BASE_URL}/pay-merchant`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`pay-merchant ${response.status}: ${text.slice(0, 200)}`);
  }
  return response.json();
}

module.exports = {
  API_BASE_URL,
  queryFunds,
  payMerchant,
};
