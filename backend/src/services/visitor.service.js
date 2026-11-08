const Visitor = require('../models/Visitor');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { ROLES, DEPARTMENTS, VISITOR_STATUS: VS } = require('../utils/constants');
const { assertActiveResident, myApartmentIds } = require('../shared/residency');
const { createWithCode } = require('../shared/code');
const { combineVN, dayRangeVN, parseDateVN, nowVN } = require('../shared/time');
const { notifyUsers } = require('./notify.service');

/**
 * M3 — Khách (UC-16, 17, 18). Xem docs/ke-hoach-nguoi-2.md mục 7.2.
 * Khách đến ngoài khung giờ: 409, cư dân tạo lịch mới (không có cơ chế ghi đè).
 */

const EARLY_MINUTES = 30; // cho đến sớm 30 phút
const MAX_DAYS_AHEAD = 30;

const isSecurity = (u) => u.role === ROLES.STAFF && u.department === DEPARTMENTS.SECURITY;
const isGateViewer = (u) =>
  u.role === ROLES.MANAGER ||
  (u.role === ROLES.STAFF && [DEPARTMENTS.SECURITY, DEPARTMENTS.RECEPTION].includes(u.department));

const paged = (page, limit, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit) });
const POPULATE = [
  { path: 'apartmentId', select: 'code floor' },
  { path: 'createdBy', select: 'fullName phone' },
  { path: 'checkedInBy', select: 'fullName' },
  { path: 'checkedOutBy', select: 'fullName' },
];

const computeOverdue = (v, now = new Date()) => v.status === VS.EXPECTED && v.timeTo < now;
const withOverdue = (doc) => {
  const o = typeof doc.toJSON === 'function' ? doc.toJSON() : doc;
  return { ...o, isOverdue: computeOverdue(o) };
};

async function scopeFor(actor) {
  if (isGateViewer(actor)) return {};
  if (actor.role === ROLES.RESIDENT) return { apartmentId: { $in: await myApartmentIds(actor._id) } };
  return null;
}

async function findVisibleOrThrow(actor, id) {
  const scope = await scopeFor(actor);
  const visitor = scope && (await Visitor.findOne({ _id: id, ...scope }));
  if (!visitor) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy lịch hẹn');
  return visitor;
}

function allowedActions(actor, v) {
  const actions = [];
  if (v.status === VS.EXPECTED && actor.role === ROLES.RESIDENT) actions.push('cancel');
  if (v.status === VS.EXPECTED && isSecurity(actor)) actions.push('check-in');
  if (v.status === VS.CHECKED_IN && isSecurity(actor)) actions.push('check-out');
  return actions;
}

async function stateError(id) {
  if (!(await Visitor.exists({ _id: id }))) {
    return new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy lịch hẹn');
  }
  return new AppError(ERROR_CODES.INVALID_STATE, 'Lịch hẹn đã thay đổi trạng thái, vui lòng tải lại');
}

const link = (v) => ({ kind: 'visitor', id: String(v._id) });

// ---------------------------------------------------------------- UC-16: đăng ký khách
async function create(actor, data) {
  await assertActiveResident(actor._id, data.apartmentId);
  const timeFrom = combineVN(data.visitDate, data.timeFrom);
  const timeTo = combineVN(data.visitDate, data.timeTo);
  const now = new Date();
  if (!(timeFrom < timeTo)) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Giờ đến phải trước giờ về');
  }
  if (timeTo <= now) throw new AppError(ERROR_CODES.BAD_REQUEST, 'Không đăng ký lịch trong quá khứ');
  const lastDay = nowVN().startOf('day').plus({ days: MAX_DAYS_AHEAD });
  if (parseDateVN(data.visitDate) > lastDay) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, `Chỉ đăng ký trước tối đa ${MAX_DAYS_AHEAD} ngày`);
  }

  const visitor = await createWithCode(Visitor, 'appointmentCode', 'VS-', {
    apartmentId: data.apartmentId,
    createdBy: actor._id,
    visitorName: data.visitorName,
    visitorPhone: data.visitorPhone,
    numberOfPeople: data.numberOfPeople,
    vehiclePlate: data.vehiclePlate,
    note: data.note,
    visitDate: parseDateVN(data.visitDate).toJSDate(),
    timeFrom,
    timeTo,
  });
  return withOverdue(visitor);
}

