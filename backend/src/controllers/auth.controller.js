const authService = require('../services/auth.service');
const { ok } = require('../utils/response');

exports.login = async (req, res) => ok(res, await authService.login(req.validated.body));

// JWT không lưu phía server: client xóa token là đăng xuất
exports.logout = async (_req, res) => ok(res, { loggedOut: true });

exports.forgotPassword = async (req, res) => {
  const extra = await authService.forgotPassword(req.validated.body);
  ok(res, { message: 'Nếu email tồn tại, mã OTP đã được gửi tới hộp thư.', ...extra });
};

exports.resetPassword = async (req, res) => {
  await authService.resetPassword(req.validated.body);
  ok(res, { message: 'Đặt lại mật khẩu thành công, vui lòng đăng nhập.' });
};

exports.changePassword = async (req, res) =>
  ok(res, await authService.changePassword(req.user._id, req.validated.body));
