const serviceRequestService = require('../services/serviceRequest.service');

const HOUR = 60 * 60 * 1000;

/** Chạy job, lỗi chỉ ghi log để không làm sập server. */
function every(ms, name, fn) {
  const run = async () => {
    try {
      const n = await fn();
      if (n) console.log(`[job:${name}] xử lý ${n} bản ghi`);
    } catch (err) {
      console.error(`[job:${name}] lỗi:`, err.message);
    }
  };
  run();
  return setInterval(run, ms);
}

/** Khởi các job nền. Gọi từ server.js sau khi kết nối DB (không chạy khi test). */
function startJobs() {
  return [
    // M5: phiếu chờ nghiệm thu quá 7 ngày -> tự đóng
    every(HOUR, 'auto-close-requests', () => serviceRequestService.autoCloseExpired()),
  ];
}

module.exports = { startJobs };
