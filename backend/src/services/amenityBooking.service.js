const AmenityBooking = require('../models/AmenityBooking');
const AmenitySlot = require('../models/AmenitySlot');
const User = require('../models/User');
const amenityService = require('./amenity.service');
const { AppError, ERROR_CODES } = require('../utils/errors');
const {
  ROLES,
  DEPARTMENTS,
  USER_STATUS,
  AMENITY_STATUS,
  BOOKING_STATUS: B,
} = require('../utils/constants');
const { assertActiveResident, myApartmentIds } = require('../shared/residency');
const { withTransaction } = require('../shared/transaction');
const { combineVN, parseDateVN, toVN } = require('../shared/time');
const { notifyUsers } = require('./notify.service');

/**
 * M6 — Đặt tiện ích (UC-37 → 39). Xem docs/ke-hoach-nguoi-2.md mục 8.2.
 *
 * Chống vượt sức chứa: đếm rồi ghi là sai (2 request cùng thấy còn chỗ).
 * Mỗi slot có 1 document AmenitySlot; giữ chỗ = update có điều kiện
 * `used <= capacity - people` trong cùng transaction với việc tạo booking.
 * Hủy / từ chối: đổi trạng thái có điều kiện + trả chỗ trong cùng transaction.
 */

const ACTIVE = [B.PENDING, B.CONFIRMED];
const HOUR = 60 * 60 * 1000;

const isFacility = (u) => u.role === ROLES.STAFF && u.department === DEPARTMENTS.FACILITY;
const canViewAll = (u) => isFacility(u) || u.role === ROLES.MANAGER;
const sameId = (a, b) => a != null && b != null && String(a) === String(b);

const paged = (page, limit, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit) });
const POPULATE = [
  { path: 'amenityId', select: 'name location capacity requiresApproval' },
  { path: 'apartmentId', select: 'code floor' },
  { path: 'bookedBy', select: 'fullName phone' },
  { path: 'reviewedBy', select: 'fullName' },
];
const link = (b) => ({ kind: 'amenity_booking', id: String(b._id) });

/** Hạn hủy = startTime − cancelDeadlineHours (chụp lại lúc đặt). */
const cancelDeadline = (b) => new Date(b.startTime.getTime() - (b.cancelDeadlineHours || 0) * HOUR);

function decorate(doc) {
  const o = typeof doc.toJSON === 'function' ? doc.toJSON() : doc;
  return { ...o, cancelDeadline: cancelDeadline(o) };
}

function allowedActions(actor, b, now = new Date()) {
  const actions = [];
  if (b.status === B.PENDING && isFacility(actor)) actions.push('approve', 'reject');
  // Ban quản lý hủy khi có sự cố: lượt chưa kết thúc, không phụ thuộc hạn hủy
  if (ACTIVE.includes(b.status) && canViewAll(actor) && b.endTime > now) {
    actions.push('cancel-by-staff');
  }
  if (ACTIVE.includes(b.status) && sameId(b.bookedBy?._id ?? b.bookedBy, actor._id) && now <= cancelDeadline(b)) {
    actions.push('cancel');
  }
  return actions;
}

async function scopeFor(actor) {
  if (canViewAll(actor)) return {};
  if (actor.role === ROLES.RESIDENT) return { apartmentId: { $in: await myApartmentIds(actor._id) } };
  return null;
}

async function findVisibleOrThrow(actor, id) {
  const scope = await scopeFor(actor);
  const booking = scope && (await AmenityBooking.findOne({ _id: id, ...scope }));
  if (!booking) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy lượt đặt');
  return booking;
}

async function stateError(id) {
  if (!(await AmenityBooking.exists({ _id: id }))) {
    return new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy lượt đặt');
  }
  return new AppError(ERROR_CODES.INVALID_STATE, 'Lượt đặt đã thay đổi trạng thái, vui lòng tải lại');
}

const activeFacilityIds = async () =>
  (
    await User.find({
      role: ROLES.STAFF,
      department: DEPARTMENTS.FACILITY,
      status: USER_STATUS.ACTIVE,
    }).select('_id')
  ).map((u) => u._id);

