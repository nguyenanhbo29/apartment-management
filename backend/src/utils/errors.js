// Mã lỗi chung toàn hệ thống (chốt chung với Người 2)
const ERROR_CODES = Object.freeze({
  VALIDATION_ERROR: { status: 400, code: 'VALIDATION_ERROR' },
  BAD_REQUEST: { status: 400, code: 'BAD_REQUEST' },
  UNAUTHORIZED: { status: 401, code: 'UNAUTHORIZED' },
  INVALID_CREDENTIALS: { status: 401, code: 'INVALID_CREDENTIALS' },
  ACCOUNT_INACTIVE: { status: 403, code: 'ACCOUNT_INACTIVE' },
  FORBIDDEN: { status: 403, code: 'FORBIDDEN' },
  NOT_FOUND: { status: 404, code: 'NOT_FOUND' },
  CONFLICT: { status: 409, code: 'CONFLICT' },
  INTERNAL: { status: 500, code: 'INTERNAL_ERROR' },

  // Module vận hành (Người 2)
  NOT_APARTMENT_RESIDENT: { status: 403, code: 'NOT_APARTMENT_RESIDENT' },
  INVALID_FILE: { status: 400, code: 'INVALID_FILE' },
  ASSIGNEE_INVALID: { status: 409, code: 'ASSIGNEE_INVALID' },
  HAS_OPEN_WORK: { status: 409, code: 'HAS_OPEN_WORK' },
  // Sai trạng thái: dùng chung cho mọi máy trạng thái (phiếu, xe, khách, booking, nhiệm vụ)
  INVALID_STATE: { status: 409, code: 'INVALID_STATE' },
  VEHICLE_PLATE_DUPLICATE: { status: 409, code: 'VEHICLE_PLATE_DUPLICATE' },
  VISITOR_OUT_OF_WINDOW: { status: 409, code: 'VISITOR_OUT_OF_WINDOW' },
  SLOT_FULL: { status: 409, code: 'SLOT_FULL' },
  BOOKING_DUPLICATE: { status: 409, code: 'BOOKING_DUPLICATE' },
  CANCEL_DEADLINE_PASSED: { status: 409, code: 'CANCEL_DEADLINE_PASSED' },
});

class AppError extends Error {
  constructor(type, message, details) {
    super(message);
    this.status = type.status;
    this.code = type.code;
    this.details = details;
    this.isAppError = true;
  }
}

module.exports = { ERROR_CODES, AppError };
