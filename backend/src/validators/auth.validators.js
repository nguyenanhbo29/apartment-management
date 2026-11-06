const { z, email, password } = require('./common');

const login = z.object({
  email,
  password: z.string().min(1, 'Vui lòng nhập mật khẩu'),
});

const forgotPassword = z.object({ email });

const resetPassword = z.object({
  email,
  otp: z.string().regex(/^\d{6}$/, 'Mã OTP gồm 6 chữ số'),
  newPassword: password,
});

const changePassword = z.object({
  currentPassword: z.string().min(1, 'Vui lòng nhập mật khẩu hiện tại'),
  newPassword: password,
});

module.exports = { login, forgotPassword, resetPassword, changePassword };
