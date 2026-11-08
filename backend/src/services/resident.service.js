const ApartmentResident = require('../models/ApartmentResident');
const Apartment = require('../models/Apartment');
const User = require('../models/User');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { ROLES, USER_STATUS, RESIDENT_RELATION, RESIDENT_STATUS } = require('../utils/constants');
const apartmentService = require('./apartment.service');
const { notifyUsers } = require('./notify.service');
const { onResidentMovedOut } = require('./operationsHooks');

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const RELATION_LABEL = { owner: 'chủ hộ', member: 'thành viên', tenant: 'người thuê' };

async function findOrThrow(id) {
  const rec = await ApartmentResident.findById(id);
  if (!rec) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy hồ sơ cư trú');
  return rec;
}

const ownerConflict = () =>
  new AppError(ERROR_CODES.CONFLICT, 'Căn hộ đã có chủ hộ đang hiệu lực');

/** Lưu hồ sơ; đổi lỗi trùng index chủ hộ thành thông báo dễ hiểu. */
async function saveRecord(rec) {
  try {
    await rec.save();
  } catch (err) {
    if (err.code === 11000) throw ownerConflict();
    throw err;
  }
  return rec;
}

async function assertNoActiveOwner(apartmentId, exceptId) {
  const exists = await ApartmentResident.exists({
    apartmentId,
    relation: RESIDENT_RELATION.OWNER,
    status: RESIDENT_STATUS.ACTIVE,
    ...(exceptId && { _id: { $ne: exceptId } }),
  });
  if (exists) throw ownerConflict();
}

/** Tài khoản liên kết phải là Resident đang hoạt động, chưa có hồ sơ mở ở căn này. */
async function assertLinkableUser(userId, apartmentId, exceptId) {
  const user = await User.findById(userId);
  if (!user) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy tài khoản liên kết');
  if (user.role !== ROLES.RESIDENT) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Chỉ liên kết được tài khoản có vai trò Cư dân');
  }
  if (user.status !== USER_STATUS.ACTIVE) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Tài khoản liên kết đang bị khóa');
  }
  const dup = await ApartmentResident.exists({
    userId,
    apartmentId,
    status: { $in: [RESIDENT_STATUS.ACTIVE, RESIDENT_STATUS.PENDING] },
    ...(exceptId && { _id: { $ne: exceptId } }),
  });
  if (dup) {
    throw new AppError(ERROR_CODES.CONFLICT, 'Tài khoản này đã có hồ sơ cư trú ở căn hộ này');
  }
  return user;
}

/** Đặt một người làm người nộp phí duy nhất của căn hộ. */
async function makePayer(rec) {
  await ApartmentResident.updateMany(
    { apartmentId: rec.apartmentId, _id: { $ne: rec._id }, isPayer: true },
    { isPayer: false }
  );
  rec.isPayer = true;
  await rec.save();
}

/** Nếu căn hộ chưa có người nộp phí, mặc định giao cho chủ hộ đang ở. */
async function ensureDefaultPayer(apartmentId) {
  const hasPayer = await ApartmentResident.exists({
    apartmentId,
    status: RESIDENT_STATUS.ACTIVE,
    isPayer: true,
  });
  if (hasPayer) return;
  await ApartmentResident.updateOne(
    { apartmentId, status: RESIDENT_STATUS.ACTIVE, relation: RESIDENT_RELATION.OWNER },
    { isPayer: true }
  );
}

const managerIds = async () =>
  (await User.find({ role: ROLES.MANAGER, status: USER_STATUS.ACTIVE }).select('_id')).map(
    (u) => u._id
  );

// ---------------------------------------------------------------- UC-12
/**
 * Danh sách người cư trú của căn hộ.
 * - Manager/Accountant/Lễ tân: mọi trạng thái (mặc định active)
 * - Chủ hộ: active, pending, rejected (để theo dõi đơn khai báo)
 * - Thành viên khác: chỉ active
 */
async function listByApartment(user, apartmentId, statuses) {
  const { membership } = await apartmentService.assertCanView(user, apartmentId);
  let allowed = Object.values(RESIDENT_STATUS);
  if (membership) {
    allowed =
      membership.relation === RESIDENT_RELATION.OWNER
        ? [RESIDENT_STATUS.ACTIVE, RESIDENT_STATUS.PENDING, RESIDENT_STATUS.REJECTED]
        : [RESIDENT_STATUS.ACTIVE];
  }
  const requested = statuses?.length ? statuses : [RESIDENT_STATUS.ACTIVE];
  const status = requested.filter((s) => allowed.includes(s));
  if (!status.length) {
    throw new AppError(ERROR_CODES.FORBIDDEN, 'Bạn không có quyền xem dữ liệu này');
  }

  const query = ApartmentResident.find({ apartmentId, status: { $in: status } }).sort({
    relation: 1,
    createdAt: 1,
  });
  // Resident không thấy CCCD của người khác
  if (membership) query.select('-idNumber');
  return query;
}

