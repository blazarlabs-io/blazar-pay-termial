const bleno = require("bleno");
const txpipe = require("./services");

const SERVICE_UUID = "1d4ddcb2-279d-42e2-a95a-274352a25248";
const VALUE1_CHARACTERISTIC_UUID = "a781af9a-9a04-4422-9d78-9014497ccdc0";
const VALUE2_CHARACTERISTIC_UUID = "61b64163-35fa-438a-810c-018d1a719667";
const VALUE3_CHARACTERISTIC_UUID = "52f34145-0363-4f4e-9fab-a133e8e5b0b1";
const WRITE1_CHARACTERISTIC_UUID = "9b16159d-7c3e-4ae6-990b-0d34f22389bb";

const BlenoCharacteristic = bleno.Characteristic;

function buildPaymentResult(payRes, clientAddress, merchantAddress, humanAmount) {
  const txHash =
    payRes?.txHash ??
    payRes?.transactionId ??
    payRes?.fundsUtxoRef?.txHash ??
    (Array.isArray(payRes?.fundsInL2) ? payRes.fundsInL2[0]?.txHash : undefined);

  return {
    clientAddress,
    merchantAddress,
    amount: humanAmount,
    fundsInL2: {
      ...payRes,
      fundsUtxoRef: {
        txHash: txHash ?? "",
      },
    },
  };
}

async function reportComplete(paymentId, payload) {
  const { MERCHANT_BASE_URL, releaseSession } = require("./index");
  try {
    const res = await fetch(
      `${MERCHANT_BASE_URL}/api/terminal/payment-complete`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ paymentId, ...payload }),
      },
    );
    if (!res.ok) {
      console.error("[report] non-OK", res.status, await res.text());
    } else {
      console.log("[report] payment-complete acked");
    }
  } catch (err) {
    console.error("[report] error:", err.message);
  } finally {
    releaseSession();
  }
}

const setupCharacteristics = (data) => {
  const { paymentId } = data;
  const decimals = Number.isFinite(Number(data.decimals)) ? Number(data.decimals) : 6;
  const humanAmount = Number(data.amount);
  const lovelace = Math.round(humanAmount * 10 ** decimals);

  const rawValue1 = String(data.address);
  const rawValue2 = String(lovelace);
  const rawValue3 = String(data.assetUnit || "lovelace");

  const value1 = Buffer.from(rawValue1, "utf8");
  const value2 = Buffer.from(rawValue2, "utf8");
  const value3 = Buffer.from(rawValue3, "utf8");

  console.log(
    "[chars] paymentId=", paymentId,
    "merchant=", rawValue1,
    "amountLovelace=", rawValue2,
    "asset=", rawValue3,
    "decimals=", decimals,
  );

  let handled = false;

  const Char1 = new BlenoCharacteristic({
    uuid: VALUE1_CHARACTERISTIC_UUID,
    properties: ["read"],
    value: value1,
    onReadRequest: (offset, callback) =>
      callback(BlenoCharacteristic.RESULT_SUCCESS, value1),
  });

  const Char2 = new BlenoCharacteristic({
    uuid: VALUE2_CHARACTERISTIC_UUID,
    properties: ["read"],
    value: value2,
    onReadRequest: (offset, callback) =>
      callback(BlenoCharacteristic.RESULT_SUCCESS, value2),
  });

  const Char4 = new BlenoCharacteristic({
    uuid: VALUE3_CHARACTERISTIC_UUID,
    properties: ["read"],
    value: value3,
    onReadRequest: (offset, callback) =>
      callback(BlenoCharacteristic.RESULT_SUCCESS, value3),
  });

  const Char3 = new BlenoCharacteristic({
    uuid: WRITE1_CHARACTERISTIC_UUID,
    properties: ["read", "write"],
    onWriteRequest: (rawData, offset, withoutResponse, callback) => {
      try {
        const clientAddress = rawData.toString("utf8").trim();
        console.log("🖊️ BLE Client wrote:", clientAddress);
        callback(BlenoCharacteristic.RESULT_SUCCESS);

        if (handled) return;
        handled = true;

        txpipe
          .queryFunds(clientAddress)
          .then((res) => {
            console.log("[QUERY-FUND RES]", res);
            const utxo = res?.fundsInL2?.[0];
            if (!utxo) {
              throw new Error("No L2 funds available for client wallet");
            }
            return txpipe.payMerchant(
              clientAddress,
              rawValue1,
              rawValue2,
              utxo.txHash,
              utxo.outputIndex,
              rawValue3,
            );
          })
          .then((payRes) => {
            console.log("[PAY-MERCHANT RES]", payRes);
            return reportComplete(paymentId, {
              result: buildPaymentResult(
                payRes,
                clientAddress,
                rawValue1,
                humanAmount,
              ),
            });
          })
          .catch((error) => {
            console.error("[payment] error:", error);
            return reportComplete(paymentId, {
              error: String(error?.message ?? error),
            });
          });
      } catch (error) {
        console.error("❌ Error parsing data:", error);
        callback(BlenoCharacteristic.RESULT_UNLIKELY_ERROR);
        if (!handled) {
          handled = true;
          void reportComplete(paymentId, {
            error: String(error?.message ?? error),
          });
        }
      }
    },
  });

  return { Char1, Char2, Char3, Char4 };
};

module.exports = {
  setupCharacteristics,
  SERVICE_UUID,
};
