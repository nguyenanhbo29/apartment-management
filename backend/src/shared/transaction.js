const mongoose = require('mongoose');

/**
 * Chạy fn(session) trong một MongoDB transaction, trả về kết quả của fn.
 * Cần replica set (Atlas, hoặc mongodb-memory-server khi test).
 * withTransaction tự thử lại khi gặp lỗi tạm thời (TransientTransactionError).
 */
async function withTransaction(fn) {
  const session = await mongoose.startSession();
  try {
    let result;
    await session.withTransaction(async () => {
      result = await fn(session);
    });
    return result;
  } finally {
    await session.endSession();
  }
}

module.exports = { withTransaction };
