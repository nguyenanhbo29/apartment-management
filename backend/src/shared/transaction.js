const mongoose = require('mongoose');

/**
 * Chạy fn(session) trong một MongoDB transaction, trả về kết quả của fn.
 * withTransaction tự thử lại khi gặp lỗi tạm thời (TransientTransactionError).
 *
 * Transaction cần replica set (Atlas, `npm run db`, mongodb-memory-server khi test).
 * Với MongoDB standalone (cài mặc định, cổng 27017) thì chạy fn(null) không transaction
 * để app vẫn dùng được khi dev; nếu fn lỗi giữa chừng thì gọi `compensate()` (nếu có)
 * để hoàn tác thủ công phần đã ghi. Chế độ này chỉ dành cho dev: production phải dùng replica set.
 */
let supported; // cache theo kết nối

async function supportsTransactions() {
  if (supported === undefined) {
    const hello = await mongoose.connection.db.admin().command({ hello: 1 });
    supported = Boolean(hello.setName || hello.msg === 'isdbgrid');
    if (!supported) {
      console.warn(
        '[transaction] MongoDB standalone: chạy KHÔNG transaction (chỉ nên dùng khi dev). ' +
          'Dùng `npm run db` hoặc replica set để có transaction.'
      );
    }
  }
  return supported;
}

async function withTransaction(fn, { compensate } = {}) {
  if (!(await supportsTransactions())) {
    try {
      return await fn(null);
    } catch (err) {
      if (compensate) await compensate().catch(() => {});
      throw err;
    }
  }
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

mongoose.connection.on('disconnected', () => {
  supported = undefined;
});

/** Chỉ dùng trong test: ép chế độ có / không transaction (undefined = tự dò lại). */
function _setTransactionSupport(value) {
  supported = value;
}

module.exports = { withTransaction, _setTransactionSupport };
