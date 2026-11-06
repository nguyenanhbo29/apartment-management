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