// ---------------------------------------------------------------- Giữ / trả chỗ
/** Bước 1, ngoài transaction: đảm bảo document slot tồn tại (E11000 = request khác vừa tạo). */
async function ensureSlot(amenityId, slotStart) {
  try {
    await AmenitySlot.updateOne(
      { amenityId, slotStart },
      { $setOnInsert: { used: 0 } },
      { upsert: true }
    );
  } catch (err) {
    if (err.code !== 11000) throw err;
  }
}

/** Bước 2, trong transaction: chỉ tăng khi còn đủ chỗ. */
async function reserveSlot({ amenity, slotStart, people }, session) {
  const slot = await AmenitySlot.findOneAndUpdate(
    { amenityId: amenity._id, slotStart, used: { $lte: amenity.capacity - people } },
    { $inc: { used: people } },
    { new: true, session }
  );
  if (!slot) throw new AppError(ERROR_CODES.SLOT_FULL, 'Khung giờ đã đầy, vui lòng chọn khung khác');
}

const releaseSlot = (booking, session) =>
  AmenitySlot.updateOne(
    { amenityId: booking.amenityId, slotStart: booking.startTime },
    { $inc: { used: -booking.numberOfParticipants } },
    { session }
  );

/**
 * Đổi trạng thái có điều kiện và (tùy chọn) trả chỗ trong cùng transaction.
 * Trả về booking sau cập nhật hoặc null nếu trạng thái đã khác.
 */
function changeStatus(id, fromStatuses, set, { release }) {
  return withTransaction(async (session) => {
    const doc = await AmenityBooking.findOneAndUpdate(
      { _id: id, status: { $in: fromStatuses } },
      { $set: set },
      { new: true, session }
    );
    if (doc && release) await releaseSlot(doc, session);
    return doc;
  });
}

// ---------------------------------------------------------------- UC-37: đặt
async function book(actor, data) {
  const amenity = await amenityService.findOrThrow(data.amenityId);
  if (amenity.status !== AMENITY_STATUS.ACTIVE) {
    throw new AppError(ERROR_CODES.INVALID_STATE, 'Tiện ích đang tạm ngưng');
  }
  await assertActiveResident(actor._id, data.apartmentId);

  const slotStart = combineVN(data.date, data.startTime);
  const slot = amenityService
    .generateSlots(amenity, data.date)
    .find((s) => slotStart && s.start.getTime() === slotStart.getTime());
  if (!slot) throw new AppError(ERROR_CODES.BAD_REQUEST, 'Khung giờ không hợp lệ');
  if (!amenityService.isBookableTime(slot.start)) {
    throw new AppError(
      ERROR_CODES.BAD_REQUEST,
      `Chỉ đặt khung giờ trong tương lai, tối đa ${amenityService.MAX_DAYS_AHEAD} ngày tới`
    );
  }
  const people = data.numberOfParticipants;
  if (people > amenity.capacity) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, `Tối đa ${amenity.capacity} người mỗi khung giờ`);
  }

  await ensureSlot(amenity._id, slot.start);
  let booking;
  try {
    booking = await withTransaction(async (session) => {
      await reserveSlot({ amenity, slotStart: slot.start, people }, session);
      const [doc] = await AmenityBooking.create(
        [
          {
            amenityId: amenity._id,
            apartmentId: data.apartmentId,
            bookedBy: actor._id,
            bookingDate: parseDateVN(data.date).toJSDate(),
            startTime: slot.start,
            endTime: slot.end,
            numberOfParticipants: people,
            note: data.note,
            status: amenity.requiresApproval ? B.PENDING : B.CONFIRMED,
            cancelDeadlineHours: amenity.cancelDeadlineHours,
          },
        ],
        { session }
      );
      return doc;
    });
  } catch (err) {
    // one_active_booking_per_apartment_slot (transaction đã rollback phần giữ chỗ)
    if (err.code === 11000) {
      throw new AppError(ERROR_CODES.BOOKING_DUPLICATE, 'Căn hộ đã có lượt đặt ở khung giờ này');
    }
    throw err;
  }

  if (booking.status === B.PENDING) {
    await notifyUsers({
      userIds: await activeFacilityIds(),
      type: 'booking_submitted',
      title: `Yêu cầu đặt ${amenity.name}`,
      body: `${actor.fullName} · ${people} người`,
      link: link(booking),
    });
  }
  return decorate(booking);
}

