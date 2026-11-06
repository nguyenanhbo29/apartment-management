const jwt = require('jsonwebtoken');
const env = require('../config/env');
const User = require('../models/User');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { USER_STATUS } = require('../utils/constants');

const signToken = (user) =>
  jwt.sign({ sub: user._id.toString(), role: user.role }, env.jwtSecret, {
    expiresIn: env.jwtExpiresIn,
  });

async function authenticate(req, _res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) {
    throw new AppError(ERROR_CODES.UNAUTHORIZED, 'Thiếu token đăng nhập');
  }
  let payload;
  try {
    payload = jwt.verify(token, env.jwtSecret);
  } catch {
    throw new AppError(ERROR_CODES.UNAUTHORIZED, 'Token không hợp lệ hoặc đã hết hạn');
  }
  const user = await User.findById(payload.sub);
  if (!user) throw new AppError(ERROR_CODES.UNAUTHORIZED, 'Tài khoản không tồn tại');
  if (user.status !== USER_STATUS.ACTIVE) {
    throw new AppError(ERROR_CODES.ACCOUNT_INACTIVE, 'Tài khoản đã bị khóa');
  }
  req.user = user;
  next();
}

// authorize(['manager']) hoặc authorize(['staff'], { departments: ['security'] })
const authorize = (roles = [], opts = {}) => (req, _res, next) => {
  const u = req.user;
  if (!u) throw new AppError(ERROR_CODES.UNAUTHORIZED, 'Chưa đăng nhập');
  if (roles.length && !roles.includes(u.role)) {
    throw new AppError(ERROR_CODES.FORBIDDEN, 'Bạn không có quyền thực hiện thao tác này');
  }
  if (opts.departments && u.role === 'staff' && !opts.departments.includes(u.department)) {
    throw new AppError(
      ERROR_CODES.FORBIDDEN,
      'Bộ phận của bạn không có quyền thực hiện thao tác này'
    );
  }
  next();
};

module.exports = { authenticate, authorize, signToken };
