const Notification = require('../models/Notification');
const { AppError, ERROR_CODES } = require('../utils/errors');

// UC-45, UC-46: người dùng chỉ thấy và thao tác thông báo của chính mình.

async function list(userId, { page, limit, unreadOnly }) {
  const filter = { userId };
  if (unreadOnly) filter.isRead = false;
  const [items, total, unread] = await Promise.all([
    Notification.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    Notification.countDocuments(filter),
    Notification.countDocuments({ userId, isRead: false }),
  ]);
  return { items, meta: { page, limit, total, totalPages: Math.ceil(total / limit), unread } };
}

const unreadCount = (userId) => Notification.countDocuments({ userId, isRead: false });

async function markRead(userId, id) {
  const n = await Notification.findOne({ _id: id, userId });
  if (!n) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy thông báo');
  if (!n.isRead) {
    n.isRead = true;
    n.readAt = new Date();
    await n.save();
  }
  return n;
}

async function markAllRead(userId) {
  const res = await Notification.updateMany(
    { userId, isRead: false },
    { isRead: true, readAt: new Date() }
  );
  return { updated: res.modifiedCount };
}

module.exports = { list, unreadCount, markRead, markAllRead };
