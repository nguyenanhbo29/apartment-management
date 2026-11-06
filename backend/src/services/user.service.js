const User = require('../models/User');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { ROLES } = require('../utils/constants');

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

async function findOrThrow(id) {
  const user = await User.findById(id);
  if (!user) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy tài khoản');
  return user;
}

async function createUser(data) {
  const exists = await User.exists({ email: data.email });
  if (exists) throw new AppError(ERROR_CODES.CONFLICT, 'Email đã được sử dụng');
  return User.create({
    email: data.email,
    fullName: data.fullName,
    phone: data.phone,
    role: data.role,
    department: data.role === ROLES.STAFF ? data.department : null,
    passwordHash: await User.hashPassword(data.password),
    mustChangePassword: true,
  });
}

async function listUsers({ page, limit, role, department, status, q }) {
  const filter = {};
  if (role) filter.role = role;
  if (department) filter.department = department;
  if (status) filter.status = status;
  if (q) {
    const rx = new RegExp(escapeRegex(q), 'i');
    filter.$or = [{ fullName: rx }, { email: rx }, { phone: rx }];
  }
  const [items, total] = await Promise.all([
    User.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    User.countDocuments(filter),
  ]);
  return { items, meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
}

async function updateProfile(id, data) {
  const user = await findOrThrow(id);
  for (const key of ['fullName', 'phone', 'avatarUrl']) {
    if (data[key] !== undefined) user[key] = data[key] ?? undefined;
  }
  await user.save();
  return user;
}

async function updateStatus(actorId, id, status) {
  if (String(actorId) === String(id)) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Không thể tự khóa/mở tài khoản của chính mình');
  }
  const user = await findOrThrow(id);
  user.status = status;
  await user.save();
  return user;
}

async function updateRole(actorId, id, { role, department }) {
  if (String(actorId) === String(id)) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Không thể tự đổi vai trò của chính mình');
  }
  const user = await findOrThrow(id);
  user.role = role;
  user.department = role === ROLES.STAFF ? department : null;
  await user.save();
  return user;
}

// Manager đặt mật khẩu tạm mới khi người dùng không nhận được email
async function adminResetPassword(id, password) {
  const user = await User.findById(id).select('+tokenVersion');
  if (!user) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy tài khoản');
  await user.setPassword(password);
  user.mustChangePassword = true;
  await user.save();
  return user;
}

module.exports = {
  findOrThrow,
  createUser,
  listUsers,
  updateProfile,
  updateStatus,
  updateRole,
  adminResetPassword,
};