// ---------------------------------------------------------------- UC-08
async function searchResidents({ page, limit, q, status, relation }) {
  const filter = { status: { $in: status?.length ? status : [RESIDENT_STATUS.ACTIVE] } };
  if (relation) filter.relation = relation;
  if (q) {
    const rx = new RegExp(escapeRegex(q), 'i');
    const aptIds = await Apartment.find({ code: rx }).distinct('_id');
    filter.$or = [{ fullName: rx }, { phone: rx }, { idNumber: rx }, { apartmentId: { $in: aptIds } }];
  }
  const [items, total] = await Promise.all([
    ApartmentResident.find(filter)
      .populate('apartmentId', 'code floor')
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    ApartmentResident.countDocuments(filter),
  ]);
  return { items, meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
}

async function getRecord(id) {
  const rec = await ApartmentResident.findById(id)
    .populate('apartmentId', 'code floor')
    .populate('userId', 'email fullName status')
    .populate('registeredBy', 'fullName')
    .populate('reviewedBy', 'fullName');
  if (!rec) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy hồ sơ cư trú');
  return rec;
}

/** Manager thêm hồ sơ cư trú, có hiệu lực ngay (không cần duyệt). */
async function createRecord(actor, apartmentId, data) {
  await apartmentService.findOrThrow(apartmentId);
  if (data.relation === RESIDENT_RELATION.OWNER) await assertNoActiveOwner(apartmentId);
  if (data.userId) await assertLinkableUser(data.userId, apartmentId);

  const { isPayer, ...rest } = data;
  const rec = await saveRecord(
    new ApartmentResident({
      ...rest,
      apartmentId,
      status: RESIDENT_STATUS.ACTIVE,
      moveInDate: data.moveInDate || new Date(),
      registeredBy: actor._id,
      reviewedBy: actor._id,
      reviewedAt: new Date(),
    })
  );
  if (isPayer) await makePayer(rec);
  else await ensureDefaultPayer(apartmentId);
  await apartmentService.recomputeStatus(apartmentId);
  return ApartmentResident.findById(rec._id);
}

async function updateRecord(id, data) {
  const rec = await findOrThrow(id);
  if (rec.status === RESIDENT_STATUS.ENDED) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Hồ sơ đã kết thúc, không thể chỉnh sửa');
  }
  if (
    data.relation === RESIDENT_RELATION.OWNER &&
    rec.relation !== RESIDENT_RELATION.OWNER &&
    rec.status === RESIDENT_STATUS.ACTIVE
  ) {
    await assertNoActiveOwner(rec.apartmentId, rec._id);
  }
  if (data.userId) await assertLinkableUser(data.userId, rec.apartmentId, rec._id);

  for (const [key, value] of Object.entries(data)) {
    rec[key] = value === null ? undefined : value;
  }
  await saveRecord(rec);
  if (rec.status === RESIDENT_STATUS.ACTIVE) await ensureDefaultPayer(rec.apartmentId);
  return ApartmentResident.findById(rec._id);
}

async function setPayer(id) {
  const rec = await findOrThrow(id);
  if (rec.status !== RESIDENT_STATUS.ACTIVE) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Chỉ người đang cư trú mới được chỉ định nộp phí');
  }
  await makePayer(rec);
  return rec;
}

// ---------------------------------------------------------------- UC-09
/** Chủ hộ khai báo thành viên / người thuê -> chờ Manager duyệt. */
async function registerMember(actor, apartmentId, data) {
  const apartment = await apartmentService.findOrThrow(apartmentId);
  const membership = await apartmentService.findMembership(actor._id, apartmentId);
  if (!membership || membership.relation !== RESIDENT_RELATION.OWNER) {
    throw new AppError(ERROR_CODES.FORBIDDEN, 'Chỉ chủ hộ mới được khai báo thành viên');
  }
  const rec = await ApartmentResident.create({
    ...data,
    apartmentId,
    status: RESIDENT_STATUS.PENDING,
    source: 'registration',
    registeredBy: actor._id,
  });

  await notifyUsers({
    userIds: await managerIds(),
    type: 'resident_registration_submitted',
    title: 'Đăng ký cư trú mới',
    body: `${actor.fullName} khai báo ${RELATION_LABEL[rec.relation]} ${rec.fullName} - căn ${apartment.code}`,
    link: { kind: 'resident_registration', id: String(rec._id) },
  });
  return rec;
}