async function listMine(actor, { page, limit, status }) {
  const filter = { apartmentId: { $in: await myApartmentIds(actor._id) } };
  if (status) filter.status = status;
  const [items, total] = await Promise.all([
    Visitor.find(filter)
      .populate('apartmentId', 'code floor')
      .sort({ timeFrom: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    Visitor.countDocuments(filter),
  ]);
  return { items: items.map(withOverdue), meta: paged(page, limit, total) };
}

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// ---------------------------------------------------------------- UC-17: danh sách tại cổng
/**
 * Mặc định khách hôm nay (giờ VN). Tìm theo mã hẹn thì bỏ qua ngày (khách đọc mã là ra).
 */
async function listForGate({ page, limit, date, code, phone, status }) {
  const filter = {};
  if (code) {
    filter.appointmentCode = code.trim().toUpperCase();
  } else {
    const range = dayRangeVN(date);
    if (!range) throw new AppError(ERROR_CODES.BAD_REQUEST, 'Ngày không hợp lệ (YYYY-MM-DD)');
    filter.visitDate = { $gte: range.start, $lt: range.end };
  }
  if (phone) filter.visitorPhone = new RegExp(escapeRegex(phone.trim()));
  if (status) filter.status = status;
  const [items, total] = await Promise.all([
    Visitor.find(filter)
      .populate(POPULATE)
      .sort({ timeFrom: 1 })
      .skip((page - 1) * limit)
      .limit(limit),
    Visitor.countDocuments(filter),
  ]);
  return { items: items.map(withOverdue), meta: paged(page, limit, total) };
}

async function getDetail(actor, id) {
  const visitor = await findVisibleOrThrow(actor, id);
  await visitor.populate(POPULATE);
  return { ...withOverdue(visitor), allowedActions: allowedActions(actor, visitor) };
}

// ---------------------------------------------------------------- Hủy (cư dân)
async function cancel(actor, id, reason) {
  const visitor = await findVisibleOrThrow(actor, id);
  const updated = await Visitor.findOneAndUpdate(
    { _id: visitor._id, status: VS.EXPECTED },
    { $set: { status: VS.CANCELLED, cancelReason: reason, cancelledAt: new Date() } },
    { new: true }
  );
  if (!updated) throw await stateError(id);
  return withOverdue(updated);
}

// ---------------------------------------------------------------- UC-17, 18: check-in / out
async function checkIn(actor, id) {
  const visitor = await Visitor.findById(id);
  if (!visitor) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy lịch hẹn');
  if (visitor.status !== VS.EXPECTED) throw await stateError(id);

  const now = new Date();
  const opensAt = new Date(visitor.timeFrom.getTime() - EARLY_MINUTES * 60 * 1000);
  if (now < opensAt || now > visitor.timeTo) {
    throw new AppError(
      ERROR_CODES.VISITOR_OUT_OF_WINDOW,
      'Khách đến ngoài khung giờ đã hẹn, cư dân cần tạo lịch mới'
    );
  }

  // Điều kiện trạng thái trong câu update: bấm 2 lần chỉ 1 lần thành công
  const updated = await Visitor.findOneAndUpdate(
    { _id: id, status: VS.EXPECTED },
    { $set: { status: VS.CHECKED_IN, checkInTime: now, checkedInBy: actor._id } },
    { new: true }
  );
  if (!updated) throw await stateError(id);

  await notifyUsers({
    userIds: [updated.createdBy],
    type: 'visitor_checked_in',
    title: `Khách ${updated.visitorName} đã đến`,
    body: `${updated.numberOfPeople} người · mã ${updated.appointmentCode}`,
    link: link(updated),
  });
  return withOverdue(updated);
}

async function checkOut(actor, id) {
  const updated = await Visitor.findOneAndUpdate(
    { _id: id, status: VS.CHECKED_IN },
    { $set: { status: VS.CHECKED_OUT, checkOutTime: new Date(), checkedOutBy: actor._id } },
    { new: true }
  );
  if (!updated) throw await stateError(id);

  await notifyUsers({
    userIds: [updated.createdBy],
    type: 'visitor_checked_out',
    title: `Khách ${updated.visitorName} đã ra về`,
    body: `Mã ${updated.appointmentCode}`,
    link: link(updated),
  });
  return withOverdue(updated);
}

module.exports = {
  EARLY_MINUTES,
  computeOverdue,
  create,
  listMine,
  listForGate,
  getDetail,
  cancel,
  checkIn,
  checkOut,
};
