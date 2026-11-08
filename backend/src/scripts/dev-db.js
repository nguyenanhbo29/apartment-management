/* eslint-disable no-console */
const path = require('path');
const { MongoMemoryReplSet } = require('mongodb-memory-server');

/**
 * MongoDB replica set cho dev / demo (cần cho transaction), KHÔNG cần cài Mongo hay quyền admin.
 * Dùng binary mongod do mongodb-memory-server tải sẵn; dữ liệu lưu ở backend/.mongo-data
 * nên tắt / bật lại vẫn còn.
 *
 *   npm run db          # giữ cửa sổ này mở
 *   .env: MONGODB_URI=mongodb://127.0.0.1:27018/apartment_management?replicaSet=rs0
 *
 * Đổi cổng: DEV_DB_PORT=27019 npm run db
 */
const port = Number(process.env.DEV_DB_PORT || 27018);
const dbPath = path.resolve(__dirname, '../../.mongo-data');

(async () => {
  require('fs').mkdirSync(dbPath, { recursive: true });
  const replSet = await MongoMemoryReplSet.create({
    replSet: { name: 'rs0', count: 1, storageEngine: 'wiredTiger' },
    instanceOpts: [{ port, dbPath, storageEngine: 'wiredTiger' }],
  });
  const uri = `mongodb://127.0.0.1:${port}/apartment_management?replicaSet=rs0`;
  console.log('MongoDB replica set đang chạy (Ctrl+C để tắt)');
  console.log(`  dữ liệu: ${dbPath}`);
  console.log(`  MONGODB_URI=${uri}`);

  const stop = async () => {
    // doCleanup: false -> giữ nguyên thư mục dữ liệu
    await replSet.stop({ doCleanup: false });
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
})().catch((err) => {
  console.error('Không khởi động được MongoDB:', err.message);
  process.exit(1);
});
