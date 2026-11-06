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
    resetOtpHash: { type: String, select: false },
    resetOtpExpires: { type: Date, select: false },
  },
  { timestamps: true }
);

userSchema.methods.verifyPassword = function verifyPassword(plain) {
  return bcrypt.compare(plain, this.passwordHash);
};

userSchema.statics.hashPassword = (plain) => bcrypt.hash(plain, 10);

userSchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.passwordHash;
  delete o.resetOtpHash;
  delete o.resetOtpExpires;
  delete o.__v;
  return o;
};

module.exports = mongoose.model('User', userSchema);
