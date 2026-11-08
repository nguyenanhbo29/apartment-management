const Amenity = require('../models/Amenity');
const AmenitySlot = require('../models/AmenitySlot');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { ROLES, AMENITY_STATUS } = require('../utils/constants');
const { parseDateVN, nowVN, minutesOf } = require('../shared/time');

/**
 * M6 — Tiện ích (UC-35) và sinh slot (UC-36). Xem docs/ke-hoach-nguoi-2.md mục 8.
 */

const MAX_DAYS_AHEAD = 30;

function assertValidSchedule({ openTime, closeTime, slotDuration }) {
  const open = minutesOf(openTime);
  const close = minutesOf(closeTime);
  if (!(open < close)) throw new AppError(ERROR_CODES.BAD_REQUEST, 'Giờ mở phải trước giờ đóng');
  if (close - open < slotDuration) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Khung giờ mở cửa ngắn hơn thời lượng một slot');
  }
}

async function findOrThrow(id) {
  const amenity = await Amenity.findById(id);
  if (!amenity) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy tiện ích');
  return amenity;
}

/** Cư dân / nhân viên chỉ thấy tiện ích đang mở; Manager thấy cả tiện ích tạm ngưng. */
async function findVisibleOrThrow(actor, id) {
  const amenity = await findOrThrow(id);
  if (amenity.status !== AMENITY_STATUS.ACTIVE && actor.role !== ROLES.MANAGER) {
    throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy tiện ích');
  }
  return amenity;
}

const list = (actor, { includeInactive }) => {
  const filter =
    includeInactive && actor.role === ROLES.MANAGER ? {} : { status: AMENITY_STATUS.ACTIVE };
  return Amenity.find(filter).sort({ status: 1, name: 1 });
};

async function create(actor, data) {
  assertValidSchedule(data);
  return Amenity.create({ ...data, createdBy: actor._id });
}

/** Thay đổi chỉ áp dụng cho booking mới; booking cũ giữ nguyên giờ và quy định hủy. */
async function update(id, data) {
  const amenity = await findOrThrow(id);
  assertValidSchedule({ ...amenity.toObject(), ...data });
  Object.assign(amenity, data);
  await amenity.save();
  return amenity;
}

/** Vô hiệu hóa chỉ chặn đặt mới; booking đã có do Manager tự xử lý. */
async function setStatus(id, status) {
  const amenity = await findOrThrow(id);
  amenity.status = status;
  await amenity.save();
  return amenity;
}

// ---------------------------------------------------------------- UC-36: slot
/** Các slot của ngày (giờ VN): [{ start: Date, end: Date }]. */
function generateSlots(amenity, dateStr) {
  const day = parseDateVN(dateStr);
  if (!day) return [];
  const open = minutesOf(amenity.openTime);
  const close = minutesOf(amenity.closeTime);
  const slots = [];
  for (let m = open; m + amenity.slotDuration <= close; m += amenity.slotDuration) {
    slots.push({
      start: day.plus({ minutes: m }).toJSDate(),
      end: day.plus({ minutes: m + amenity.slotDuration }).toJSDate(),
    });
  }
  return slots;
}

/** Slot có nằm trong khoảng được đặt không (tương lai, trong 30 ngày). */
function isBookableTime(start, now = new Date()) {
  const lastDay = nowVN().startOf('day').plus({ days: MAX_DAYS_AHEAD + 1 }).toJSDate();
  return start > now && start < lastDay;
}

async function getSlots(actor, id, dateStr) {
  const amenity = await findVisibleOrThrow(actor, id);
  if (!parseDateVN(dateStr)) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Ngày không hợp lệ (YYYY-MM-DD)');
  }
  const slots = generateSlots(amenity, dateStr);
  const counters = await AmenitySlot.find({
    amenityId: amenity._id,
    slotStart: { $in: slots.map((s) => s.start) },
  });
  const usedByStart = new Map(counters.map((c) => [c.slotStart.getTime(), c.used]));
  const now = new Date();
  const active = amenity.status === AMENITY_STATUS.ACTIVE;
  return slots.map(({ start, end }) => {
    const used = usedByStart.get(start.getTime()) || 0;
    // Giảm capacity sau khi đã có người đặt: slot đang vượt hiển thị còn 0 chỗ
    const remaining = Math.max(0, amenity.capacity - used);
    return { start, end, used, remaining, available: active && remaining > 0 && isBookableTime(start, now) };
  });
}

module.exports = {
  MAX_DAYS_AHEAD,
  findOrThrow,
  findVisibleOrThrow,
  list,
  create,
  update,
  setStatus,
  generateSlots,
  isBookableTime,
  getSlots,
};
