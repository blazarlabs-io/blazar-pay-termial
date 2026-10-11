const bleno = require("bleno");
const { paymentValues } = require("./payment");

const SERVICE_UUID = "1d4ddcb2-279d-42e2-a95a-274352a25248";
const UUIDS = [
  "a781af9a-9a04-4422-9d78-9014497ccdc0", // value1 merchantAddress
  "61b64163-35fa-438a-810c-018d1a719667", // value2 amountBaseUnits
  "52f34145-0363-4f4e-9fab-a133e8e5b0b1", // value3 assetUnit
  "44f2e2a5-f323-44a2-bfbb-4afe3ef2b3ba", // value4 paymentId
];

const BlenoCharacteristic = bleno.Characteristic;

// Returns [Char1..Char4], all read-only.
const setupCharacteristics = (payment) => {
  const v = paymentValues(payment);
  console.log("[chars]", v);
  return Object.values(v).map((s, i) => {
    const value = Buffer.from(s, "utf8");
    return new BlenoCharacteristic({
      uuid: UUIDS[i],
      properties: ["read"],
      value,
      onReadRequest: (offset, cb) =>
        cb(BlenoCharacteristic.RESULT_SUCCESS, value.slice(offset)),
    });
  });
};

module.exports = { setupCharacteristics, SERVICE_UUID };
