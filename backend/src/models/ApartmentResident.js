const mongoose = require('mongoose');
const { RESIDENT_RELATION, RESIDENT_STATUS } = require('../utils/constants');

/**
 * Hồ sơ cư trú: một người ở một căn hộ trong một khoảng thời gian.
 * Không xóa khi chuyển đi (status = ended) để giữ lịch sử.
 * Vòng đời: pending -> active | rejected; active -> ended.
 */
const apartmentResidentSchema = new mongoose.Schema(
  {
    apartmentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Apartment',
      required: true,
      index: true,
    },
    // Tài khoản đăng nhập (nếu có). Trẻ em/người già có thể không có tài khoản.
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },
    fullName: { type: String, required: true, trim: true },
    phone: String,
    idNumber: String, // CCCD/CMND
    dateOfBirth: Date,
    relation: { type: String, enum: Object.values(RESIDENT_RELATION), required: true },
    status: {
      type: String,
      enum: Object.values(RESIDENT_STATUS),
      default: RESIDENT_STATUS.PENDING,
      index: true,
    },
    // Người nộp phí được chỉ định của căn hộ (tối đa 1 người active)
    isPayer: { type: Boolean, default: false },
    moveInDate: Date,
    moveOutDate: Date,
    moveOutReason: String,
    rejectReason: String,
    note: String,
    // manager: Manager thêm trực tiếp; registration: chủ hộ khai báo, qua duyệt
    source: { type: String, enum: ['manager', 'registration'], default: 'manager' },
    registeredBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    reviewedAt: Date,
  },
  { timestamps: true }
);

// Mỗi căn chỉ có một chủ hộ đang hiệu lực tại một thời điểm
apartmentResidentSchema.index(
  { apartmentId: 1 },
  {
    unique: true,
    partialFilterExpression: {
      relation: RESIDENT_RELATION.OWNER,
      status: RESIDENT_STATUS.ACTIVE,
    },
    name: 'one_active_owner_per_apartment',
  }
);

apartmentResidentSchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.__v;
  return o;
};

module.exports = mongoose.model('ApartmentResident', apartmentResidentSchema);
