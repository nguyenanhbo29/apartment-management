const Notification = require('../models/Notification');

/**
 * Interface dùng chung cho MỌI module (chốt với Người 2):
 *   notifyUsers({ userIds, type, title, body, link })
 *   - userIds: mảng id người nhận (tự loại trùng, bỏ giá trị rỗng)
 *   - type:    mã sự kiện, vd 'fee_issued', 'request_status_changed'
 *   - title/body: nội dung hiển thị
 *   - link:    { kind, id } trỏ tới dữ liệu mà người nhận có quyền xem
 * Trả về mảng notification đã tạo. Không ném lỗi ra ngoài để không làm hỏng
 * nghiệp vụ chính: lỗi gửi thông báo chỉ được log.
 */
async function notifyUsers({ userIds, type, title, body = '', link }) {
  const ids = [...new Set((userIds || []).filter(Boolean).map(String))];
  if (!ids.length) return [];
  try {
    return await Notification.insertMany(ids.map((userId) => ({ userId, type, title, body, link })));
  } catch (err) {
    console.error('[notifyUsers] failed:', err.message);
    return [];
  }
}

module.exports = { notifyUsers };
