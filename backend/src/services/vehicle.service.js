const Vehicle = require('../models/Vehicle');
const User = require('../models/User');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { ROLES, DEPARTMENTS, USER_STATUS, VEHICLE_STATUS: V } = require('../utils/constants');
const { assertActiveResident, myApartmentIds } = require('../shared/residency');
const { saveImages, removeImages } = require('./upload.service');
const { notifyUsers } = require('./notify.service');

/**
 * M3 — Xe (UC-13, 14, 15). Xem docs/ke-hoach-nguoi-2.md mục 7.1.
 * Biển số lưu dạng chuẩn hóa (không dấu, không khoảng trắng, viết hoa) để
 * '30A-123.45' và '30a12345' là một xe. Partial unique index trên model chặn
 * 2 xe approved trùng biển kể cả khi duyệt đồng thời.
 */

const normalizePlate = (raw = '') => raw.toUpperCase().replace(/[\s.\-]/g, '');
const PLATE_REGEX = /^[0-9]{2}[A-Z]{1,2}[0-9]{4,6}$/;

/** Dạng hiển thị trong thông báo / lỗi (giống formatPlate bên Flutter). */
function formatPlate(plate = '') {
  const m = plate.match(/^(\d{2}[A-Z]{1,2})(\d+)$/);
  if (!m) return plate;
  let [, series, digits] = m;
  // 1 chữ cái + 6 số: số đầu thuộc seri xe máy (29-H1 555.55)
  if (series.length === 3 && digits.length === 6) {
    series += digits[0];
    digits = digits.slice(1);
  }
  const tail = digits.length === 5 ? `${digits.slice(0, 3)}.${digits.slice(3)}` : digits;
  return `${series}-${tail}`;
}
const UPLOAD_FOLDER = 'vehicles';

const isSecurity = (u) => u.role === ROLES.STAFF && u.department === DEPARTMENTS.SECURITY;
const canViewAll = (u) => isSecurity(u) || u.role === ROLES.MANAGER || u.role === ROLES.ACCOUNTANT;

const paged = (page, limit, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit) });
const POPULATE = [
  { path: 'apartmentId', select: 'code floor' },
  { path: 'ownerId', select: 'fullName phone' },
  { path: 'reviewedBy', select: 'fullName' },
];

const duplicatePlate = (plate) =>
  new AppError(ERROR_CODES.VEHICLE_PLATE_DUPLICATE, `Biển số ${formatPlate(plate)} đã được đăng ký và đang hoạt động`);

/** Phạm vi xem; cư dân: xe của các căn mình đang ở. null = không được xem. */
async function scopeFor(actor) {
  if (canViewAll(actor)) return {};
  if (actor.role === ROLES.RESIDENT) return { apartmentId: { $in: await myApartmentIds(actor._id) } };
  return null;
}

async function findVisibleOrThrow(actor, id) {
  const scope = await scopeFor(actor);
  const vehicle = scope && (await Vehicle.findOne({ _id: id, ...scope }));
  if (!vehicle) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy xe');
  return vehicle;
}

/** Hành động người xem làm được ngay (app hiện nút; backend vẫn kiểm tra lại). */
function allowedActions(actor, vehicle) {
  const actions = [];
  if (vehicle.status === V.PENDING && isSecurity(actor)) actions.push('approve', 'reject');
  const canDeactivate = actor.role === ROLES.MANAGER || actor.role === ROLES.RESIDENT;
  if ([V.PENDING, V.APPROVED].includes(vehicle.status) && canDeactivate) actions.push('deactivate');
  return actions;
}

const activeSecurityIds = async () =>
  (
    await User.find({
      role: ROLES.STAFF,
      department: DEPARTMENTS.SECURITY,
      status: USER_STATUS.ACTIVE,
    }).select('_id')
  ).map((u) => u._id);

const link = (v) => ({ kind: 'vehicle', id: String(v._id) });

// ---------------------------------------------------------------- UC-13: đăng ký xe
async function register(actor, data, files = []) {
  await assertActiveResident(actor._id, data.apartmentId);
  const plateNumber = normalizePlate(data.plateNumber);
  if (!PLATE_REGEX.test(plateNumber)) {
    throw new AppError(ERROR_CODES.VALIDATION_ERROR, 'Biển số không hợp lệ', [
      { field: 'plateNumber', message: 'Biển số không đúng định dạng (vd 30A-123.45)' },
    ]);
  }
  // Báo sớm cho dễ hiểu; nhiều hồ sơ pending trùng nhau vẫn được, duyệt trước thắng
  if (await Vehicle.exists({ plateNumber, status: V.APPROVED })) throw duplicatePlate(plateNumber);
  // Cùng căn gửi lại biển đang chờ duyệt (bấm hai lần, gửi lại vì tưởng lỗi): chặn ngay
  if (await Vehicle.exists({ plateNumber, apartmentId: data.apartmentId, status: V.PENDING })) {
    throw new AppError(
      ERROR_CODES.VEHICLE_PLATE_DUPLICATE,
      `Căn hộ đã gửi đăng ký biển số ${formatPlate(plateNumber)}, đang chờ duyệt`
    );
  }

  const [imageUrl] = await saveImages(files, UPLOAD_FOLDER);
  let vehicle;
  try {
    vehicle = await Vehicle.create({
      ...data,
      plateNumber,
      ownerId: actor._id,
      imageUrl,
      status: V.PENDING,
    });
  } catch (err) {
    await removeImages([imageUrl].filter(Boolean));
    throw err;
  }

  await notifyUsers({
    userIds: await activeSecurityIds(),
    type: 'vehicle_submitted',
    title: `Đăng ký xe mới ${formatPlate(plateNumber)}`,
    body: `${actor.fullName} đăng ký ${vehicle.type === 'car' ? 'ô tô' : 'xe máy'} ${formatPlate(plateNumber)}`,
    link: link(vehicle),
  });
  return vehicle;
}

