const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const { ROLES, DEPARTMENTS, USER_STATUS } = require('../utils/constants');

const userSchema = new mongoose.Schema(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    passwordHash: { type: String, required: true, select: false },
    fullName: { type: String, required: true, trim: true },
    phone: { type: String, trim: true },
    avatarUrl: String,
    role: { type: String, enum: Object.values(ROLES), required: true },
    // Chỉ dùng cho role staff
    department: { type: String, enum: [...Object.values(DEPARTMENTS), null], default: null },
    status: { type: String, enum: Object.values(USER_STATUS), default: USER_STATUS.ACTIVE },
    mustChangePassword: { type: Boolean, default: false },
    buildingId: { type: String, default: 'main' },
    // Tăng mỗi khi đổi/đặt lại mật khẩu -> mọi JWT cũ (mang tv cũ) bị vô hiệu
    tokenVersion: { type: Number, default: 0, select: false },
    passwordChangedAt: Date,
    lastLoginAt: Date,
    resetOtpHash: { type: String, select: false },
    resetOtpExpires: { type: Date, select: false },
    resetOtpSentAt: { type: Date, select: false },
    resetOtpAttempts: { type: Number, default: 0, select: false },
  },
  { timestamps: true }
);

userSchema.methods.verifyPassword = function verifyPassword(plain) {
  return bcrypt.compare(plain, this.passwordHash);
};

userSchema.statics.hashPassword = (plain) => bcrypt.hash(plain, 10);

// Đặt mật khẩu mới và vô hiệu toàn bộ phiên đăng nhập cũ
userSchema.methods.setPassword = async function setPassword(plain) {
  this.passwordHash = await bcrypt.hash(plain, 10);
  this.tokenVersion = (this.tokenVersion || 0) + 1;
  this.passwordChangedAt = new Date();
};

userSchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.passwordHash;
  delete o.tokenVersion;
  delete o.resetOtpHash;
  delete o.resetOtpExpires;
  delete o.resetOtpSentAt;
  delete o.resetOtpAttempts;
  delete o.__v;
  return o;
};

module.exports = mongoose.model('User', userSchema);
