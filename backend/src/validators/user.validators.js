const { z, email, password, phone, pagination } = require('./common');
const { ROLES, DEPARTMENTS, USER_STATUS } = require('../utils/constants');

const role = z.enum(Object.values(ROLES), 'Vai trò không hợp lệ');
const department = z.enum(Object.values(DEPARTMENTS), 'Bộ phận không hợp lệ');

// Staff bắt buộc có department; role khác không được có department
const roleDepartmentRule = (data, ctx) => {
  if (data.role === ROLES.STAFF && !data.department) {
    ctx.addIssue({ code: 'custom', path: ['department'], message: 'Nhân viên phải có bộ phận' });
  }
  if (data.role && data.role !== ROLES.STAFF && data.department) {
    ctx.addIssue({
      code: 'custom',
      path: ['department'],
      message: 'Chỉ nhân viên (staff) mới có bộ phận',
    });
  }
};

const createUser = z
  .object({
    email,
    fullName: z.string().trim().min(1, 'Vui lòng nhập họ tên').max(100),
    phone: phone.optional(),
    role,
    department: department.nullish(),
    password, // mật khẩu tạm, người dùng phải đổi ở lần đăng nhập đầu
  })
  .superRefine(roleDepartmentRule);

const updateUser = z
  .object({
    fullName: z.string().trim().min(1).max(100).optional(),
    phone: phone.nullish(),
  })
  .refine((d) => Object.keys(d).length > 0, 'Không có dữ liệu cập nhật');

const updateMe = z
  .object({
    fullName: z.string().trim().min(1, 'Vui lòng nhập họ tên').max(100).optional(),
    phone: phone.nullish(),
    avatarUrl: z.url('URL ảnh không hợp lệ').nullish(),
  })
  .refine((d) => Object.keys(d).length > 0, 'Không có dữ liệu cập nhật');

const updateStatus = z.object({ status: z.enum(Object.values(USER_STATUS)) });

const updateRole = z
  .object({ role, department: department.nullish() })
  .superRefine(roleDepartmentRule);

const adminResetPassword = z.object({ password });

const listUsers = z.object({
  ...pagination,
  role: role.optional(),
  department: department.optional(),
  status: z.enum(Object.values(USER_STATUS)).optional(),
  q: z.string().trim().max(100).optional(),
});

module.exports = {
  createUser,
  updateUser,
  updateMe,
  updateStatus,
  updateRole,
  adminResetPassword,
  listUsers,
};
