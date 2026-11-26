// The four of bench/signatures.ce in Node's crypto, the same sizes: microseconds per call, one line per kind. Its
// KeyObjects are parsed once; the lines -der take the key as DER at each call, as std/crypto does.
//   node bench/signatures.js [n]
const crypto = require("node:crypto");
const n = Number(process.argv[2] || 2000);
const message = Buffer.from("a".repeat(400));
const rsa = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
const ec = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const rs256 = crypto.sign("sha256", message, rsa.privateKey);
const es256 = crypto.sign("sha256", message, ec.privateKey);
const seed = Buffer.from("12345678901234567890");
const counter = Buffer.from([0, 0, 0, 0, 2, 0x35, 0x23, 0xec]);

function timed(name, f) {
  for (let i = 0; i < 200; i++) f();
  const start = process.hrtime.bigint();
  for (let i = 0; i < n; i++) f();
  const us = Number(process.hrtime.bigint() - start) / 1000 / n;
  console.log(name, 0, us.toFixed(2));
}

timed("verify-rs256", () => crypto.verify("sha256", message, rsa.publicKey, rs256));
timed("verify-es256", () => crypto.verify("sha256", message, ec.publicKey, es256));
const rsaDer = { key: rsa.publicKey.export({ type: "spki", format: "der" }), format: "der", type: "spki" };
const ecDer = { key: ec.publicKey.export({ type: "spki", format: "der" }), format: "der", type: "spki" };
timed("verify-rs256-der", () => crypto.verify("sha256", message, rsaDer, rs256));
timed("verify-es256-der", () => crypto.verify("sha256", message, ecDer, es256));
timed("sign-es256", () => crypto.sign("sha256", message, ec.privateKey));
const ecSecretDer = { key: ec.privateKey.export({ type: "pkcs8", format: "der" }), format: "der", type: "pkcs8" };
timed("sign-es256-der", () => crypto.sign("sha256", message, ecSecretDer));
timed("hmac-sha1", () => crypto.createHmac("sha1", seed).update(counter).digest());
