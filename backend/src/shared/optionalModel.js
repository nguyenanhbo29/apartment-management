const mongoose = require('mongoose');

/**
 * Lấy model theo tên nếu đã được đăng ký, chưa có thì trả null.
 * Dùng khi code chạy trước lúc module tương ứng được viết (vd ServiceRequest của M5),
 * để không phải require file chưa tồn tại.
 */
const optionalModel = (name) => mongoose.models[name] || null;

module.exports = { optionalModel };
