const crypto = require('crypto');

// Bỏ 0/O, 1/I/L để đọc mã hẹn qua điện thoại không nhầm
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/** Sinh mã dạng `${prefix}XXXXXX` bằng crypto (không dùng Math.random). */
function generateCode(prefix, length = 6) {
  let out = '';
  for (let i = 0; i < length; i += 1) out += ALPHABET[crypto.randomInt(ALPHABET.length)];
  return `${prefix}${out}`;
}

/**
 * Tạo document có mã duy nhất, gặp trùng mã (E11000 trên đúng field) thì sinh lại.
 *   createWithCode(ServiceRequest, 'requestCode', 'SR-', { ...data }, { session })
 * Trả về document đã tạo.
 */
async function createWithCode(Model, field, prefix, data, { session, attempts = 5 } = {}) {
  for (let i = 0; i < attempts; i += 1) {
    try {
      const [doc] = await Model.create([{ ...data, [field]: generateCode(prefix) }], { session });
      return doc;
    } catch (err) {
      const dupOnField = err.code === 11000 && err.keyPattern && err.keyPattern[field];
      if (!dupOnField || i === attempts - 1) throw err;
    }
  }
  return null; // không tới được
}

module.exports = { generateCode, createWithCode, CODE_ALPHABET: ALPHABET };
