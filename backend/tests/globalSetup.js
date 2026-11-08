const { MongoMemoryReplSet } = require('mongodb-memory-server');

/**
 * Bật một MongoDB replica set tạm trong RAM cho cả bộ test (hỗ trợ transaction).
 * Muốn chạy trên Mongo thật thì đặt MONGODB_TEST_URI, khi đó bỏ qua bước này.
 * tests/setup.js đọc MONGODB_TEST_URI để gán cho MONGODB_URI.
 */
module.exports = async () => {
  if (process.env.MONGODB_TEST_URI) return;
  const replSet = await MongoMemoryReplSet.create({ replSet: { count: 1 } });
  globalThis.__MONGO_REPLSET__ = replSet;
  process.env.MONGODB_TEST_URI = replSet.getUri('apartment_management_test');
};
