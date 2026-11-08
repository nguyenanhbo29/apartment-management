const announcementService = require('../services/announcement.service');
const notificationService = require('../services/notification.service');
const { ok, created } = require('../utils/response');

// ---- Bảng tin
exports.createAnnouncement = async (req, res) =>
  created(res, await announcementService.createAnnouncement(req.user, req.validated.body));

exports.listAnnouncements = async (req, res) => {
  const { items, meta } = await announcementService.listAnnouncements(
    req.user,
    req.validated.query
  );
  ok(res, items, meta);
};

exports.getAnnouncement = async (req, res) =>
  ok(res, await announcementService.getAnnouncement(req.user, req.params.id));

exports.pinAnnouncement = async (req, res) =>
  ok(res, await announcementService.setPinned(req.params.id, req.validated.body.isPinned));

exports.removeAnnouncement = async (req, res) =>
  ok(res, await announcementService.removeAnnouncement(req.user, req.params.id));

// ---- Thông báo
exports.listNotifications = async (req, res) => {
  const { items, meta } = await notificationService.list(req.user._id, req.validated.query);
  ok(res, items, meta);
};

exports.unreadCount = async (req, res) =>
  ok(res, { count: await notificationService.unreadCount(req.user._id) });

exports.markRead = async (req, res) =>
  ok(res, await notificationService.markRead(req.user._id, req.params.id));

exports.markAllRead = async (req, res) =>
  ok(res, await notificationService.markAllRead(req.user._id));
