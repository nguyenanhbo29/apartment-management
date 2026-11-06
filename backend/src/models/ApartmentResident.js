const mongoose = require('mongoose');
const { RESIDENT_RELATION, RESIDENT_STATUS } = require('../utils/constants');

const apartmentResidentSchema = new mongoose.Schema(
  {
    apartmentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Apartment',
      required: true,
      index: true,
    },
    // Có thể null nếu người đó chưa có tài khoản
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },
    fullName: { type: String, required: true, trim: true },
    phone: String,
    idNumber: String,
    dateOfBirth: Date,
    relation: { type: String, enum: Object.values(RESIDENT_RELATION), required: true },
    status: {
      type: String,
      enum: Object.values(RESIDENT_STATUS),
      default: RESIDENT_STATUS.PENDING,
    },
    // Người nộp phí được chỉ định của căn hộ
    isPayer: { type: Boolean, default: false },
    moveInDate: Date,
    moveOutDate: Date,
    rejectReason: String,
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

module.exports = mongoose.model('ApartmentResident', apartmentResidentSchema);