// ---------------------------------------------------------------- UC-15: danh sách
async function listMine(actor, { page, limit, status }) {
  const filter = { apartmentId: { $in: await myApartmentIds(actor._id) } };
  if (status) filter.status = status;
  const [items, total] = await Promise.all([
    Vehicle.find(filter)
      .populate('apartmentId', 'code floor')
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    Vehicle.countDocuments(filter),
  ]);
  return { items, meta: paged(page, limit, total) };
}

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

async function list({ page, limit, status, plate, apartmentId, type }) {
  const filter = {};
  if (status) filter.status = status;
  if (apartmentId) filter.apartmentId = apartmentId;
  if (type) filter.type = type;
  // Tìm biển số phải chuẩn hóa trước: '30a-123' khớp '30A12345'
  const q = plate && normalizePlate(plate);
  if (q) filter.plateNumber = new RegExp(escapeRegex(q));
  const [items, total] = await Promise.all([
    Vehicle.find(filter)
      .populate(POPULATE)
      // Hàng chờ duyệt: cũ nhất lên trước
      .sort(status === V.PENDING ? { createdAt: 1 } : { createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    Vehicle.countDocuments(filter),
  ]);
  return { items, meta: paged(page, limit, total) };
}

async function getDetail(actor, id) {
  const vehicle = await findVisibleOrThrow(actor, id);
  await vehicle.populate(POPULATE);
  return { ...vehicle.toJSON(), allowedActions: allowedActions(actor, vehicle) };
}

// ---------------------------------------------------------------- UC-14: duyệt / từ chối
/** Không cập nhật được: phân biệt không tồn tại với sai trạng thái. */
async function stateError(id) {
  if (!(await Vehicle.exists({ _id: id }))) {
    return new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy xe');
  }
  return new AppError(ERROR_CODES.INVALID_STATE, 'Hồ sơ xe đã được xử lý, vui lòng tải lại');
}

async function approve(actor, id) {
  let vehicle;
  try {
    vehicle = await Vehicle.findOneAndUpdate(
      { _id: id, status: V.PENDING },
      { $set: { status: V.APPROVED, reviewedBy: actor._id, reviewedAt: new Date() } },
      { new: true, runValidators: true }
    );
  } catch (err) {
    // unique_approved_plate: đã có xe khác cùng biển được duyệt (kể cả duyệt đồng thời)
    if (err.code === 11000) {
      const pending = await Vehicle.findById(id).select('plateNumber');
      throw duplicatePlate(pending?.plateNumber);
    }
    throw err;
  }
  if (!vehicle) throw await stateError(id);

  await notifyUsers({
    userIds: [vehicle.ownerId],
    type: 'vehicle_approved',
    title: `Xe ${formatPlate(vehicle.plateNumber)} đã được duyệt`,
    body: 'Xe đã được ghi nhận gửi tại tòa nhà',
    link: link(vehicle),
  });
  return vehicle;
}

async function reject(actor, id, reason) {
  const vehicle = await Vehicle.findOneAndUpdate(
    { _id: id, status: V.PENDING },
    { $set: { status: V.REJECTED, rejectReason: reason, reviewedBy: actor._id, reviewedAt: new Date() } },
    { new: true }
  );
  if (!vehicle) throw await stateError(id);

  await notifyUsers({
    userIds: [vehicle.ownerId],
    type: 'vehicle_rejected',
    title: `Đăng ký xe ${formatPlate(vehicle.plateNumber)} bị từ chối`,
    body: `Lý do: ${reason}`,
    link: link(vehicle),
  });
  return vehicle;
}

// ---------------------------------------------------------------- Ngừng sử dụng
/**
 * Cư dân (xe của căn mình) hoặc Manager. pending -> inactive = hủy đăng ký,
 * approved -> inactive = ngừng gửi xe, có hiệu lực cho kỳ phí sau.
 */
async function deactivate(actor, id) {
  const vehicle = await findVisibleOrThrow(actor, id);
  const updated = await Vehicle.findOneAndUpdate(
    { _id: vehicle._id, status: { $in: [V.PENDING, V.APPROVED] } },
    { $set: { status: V.INACTIVE, deactivatedAt: new Date() } },
    { new: true }
  );
  if (!updated) throw await stateError(id);

  if (actor.role === ROLES.MANAGER) {
    await notifyUsers({
      userIds: [updated.ownerId],
      type: 'vehicle_deactivated',
      title: `Xe ${formatPlate(updated.plateNumber)} đã ngừng sử dụng`,
      body: 'Ban quản lý đã chuyển xe sang ngừng sử dụng',
      link: link(updated),
    });
  }
  return updated;
}

// ---------------------------------------------------------------- Cho Người 1 (UC-20)
/** Xe tính phí của căn hộ: chỉ xe đang được duyệt (approved). */
const getBillableVehicles = (apartmentId) =>
  Vehicle.find({ apartmentId, status: V.APPROVED }).sort({ type: 1, createdAt: 1 });

module.exports = {
  normalizePlate,
  formatPlate,
  PLATE_REGEX,
  register,
  listMine,
  list,
  getDetail,
  approve,
  reject,
  deactivate,
  getBillableVehicles,
};
