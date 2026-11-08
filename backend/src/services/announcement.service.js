const Announcement = require('../models/Announcement');
const Apartment = require('../models/Apartment');
const ApartmentResident = require('../models/ApartmentResident');
const User = require('../models/User');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { ROLES, USER_STATUS, RESIDENT_STATUS } = require('../utils/constants');
const { notifyUsers } = require('./notify.service');

/** userId của cư dân đang ở các căn hộ cho trước (tài khoản còn hoạt động). */
async function residentUserIds(apartmentIds) {
  const ids = await ApartmentResident.find({
    apartmentId: { $in: apartmentIds },
    status: RESIDENT_STATUS.ACTIVE,
    userId: { $exists: true, $ne: null },
  }).distinct('userId');
  return User.find({ _id: { $in: ids }, status: USER_STATUS.ACTIVE }).distinct('_id');
}

/** Danh sách người nhận theo đối tượng của bảng tin. */
async function resolveRecipients(audience) {
  switch (audience.type) {
    case 'all':
      return User.find({ status: USER_STATUS.ACTIVE }).distinct('_id');
    case 'roles':
      return User.find({ status: USER_STATUS.ACTIVE, role: { $in: audience.roles } }).distinct('_id');
    case 'floors': {
      const aptIds = await Apartment.find({ floor: { $in: audience.floors } }).distinct('_id');
      return residentUserIds(aptIds);
    }
    case 'apartments':
      return residentUserIds(audience.apartmentIds);
    default:
      return [];
  }
}

/** Điều kiện Mongo: bảng tin mà người dùng này thuộc đối tượng nhận. */
async function audienceFilterFor(user) {
  const or = [{ 'audience.type': 'all' }, { 'audience.type': 'roles', 'audience.roles': user.role }];
  if (user.role === ROLES.RESIDENT) {
    const aptIds = await ApartmentResident.find({
      userId: user._id,
      status: RESIDENT_STATUS.ACTIVE,
    }).distinct('apartmentId');
    if (aptIds.length) {
      const floors = await Apartment.find({ _id: { $in: aptIds } }).distinct('floor');
      or.push({ 'audience.type': 'apartments', 'audience.apartmentIds': { $in: aptIds } });
      or.push({ 'audience.type': 'floors', 'audience.floors': { $in: floors } });
    }
  }
  return { $or: or };
}

const activeFilter = () => ({
  status: 'published',
  $or: [{ expiresAt: null }, { expiresAt: { $gt: new Date() } }],
});

// ---------------------------------------------------------------- UC-43
async function createAnnouncement(actor, data) {
  if (data.audience.type === 'apartments') {
    const count = await Apartment.countDocuments({ _id: { $in: data.audience.apartmentIds } });
    if (count !== new Set(data.audience.apartmentIds).size) {
      throw new AppError(ERROR_CODES.BAD_REQUEST, 'Có căn hộ không tồn tại trong danh sách');
    }
  }
  const recipients = (await resolveRecipients(data.audience)).filter(
    (id) => String(id) !== String(actor._id)
  );
  const ann = await Announcement.create({
    ...data,
    createdBy: actor._id,
    publishedAt: new Date(),
    recipientCount: recipients.length,
  });

  await notifyUsers({
    userIds: recipients,
    type: 'announcement',
    title: `Bảng tin: ${ann.title}`,
    body: ann.content.length > 140 ? `${ann.content.slice(0, 140)}…` : ann.content,
    link: { kind: 'announcement', id: String(ann._id) },
  });
  return ann;
}

// ---------------------------------------------------------------- UC-44
async function listAnnouncements(user, { page, limit, includeInactive }) {
  const isManager = user.role === ROLES.MANAGER;
  const clauses = [];
  if (!(isManager && includeInactive)) clauses.push(activeFilter());
  if (!isManager) clauses.push(await audienceFilterFor(user));
  const filter = clauses.length ? { $and: clauses } : {};

  const [items, total] = await Promise.all([
    Announcement.find(filter)
      .populate('createdBy', 'fullName')
      .sort({ isPinned: -1, pinnedAt: -1, publishedAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    Announcement.countDocuments(filter),
  ]);
  return { items, meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
}

async function getAnnouncement(user, id) {
  const ann = await Announcement.findById(id).populate('createdBy', 'fullName');
  if (!ann) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy bảng tin');
  if (user.role === ROLES.MANAGER) return ann;

  const visible = await Announcement.exists({
    $and: [{ _id: ann._id }, activeFilter(), await audienceFilterFor(user)],
  });
  if (!visible) throw new AppError(ERROR_CODES.NOT_FOUND, 'Bảng tin không tồn tại hoặc đã được gỡ');
  return ann;
}

async function findOrThrow(id) {
  const ann = await Announcement.findById(id);
  if (!ann) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy bảng tin');
  return ann;
}

async function setPinned(id, isPinned) {
  const ann = await findOrThrow(id);
  if (ann.status === 'removed') {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Bảng tin đã được gỡ');
  }
  ann.isPinned = isPinned;
  await ann.save();
  return ann;
}

async function removeAnnouncement(actor, id) {
  const ann = await findOrThrow(id);
  if (ann.status === 'removed') {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Bảng tin đã được gỡ trước đó');
  }
  ann.status = 'removed';
  ann.isPinned = false;
  ann.removedAt = new Date();
  ann.removedBy = actor._id;
  await ann.save();
  return ann;
}

module.exports = {
  resolveRecipients,
  createAnnouncement,
  listAnnouncements,
  getAnnouncement,
  setPinned,
  removeAnnouncement,
};