// ---------------------------------------------------------------- Danh sách
async function listMine(actor, { page, limit, status }) {
  const filter = { apartmentId: { $in: await myApartmentIds(actor._id) } };
  if (status) filter.status = status;
  const [items, total] = await Promise.all([
    AmenityBooking.find(filter)
      .populate(POPULATE)
      .sort({ startTime: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    AmenityBooking.countDocuments(filter),
  ]);
  return { items: items.map(decorate), meta: paged(page, limit, total) };
}

// UC-38: hàng chờ của Facility (mặc định pending, sắp theo giờ sử dụng gần nhất)
async function listForStaff({ page, limit, status, amenityId }) {
  const filter = {};
  if (status && status !== 'all') filter.status = status;
  if (amenityId) filter.amenityId = amenityId;
  const sort = status === B.PENDING ? { startTime: 1 } : { startTime: -1 };
  const [items, total] = await Promise.all([
    AmenityBooking.find(filter)
      .populate(POPULATE)
      .sort(sort)
      .skip((page - 1) * limit)
      .limit(limit),
    AmenityBooking.countDocuments(filter),
  ]);
  return { items: items.map(decorate), meta: paged(page, limit, total) };
}

async function getDetail(actor, id) {
  const booking = await findVisibleOrThrow(actor, id);
  const actions = allowedActions(actor, booking);
  await booking.populate(POPULATE);
  return { ...decorate(booking), allowedActions: actions };
}

// ---------------------------------------------------------------- UC-38: duyệt / từ chối
async function approve(actor, id) {
  const booking = await AmenityBooking.findOneAndUpdate(
    // Đã qua giờ bắt đầu thì không duyệt nữa (job sẽ chuyển sang hết hạn)
    { _id: id, status: B.PENDING, startTime: { $gt: new Date() } },
    { $set: { status: B.CONFIRMED, reviewedBy: actor._id, reviewedAt: new Date() } },
    { new: true }
  );
  if (!booking) throw await stateError(id);
  await notifyUsers({
    userIds: [booking.bookedBy],
    type: 'booking_confirmed',
    title: 'Lượt đặt tiện ích đã được duyệt',
    body: `Bắt đầu lúc ${toVN(booking.startTime).toFormat('HH:mm dd/MM/yyyy')}`,
    link: link(booking),
  });
  return decorate(booking);
}

async function reject(actor, id, reason) {
  const booking = await changeStatus(
    id,
    [B.PENDING],
    { status: B.REJECTED, rejectReason: reason, reviewedBy: actor._id, reviewedAt: new Date() },
    { release: true }
  );
  if (!booking) throw await stateError(id);
  await notifyUsers({
    userIds: [booking.bookedBy],
    type: 'booking_rejected',
    title: 'Lượt đặt tiện ích bị từ chối',
    body: `Lý do: ${reason}`,
    link: link(booking),
  });
  return decorate(booking);
}

// ---------------------------------------------------------------- UC-39: hủy
async function cancel(actor, id, reason) {
  const booking = await findVisibleOrThrow(actor, id);
  if (!sameId(booking.bookedBy, actor._id)) {
    throw new AppError(ERROR_CODES.FORBIDDEN, 'Chỉ người đặt mới được hủy');
  }
  if (!ACTIVE.includes(booking.status)) throw await stateError(id);
  if (new Date() > cancelDeadline(booking)) {
    throw new AppError(
      ERROR_CODES.CANCEL_DEADLINE_PASSED,
      `Đã quá hạn hủy (trước giờ bắt đầu ${booking.cancelDeadlineHours} tiếng)`
    );
  }
  const updated = await changeStatus(
    id,
    ACTIVE,
    { status: B.CANCELLED, cancelReason: reason, cancelledAt: new Date(), cancelledBy: actor._id },
    { release: true }
  );
  if (!updated) throw await stateError(id);
  return decorate(updated);
}

/**
 * Ban quản lý (Facility / Manager) hủy khi có sự cố: bảo trì, hỏng thiết bị, vi phạm nội quy...
 * Khác cư dân hủy: bắt buộc lý do, không áp dụng hạn hủy, được hủy cả lượt đã xác nhận.
 * Chỉ lượt chưa kết thúc (endTime ở tương lai). Trả chỗ và báo người đặt.
 */
async function cancelByStaff(actor, id, reason) {
  const now = new Date();
  const updated = await withTransaction(async (session) => {
    const doc = await AmenityBooking.findOneAndUpdate(
      { _id: id, status: { $in: ACTIVE }, endTime: { $gt: now } },
      {
        $set: {
          status: B.CANCELLED,
          cancelReason: reason,
          cancelledAt: now,
          cancelledBy: actor._id,
          cancelledByStaff: true,
        },
      },
      { new: true, session }
    );
    if (doc) await releaseSlot(doc, session);
    return doc;
  });
  if (!updated) throw await stateError(id);

  await notifyUsers({
    userIds: [updated.bookedBy],
    type: 'booking_cancelled_by_staff',
    title: 'Lượt đặt tiện ích đã bị ban quản lý hủy',
    body: `${toVN(updated.startTime).toFormat('HH:mm dd/MM/yyyy')} · Lý do: ${reason}`,
    link: link(updated),
  });
  return decorate(updated);
}

// ---------------------------------------------------------------- Job
/** confirmed đã qua endTime -> completed (không trả chỗ: slot đã qua). */
async function completeFinished(now = new Date()) {
  const res = await AmenityBooking.updateMany(
    { status: B.CONFIRMED, endTime: { $lte: now } },
    { $set: { status: B.COMPLETED, completedAt: now } }
  );
  return res.modifiedCount;
}

/** pending đã tới giờ mà chưa ai duyệt -> rejected "Hết hạn duyệt". */
async function expireStalePending(now = new Date()) {
  const stale = await AmenityBooking.find({ status: B.PENDING, startTime: { $lte: now } }).select('_id');
  let n = 0;
  for (const { _id } of stale) {
    const doc = await AmenityBooking.findOneAndUpdate(
      { _id, status: B.PENDING },
      { $set: { status: B.REJECTED, rejectReason: 'Hết hạn duyệt', reviewedAt: now } },
      { new: true }
    );
    if (!doc) continue;
    n += 1;
    await notifyUsers({
      userIds: [doc.bookedBy],
      type: 'booking_rejected',
      title: 'Lượt đặt tiện ích hết hạn duyệt',
      body: 'Yêu cầu chưa được duyệt trước giờ sử dụng',
      link: link(doc),
    });
  }
  return n;
}

// ---------------------------------------------------------------- Hook chuyển đi (UC-11)
/**
 * Hủy booking tương lai và trả chỗ. userId = null: cả căn hộ (người cuối cùng chuyển đi);
 * có userId: chỉ booking người đó đặt. Trả về số booking đã hủy.
 */
async function cancelFutureForMoveOut(apartmentId, userId) {
  const filter = { apartmentId, status: { $in: ACTIVE }, startTime: { $gt: new Date() } };
  if (userId) filter.bookedBy = userId;
  const targets = await AmenityBooking.find(filter).select('_id');
  let n = 0;
  for (const { _id } of targets) {
    const doc = await changeStatus(
      _id,
      ACTIVE,
      { status: B.CANCELLED, cancelReason: 'Cư dân chuyển đi', cancelledAt: new Date() },
      { release: true }
    );
    if (doc) n += 1;
  }
  return n;
}

module.exports = {
  cancelDeadline,
  allowedActions,
  book,
  listMine,
  listForStaff,
  getDetail,
  approve,
  reject,
  cancel,
  cancelByStaff,
  completeFinished,
  expireStalePending,
  cancelFutureForMoveOut,
};
