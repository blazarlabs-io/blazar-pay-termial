const bleno = require("bleno");
const sio = require("./socket");
const txpipe = require("./services");
const { LED } = require("./led");
const SERVICE_UUID = "1d4ddcb2-279d-42e2-a95a-274352a25248";
const VALUE1_CHARACTERISTIC_UUID = "a781af9a-9a04-4422-9d78-9014497ccdc0";
const VALUE2_CHARACTERISTIC_UUID = "61b64163-35fa-438a-810c-018d1a719667";
const VALUE3_CHARACTERISTIC_UUID = "52f34145-0363-4f4e-9fab-a133e8e5b0b1";
const WRITE1_CHARACTERISTIC_UUID = "9b16159d-7c3e-4ae6-990b-0d34f22389bb";

const setupCharacteristics = (data) => {
  const BlenoPrimaryService = bleno.PrimaryService;
  const BlenoCharacteristic = bleno.Characteristic;

  // const DEVICE_NAME = "Hydra TERM";
  const multiplier = 10 ** data.decimals;
  const value = parseInt(data.amount * multiplier);

  const rawValue1 = data.address;
  const rawValue2 = value.toString();
  const rawValue3 = data.assetUnit;

  const value1 = Buffer.from(rawValue1);
  const value2 = Buffer.from(rawValue2);
  const value3 = Buffer.from(rawValue3);

  console.log(
    "\n\n",
    rawValue1,
    rawValue2,
    rawValue3,
    data.decimals,
    multiplier,
    value,
    "\n\n"
  );

  const Char1 = new BlenoCharacteristic({
    uuid: VALUE1_CHARACTERISTIC_UUID,
    properties: ["read"],
    value: value1,
    onReadRequest: (offset, callback) => callback(this.RESULT_SUCCESS, value1),
  });

  const Char2 = new BlenoCharacteristic({
    uuid: VALUE2_CHARACTERISTIC_UUID,
    properties: ["read"],
    value: value2,
    onReadRequest: (offset, callback) => callback(this.RESULT_SUCCESS, value2),
  });

  const Char3 = new BlenoCharacteristic({
    uuid: WRITE1_CHARACTERISTIC_UUID, // New UUID
    properties: ["read", "write"],
    onWriteRequest: (data, offset, withoutResponse, callback) => {
      try {
        const clientAddress = data.toString("utf8");
        console.log("🖊️ BLE Client wrote:", clientAddress);
        txpipe
          .queryFunds(clientAddress)
          .then((res) => {
            console.log("\n\nXXXXXXXXXXXXXXXXX");
            console.log("[QUERY-FUND RES]", res);
            console.log("[CLIENT ADDRESS]", clientAddress);
            console.log("[MERCHANT ADDRESS]", rawValue1);
            console.log("[AMOUNT TO PAY]", rawValue2);
            console.log("[ASSET-INIT]", rawValue3);
            console.log("[TX-HASH]", res.fundsInL2[0].txHash);
            console.log("[INDEX]", res.fundsInL2[0].outputIndex);
            console.log("XXXXXXXXXXXXXXXXX\n\n");
            txpipe
              .payMerchant(
                clientAddress,
                rawValue1,
                rawValue2,
                res.fundsInL2[0].txHash,
                res.fundsInL2[0].outputIndex,
                rawValue3
              )
              .then((payRes) => {
                console.log("\n\nXXXXXXXXXXXXXXXXX");
                console.log("[PAY-MERCHANT RES]", payRes);
                console.log("XXXXXXXXXXXXXXXXX\n\n");
                // Send back data to Merchant
                sio.io.emit("payed", {
                  clientAddress: clientAddress,
                  merchantAddress: data.address,
                  amount: data.amount,
                  fundsInL2: payRes,
                });
                LED.finishPayment(true)
              })
              .catch((error) => {
                console.error(error);
                LED.finishPayment(false)
              });
          })
          .catch((error) => {
            console.log(error);
            LED.finishPayment(false)
          });
        callback(BlenoCharacteristic.RESULT_SUCCESS);
      } catch (error) {
        console.error("❌ Error parsing data:", error);
        callback(BlenoCharacteristic.RESULT_UNLIKELY_ERROR);
      }
    },
  });

  const Char4 = new BlenoCharacteristic({
    uuid: VALUE3_CHARACTERISTIC_UUID,
    properties: ["read"],
    value: value3,
    onReadRequest: (offset, callback) => callback(this.RESULT_SUCCESS, value3),
  });

  return { Char1, Char2, Char3, Char4 };
};

module.exports = {
  setupCharacteristics,
  SERVICE_UUID,
};
