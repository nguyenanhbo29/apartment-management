const ApartmentResident = require('../models/ApartmentResident');
const apartmentService = require('../services/apartment.service');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { RESIDENT_STATUS } = require('../utils/constants');

/**
 * Người dùng phải đang cư trú (active) tại căn hộ. Không bao giờ tin apartmentId
 * client gửi lên mà không qua hàm này. Trả về hồ sơ cư trú (relation, isPayer...).
 */
async function assertActiveResident(userId, apartmentId) {
  const membership = await apartmentService.findMembership(userId, apartmentId);
  if (!membership) {
    throw new AppError(ERROR_CODES.NOT_APARTMENT_RESIDENT, 'Bạn không cư trú tại căn hộ này');
  }
  return membership;
}

/** Id các căn hộ người dùng đang cư trú, dùng cho các API "của tôi". */
const myApartmentIds = (userId) =>
  ApartmentResident.find({ userId, status: RESIDENT_STATUS.ACTIVE }).distinct('apartmentId');

module.exports = { assertActiveResident, myApartmentIds };
