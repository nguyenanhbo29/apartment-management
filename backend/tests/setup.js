process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-secret';
process.env.MONGODB_URI =
  process.env.MONGODB_TEST_URI || 'mongodb://127.0.0.1:27017/apartment_management_test';
// Ảnh upload khi test ghi vào thư mục tạm, không lẫn vào backend/uploads
process.env.UPLOAD_DIR = require('path').join(require('os').tmpdir(), 'apartment-test-uploads');
