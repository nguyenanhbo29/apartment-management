const Apartment = require('../models/Apartment');
const ApartmentResident = require('../models/ApartmentResident');
const { AppError, ERROR_CODES } = require('../utils/errors');
const {
  ROLES,
  DEPARTMENTS,
  APARTMENT_STATUS,
  RESIDENT_RELATION,
  RESIDENT_STATUS,
} = require('../utils/constants');

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Vai trò được xem toàn bộ căn hộ/cư dân: Manager, Accountant, Staff Lễ tân. */
const canViewAll = (user) =>
  user.role === ROLES.MANAGER ||
  user.role === ROLES.ACCOUNTANT ||
  (user.role === ROLES.STAFF && user.department === DEPARTMENTS.RECEPTION);

async function findOrThrow(id) {
  const apt = await Apartment.findById(id);
  if (!apt) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy căn hộ');
  return apt;
}

/** Hồ sơ cư trú đang hiệu lực của user tại căn hộ (null nếu không có). */
const findMembership = (userId, apartmentId) =>
  ApartmentResident.findOne({ userId, apartmentId, status: RESIDENT_STATUS.ACTIVE });

/**
 * Kiểm tra quyền xem căn hộ. Trả về { apartment, membership }.
 * Resident chỉ xem được căn hộ mình đang cư trú.
 */
async function assertCanView(user, apartmentId) {
  const apartment = await findOrThrow(apartmentId);
  if (canViewAll(user)) return { apartment, membership: null };
  if (user.role === ROLES.RESIDENT) {
    const membership = await findMembership(user._id, apartment._id);
    if (membership) return { apartment, membership };
  }
  throw new AppError(ERROR_CODES.FORBIDDEN, 'Bạn không có quyền xem căn hộ này');
}

/** Cập nhật trạng thái có người ở / trống theo số cư dân đang ở. */
async function recomputeStatus(apartmentId) {
  const active = await ApartmentResident.exists({ apartmentId, status: RESIDENT_STATUS.ACTIVE });
  const status = active ? APARTMENT_STATUS.OCCUPIED : APARTMENT_STATUS.VACANT;
  await Apartment.updateOne({ _id: apartmentId }, { status });
  return status;
}

/** Gắn thêm số cư dân đang ở và tên chủ hộ cho danh sách căn hộ. */
async function withOccupancy(apartments) {
  const ids = apartments.map((a) => a._id);
  const rows = await ApartmentResident.aggregate([
    { $match: { apartmentId: { $in: ids }, status: RESIDENT_STATUS.ACTIVE } },
    {
      $group: {
        _id: '$apartmentId',
        residentCount: { $sum: 1 },
        owner: {
          $max: { $cond: [{ $eq: ['$relation', RESIDENT_RELATION.OWNER] }, '$fullName', null] },
        },
      },
    },
  ]);
  const byId = new Map(rows.map((r) => [String(r._id), r]));
  return apartments.map((a) => {
    const r = byId.get(String(a._id));
    return { ...a.toJSON(), residentCount: r?.residentCount ?? 0, ownerName: r?.owner ?? null };
  });
}

async function createApartment(data) {
  if (await Apartment.exists({ buildingId: 'main', code: data.code.toUpperCase() })) {
    throw new AppError(ERROR_CODES.CONFLICT, `Mã căn hộ ${data.code.toUpperCase()} đã tồn tại`);
  }
  return Apartment.create(data);
}

async function listApartments({ page, limit, q, floor, status }) {
  const filter = { buildingId: 'main' };
  if (q) filter.code = new RegExp(escapeRegex(q), 'i');
  if (floor !== undefined) filter.floor = floor;
  if (status) filter.status = status;
  const [items, total] = await Promise.all([
    Apartment.find(filter)
      .sort({ floor: 1, code: 1 })
      .skip((page - 1) * limit)
      .limit(limit),
    Apartment.countDocuments(filter),
  ]);
  return {
    items: await withOccupancy(items),
    meta: { page, limit, total, totalPages: Math.ceil(total / limit) },
  };
}

async function getApartmentDetail(user, id) {
  const { apartment, membership } = await assertCanView(user, id);
  const [detail] = await withOccupancy([apartment]);
  return {
    ...detail,
    // Vai trò của người đang xem trong căn hộ (chỉ với Resident)
    myMembership: membership
      ? { id: membership._id, relation: membership.relation, isPayer: membership.isPayer }
      : null,
  };
}

/** UC-07: các căn hộ mà Resident đang cư trú. */
async function listMyApartments(userId) {
  const memberships = await ApartmentResident.find({ userId, status: RESIDENT_STATUS.ACTIVE })
    .populate('apartmentId')
    .sort({ createdAt: 1 });
  const valid = memberships.filter((m) => m.apartmentId);
  const apartments = await withOccupancy(valid.map((m) => m.apartmentId));
  return apartments.map((a, i) => ({
    ...a,
    myMembership: {
      id: valid[i]._id,
      relation: valid[i].relation,
      isPayer: valid[i].isPayer,
    },
  }));
}

async function updateApartment(id, data) {
  const apt = await findOrThrow(id);
  if (data.code && data.code.toUpperCase() !== apt.code) {
    const dup = await Apartment.exists({
      buildingId: apt.buildingId,
      code: data.code.toUpperCase(),
      _id: { $ne: apt._id },
    });
    if (dup) throw new AppError(ERROR_CODES.CONFLICT, `Mã căn hộ ${data.code.toUpperCase()} đã tồn tại`);
  }
  Object.assign(apt, data);
  await apt.save();
  return apt;
}

/** Chỉ xóa được căn hộ chưa từng có hồ sơ cư trú (giữ lịch sử). */
async function deleteApartment(id) {
  const apt = await findOrThrow(id);
  if (await ApartmentResident.exists({ apartmentId: apt._id })) {
    throw new AppError(
      ERROR_CODES.CONFLICT,
      'Căn hộ đã có hồ sơ cư trú, không thể xóa để đảm bảo lưu lịch sử'
    );
  }
  await apt.deleteOne();
}

module.exports = {
  canViewAll,
  findOrThrow,
  findMembership,
  assertCanView,
  recomputeStatus,
  createApartment,
  listApartments,
  getApartmentDetail,
  listMyApartments,
  updateApartment,
  deleteApartment,
};
