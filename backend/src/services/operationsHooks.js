const { optionalModel } = require('../shared/optionalModel');
const Vehicle = require('../models/Vehicle');
const ApartmentResident = require('../models/ApartmentResident');
const { AppError, ERROR_CODES } = require('../utils/errors');
const {
  VEHICLE_STATUS,
  RESIDENT_STATUS,
  VISITOR_STATUS,
  OPEN_REQUEST_STATUSES,
  OPEN_TASK_STATUSES,
} = require('../utils/constants');

/**
 * Hook để module của Người 1 (M1, M2) báo sự kiện cho module vận hành (M3, M5, M6, M7).
 *
 * Model của module vận hành được tra theo tên qua mongoose.models: model nào chưa tạo
 * thì phần đó bỏ qua. Khi thêm model mới (ServiceRequest, OperationalTask, Visitor,
 * AmenityBooking), hook tự có hiệu lực mà không phải sửa code của Người 1.
 */

/**
 * Chặn khóa tài khoản hoặc đổi vai trò/bộ phận của Staff khi còn việc đang mở.
 * Người 1 gọi trong userService.updateStatus và userService.updateRole.
 */
async function assertNoOpenWork(userId) {
  const ServiceRequest = optionalModel('ServiceRequest');
  const OperationalTask = optionalModel('OperationalTask');
  const [hasRequest, hasTask] = await Promise.all([
    ServiceRequest?.exists({ assignedStaffId: userId, status: { $in: OPEN_REQUEST_STATUSES } }),
    OperationalTask?.exists({ assignedStaffId: userId, status: { $in: OPEN_TASK_STATUSES } }),
  ]);
  if (hasRequest || hasTask) {
    throw new AppError(
      ERROR_CODES.HAS_OPEN_WORK,
      'Nhân viên còn phiếu hoặc nhiệm vụ đang mở, hãy chuyển cho người khác trước'
    );
  }
}

/**
 * Dọn dữ liệu vận hành khi một cư dân chuyển đi (UC-11).
 * Người 1 gọi trong residentService.moveOut, sau khi đã kết thúc hồ sơ cư trú.
 * - Căn hộ không còn ai ở: hủy xe, lịch khách, booking tương lai của cả căn.
 * - Căn hộ còn người ở: chỉ hủy lịch khách và booking do chính người đó tạo.
 * Phiếu đang mở giữ nguyên để Manager xử lý.
 * Không ném lỗi ra ngoài: lỗi chỉ ghi log, không làm hỏng thao tác chuyển đi.
 */
async function onResidentMovedOut(apartmentId, userId) {
  try {
    const stillOccupied = await ApartmentResident.exists({
      apartmentId,
      status: RESIDENT_STATUS.ACTIVE,
    });
    const now = new Date();

    if (!stillOccupied) {
      await Vehicle.updateMany(
        { apartmentId, status: { $in: [VEHICLE_STATUS.APPROVED, VEHICLE_STATUS.PENDING] } },
        { $set: { status: VEHICLE_STATUS.INACTIVE, deactivatedAt: now } }
      );
    }

    const byPerson = stillOccupied ? { createdBy: userId } : {};

    const Visitor = optionalModel('Visitor');
    if (Visitor) {
      await Visitor.updateMany(
        { apartmentId, status: VISITOR_STATUS.EXPECTED, ...byPerson },
        { $set: { status: VISITOR_STATUS.CANCELLED, cancelReason: 'Cư dân chuyển đi' } }
      );
    }

    // M6: hủy booking tương lai và trả chỗ (đổi trạng thái có điều kiện + $inc slot
    // trong cùng transaction). require muộn để tránh vòng phụ thuộc khi nạp module.
    const bookingService = require('./amenityBooking.service');
    await bookingService.cancelFutureForMoveOut(apartmentId, stillOccupied ? userId : null);
  } catch (err) {
    console.error('[onResidentMovedOut] failed:', err.message);
  }
}

module.exports = { assertNoOpenWork, onResidentMovedOut };