// ---------------------------------------------------------------- UC-10
async function listRegistrations({ page, limit, status }) {
  // Chỉ lấy hồ sơ do chủ hộ khai báo (hồ sơ Manager tự thêm không qua duyệt)
  const filter = { status, source: 'registration' };
  const [items, total] = await Promise.all([
    ApartmentResident.find(filter)
      .populate('apartmentId', 'code floor')
      .populate('registeredBy', 'fullName email')
      .sort({ createdAt: status === RESIDENT_STATUS.PENDING ? 1 : -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    ApartmentResident.countDocuments(filter),
  ]);
  return { items, meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
}

async function findPendingOrThrow(id) {
  const rec = await findOrThrow(id);
  if (rec.status !== RESIDENT_STATUS.PENDING) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Đơn đăng ký đã được xử lý');
  }
  return rec;
}

async function approve(actor, id) {
  const rec = await findPendingOrThrow(id);
  if (rec.relation === RESIDENT_RELATION.OWNER) await assertNoActiveOwner(rec.apartmentId);
  rec.status = RESIDENT_STATUS.ACTIVE;
  rec.moveInDate = rec.moveInDate || new Date();
  rec.reviewedBy = actor._id;
  rec.reviewedAt = new Date();
  await saveRecord(rec);
  await ensureDefaultPayer(rec.apartmentId);
  await apartmentService.recomputeStatus(rec.apartmentId);

  const apt = await Apartment.findById(rec.apartmentId);
  await notifyUsers({
    userIds: [rec.registeredBy, rec.userId],
    type: 'resident_registration_approved',
    title: 'Đăng ký cư trú đã được duyệt',
    body: `${rec.fullName} đã được ghi nhận là ${RELATION_LABEL[rec.relation]} căn ${apt?.code}`,
    link: { kind: 'apartment', id: String(rec.apartmentId) },
  });
  return rec;
}

async function reject(actor, id, reason) {
  const rec = await findPendingOrThrow(id);
  rec.status = RESIDENT_STATUS.REJECTED;
  rec.rejectReason = reason;
  rec.reviewedBy = actor._id;
  rec.reviewedAt = new Date();
  await rec.save();

  const apt = await Apartment.findById(rec.apartmentId);
  await notifyUsers({
    userIds: [rec.registeredBy],
    type: 'resident_registration_rejected',
    title: 'Đăng ký cư trú bị từ chối',
    body: `Đăng ký ${rec.fullName} - căn ${apt?.code} bị từ chối. Lý do: ${reason}`,
    link: { kind: 'apartment', id: String(rec.apartmentId) },
  });
  return rec;
}

// ---------------------------------------------------------------- UC-11
/** Ghi nhận chuyển đi: kết thúc hồ sơ, giữ lịch sử, không xóa tài khoản. */
async function moveOut(id, { moveOutDate, reason }) {
  const rec = await findOrThrow(id);
  if (rec.status !== RESIDENT_STATUS.ACTIVE) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Chỉ ghi nhận chuyển đi cho người đang cư trú');
  }
  const date = moveOutDate || new Date();
  if (rec.moveInDate && date < rec.moveInDate) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Ngày chuyển đi không được trước ngày chuyển đến');
  }
  const wasPayer = rec.isPayer;
  rec.status = RESIDENT_STATUS.ENDED;
  rec.moveOutDate = date;
  rec.moveOutReason = reason;
  rec.isPayer = false;
  await rec.save();

  if (wasPayer) await ensureDefaultPayer(rec.apartmentId);
  await apartmentService.recomputeStatus(rec.apartmentId);
  // Dọn xe, lịch khách, booking của module vận hành (không ném lỗi)
  if (rec.userId) await onResidentMovedOut(rec.apartmentId, rec.userId);
  return rec;
}

module.exports = {
  listByApartment,
  searchResidents,
  getRecord,
  createRecord,
  updateRecord,
  setPayer,
  registerMember,
  listRegistrations,
  approve,
  reject,
  moveOut,
};
