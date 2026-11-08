const User = require('../models/User');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { ROLES, USER_STATUS } = require('../utils/constants');

/**
 * Nhân viên được giao phải là Staff đang hoạt động, đúng bộ phận.
 * Dùng chung cho phân công phiếu (UC-30) và nhiệm vụ (UC-41).
 */
async function assertAssignable(staffId, department) {
  const staff = await User.findOne({
    _id: staffId,
    role: ROLES.STAFF,
    status: USER_STATUS.ACTIVE,
    department,
  });
  if (!staff) {
    throw new AppError(ERROR_CODES.ASSIGNEE_INVALID, 'Nhân viên không hợp lệ cho bộ phận này');
  }
  return staff;
}

module.exports = { assertAssignable };
