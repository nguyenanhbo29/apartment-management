const crypto = require('crypto');
const User = require('../models/User');
const { signToken } = require('../middleware/auth');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { USER_STATUS } = require('../utils/constants');
const { sendMail, isConsoleMode } = require('./mail.service');

const OTP_TTL_MS = 10 * 60 * 1000; // OTP hiệu lực 10 phút
const OTP_RESEND_MS = 60 * 1000; // tối thiểu 60 giây giữa 2 lần gửi
const OTP_MAX_ATTEMPTS = 5;

const hashOtp = (otp) => crypto.createHash('sha256').update(otp).digest('hex');

async function login({ email, password }) {
  const user = await User.findOne({ email }).select('+passwordHash +tokenVersion');
  // Cùng một thông báo cho sai email/sai mật khẩu để không lộ email tồn tại
  if (!user || !(await user.verifyPassword(password))) {
    throw new AppError(ERROR_CODES.INVALID_CREDENTIALS, 'Email hoặc mật khẩu không đúng');
  }
  if (user.status !== USER_STATUS.ACTIVE) {
    throw new AppError(ERROR_CODES.ACCOUNT_INACTIVE, 'Tài khoản đã bị khóa, vui lòng liên hệ quản lý');
  }
  user.lastLoginAt = new Date();
  await user.save();
  return { token: signToken(user), user };
}

/**
 * Gửi OTP đặt lại mật khẩu. Luôn trả thành công kể cả email không tồn tại
 * (không lộ thông tin tài khoản). Ở MAIL_MODE=console trả kèm devOtp để demo.
 */
async function forgotPassword({ email }) {
  const user = await User.findOne({ email }).select('+resetOtpSentAt');
  if (!user || user.status !== USER_STATUS.ACTIVE) return {};

  if (user.resetOtpSentAt && Date.now() - user.resetOtpSentAt.getTime() < OTP_RESEND_MS) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Vui lòng đợi 60 giây trước khi gửi lại mã');
  }

  const otp = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
  user.resetOtpHash = hashOtp(otp);
  user.resetOtpExpires = new Date(Date.now() + OTP_TTL_MS);
  user.resetOtpSentAt = new Date();
  user.resetOtpAttempts = 0;
  await user.save();

  await sendMail({
    to: user.email,
    subject: 'Mã đặt lại mật khẩu - Quản lý chung cư',
    text: `Xin chào ${user.fullName},\n\nMã đặt lại mật khẩu của bạn là: ${otp}\nMã có hiệu lực trong 10 phút.\n\nNếu bạn không yêu cầu, hãy bỏ qua email này.`,
  });

  return isConsoleMode() ? { devOtp: otp } : {};
}

async function resetPassword({ email, otp, newPassword }) {
  const invalid = () => new AppError(ERROR_CODES.BAD_REQUEST, 'Mã OTP không đúng hoặc đã hết hạn');
  const user = await User.findOne({ email }).select(
    '+resetOtpHash +resetOtpExpires +resetOtpAttempts +tokenVersion'
  );
  if (!user || !user.resetOtpHash || !user.resetOtpExpires) throw invalid();
  if (user.resetOtpExpires.getTime() < Date.now()) throw invalid();
  if (user.resetOtpAttempts >= OTP_MAX_ATTEMPTS) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Nhập sai quá nhiều lần, vui lòng yêu cầu mã mới');
  }
  if (hashOtp(otp) !== user.resetOtpHash) {
    user.resetOtpAttempts += 1;
    await user.save();
    throw invalid();
  }

  await user.setPassword(newPassword);
  user.mustChangePassword = false;
  user.resetOtpHash = undefined;
  user.resetOtpExpires = undefined;
  user.resetOtpAttempts = 0;
  await user.save();
}

async function changePassword(userId, { currentPassword, newPassword }) {
  const user = await User.findById(userId).select('+passwordHash +tokenVersion');
  if (!(await user.verifyPassword(currentPassword))) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Mật khẩu hiện tại không đúng');
  }
  if (currentPassword === newPassword) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Mật khẩu mới phải khác mật khẩu hiện tại');
  }
  await user.setPassword(newPassword);
  user.mustChangePassword = false;
  await user.save();
  // Cấp token mới vì token cũ đã bị vô hiệu
  return { token: signToken(user), user };
}

module.exports = { login, forgotPassword, resetPassword, changePassword };
