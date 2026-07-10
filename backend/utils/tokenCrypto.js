const crypto = require("crypto");

const ALGORITHM = "aes-256-gcm";

function getKey() {
  const raw = process.env.GMAIL_TOKEN_ENCRYPTION_KEY;
  if (!raw) {
    throw new Error("GMAIL_TOKEN_ENCRYPTION_KEY is not configured");
  }
  const key = Buffer.from(raw, "hex");
  if (key.length !== 32) {
    throw new Error("GMAIL_TOKEN_ENCRYPTION_KEY must be 32 bytes (64 hex chars)");
  }
  return key;
}

function encrypt(text) {
  const key = getKey();
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
  let encrypted = cipher.update(text, "utf8", "hex");
  encrypted += cipher.final("hex");
  const tag = cipher.getAuthTag().toString("hex");
  return `${iv.toString("hex")}:${tag}:${encrypted}`;
}

function decrypt(payload) {
  const key = getKey();
  const [ivHex, tagHex, encrypted] = payload.split(":");
  const decipher = crypto.createDecipheriv(
    ALGORITHM,
    key,
    Buffer.from(ivHex, "hex")
  );
  decipher.setAuthTag(Buffer.from(tagHex, "hex"));
  let decrypted = decipher.update(encrypted, "hex", "utf8");
  decrypted += decipher.final("utf8");
  return decrypted;
}

module.exports = { encrypt, decrypt };
