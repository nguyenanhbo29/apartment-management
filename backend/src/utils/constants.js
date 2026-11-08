const ROLES = Object.freeze({
  RESIDENT: 'resident',
  STAFF: 'staff',
  MANAGER: 'manager',
  ACCOUNTANT: 'accountant',
});

// Bộ phận của Staff
const DEPARTMENTS = Object.freeze({
  RECEPTION: 'reception',
  SECURITY: 'security',
  TECHNICAL: 'technical',
  FACILITY: 'facility',
});

const USER_STATUS = Object.freeze({ ACTIVE: 'active', INACTIVE: 'inactive' });

const APARTMENT_STATUS = Object.freeze({ VACANT: 'vacant', OCCUPIED: 'occupied' });

const RESIDENT_RELATION =Object.freeze({ OWNER: 'owner', MEMBER: 'member', TENANT: 'tenant' });
const RESIDENT_STATUS = Object.freeze({
  PENDING: 'pending',
  ACTIVE: 'active',
  REJECTED: 'rejected',
  ENDED: 'ended',
});

const VEHICLE_TYPE = Object.freeze({ MOTORBIKE: 'motorbike', CAR: 'car' });
const VEHICLE_STATUS = Object.freeze({
  PENDING: 'pending',
  APPROVED: 'approved',
  REJECTED: 'rejected',
  INACTIVE: 'inactive',
});

// ---------------------------------------------------------------- Module vận hành (Người 2)
// M5 - Phiếu yêu cầu / phản ánh
const REQUEST_TYPE = Object.freeze({ REPAIR: 'repair', COMPLAINT: 'complaint' });
const REQUEST_CATEGORY = Object.freeze({
  ELECTRIC: 'electric',
  PLUMBING: 'plumbing',
  INTERNET: 'internet',
  ELEVATOR: 'elevator',
  HYGIENE: 'hygiene',
  NOISE: 'noise',
  SECURITY: 'security',
  SERVICE: 'service',
  OTHER: 'other',
});
// Danh mục hợp lệ theo loại phiếu (chốt 2026-11-08). Thang máy, vệ sinh, khác dùng cho cả hai.
// Flutter có bảng giống hệt: lib/features/service_requests/data/models.dart
const C = REQUEST_CATEGORY;
const REQUEST_CATEGORIES_BY_TYPE = Object.freeze({
  [REQUEST_TYPE.REPAIR]: Object.freeze([C.ELECTRIC, C.PLUMBING, C.INTERNET, C.ELEVATOR, C.HYGIENE, C.OTHER]),
  [REQUEST_TYPE.COMPLAINT]: Object.freeze([C.ELEVATOR, C.HYGIENE, C.NOISE, C.SECURITY, C.SERVICE, C.OTHER]),
});
const REQUEST_PRIORITY = Object.freeze({
  LOW: 'low',
  NORMAL: 'normal',
  HIGH: 'high',
  URGENT: 'urgent',
});
const REQUEST_STATUS = Object.freeze({
  PENDING: 'pending',
  REJECTED: 'rejected',
  ASSIGNED: 'assigned',
  IN_PROGRESS: 'in_progress',
  WAITING_CONFIRMATION: 'waiting_confirmation',
  REOPENED: 'reopened',
  CLOSED: 'closed',
  // Cư dân tự rút phiếu khi chưa bắt đầu xử lý (pending / assigned)
  CANCELLED: 'cancelled',
});
// Phiếu đang nằm trong tay nhân viên
const OPEN_REQUEST_STATUSES = Object.freeze([
  REQUEST_STATUS.ASSIGNED,
  REQUEST_STATUS.IN_PROGRESS,
  REQUEST_STATUS.REOPENED,
]);

// M7 - Nhiệm vụ vận hành
const TASK_STATUS = Object.freeze({
  ASSIGNED: 'assigned',
  IN_PROGRESS: 'in_progress',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
});
const OPEN_TASK_STATUSES = Object.freeze([TASK_STATUS.ASSIGNED, TASK_STATUS.IN_PROGRESS]);
const TASK_CATEGORY = Object.freeze({
  INSPECTION: 'inspection', // kiểm tra định kỳ (PCCC, thang máy...)
  MAINTENANCE: 'maintenance',
  CLEANING: 'cleaning',
  PATROL: 'patrol',
  OTHER: 'other',
});

// M3 - Khách
const VISITOR_STATUS = Object.freeze({
  EXPECTED: 'expected',
  CHECKED_IN: 'checked_in',
  CHECKED_OUT: 'checked_out',
  CANCELLED: 'cancelled',
});

// M6 - Đặt tiện ích
const AMENITY_STATUS = Object.freeze({ ACTIVE: 'active', INACTIVE: 'inactive' });
const BOOKING_STATUS = Object.freeze({
  PENDING: 'pending',
  CONFIRMED: 'confirmed',
  REJECTED: 'rejected',
  CANCELLED: 'cancelled',
  COMPLETED: 'completed',
});

module.exports = {
  REQUEST_TYPE,
  REQUEST_CATEGORY,
  REQUEST_CATEGORIES_BY_TYPE,
  REQUEST_PRIORITY,
  REQUEST_STATUS,
  OPEN_REQUEST_STATUSES,
  TASK_STATUS,
  OPEN_TASK_STATUSES,
  TASK_CATEGORY,
  VISITOR_STATUS,
  AMENITY_STATUS,
  BOOKING_STATUS,
  ROLES,
  DEPARTMENTS,
  USER_STATUS,
  APARTMENT_STATUS,
  RESIDENT_RELATION,
  RESIDENT_STATUS,
  VEHICLE_TYPE,
  VEHICLE_STATUS,
};
