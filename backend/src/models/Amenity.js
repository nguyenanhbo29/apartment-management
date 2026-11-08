const mongoose = require('mongoose');
const { AMENITY_STATUS } = require('../utils/constants');

const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;

/**
 * Tiện ích (M6, UC-35). Slot sinh từ openTime → closeTime theo slotDuration (phút),
 * giờ Việt Nam, không hỗ trợ mở qua nửa đêm. Sửa tiện ích chỉ áp dụng cho booking mới.
 */
const amenitySchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    description: String,
    rules: String,
    location: String,
    openTime: { type: String, required: true, match: HHMM },
    closeTime: { type: String, required: true, match: HHMM },
    slotDuration: { type: Number, required: true, min: 15 },
    capacity: { type: Number, required: true, min: 1 },
    requiresApproval: { type: Boolean, default: false },
    // Hủy muộn nhất trước giờ bắt đầu bao nhiêu tiếng
    cancelDeadlineHours: { type: Number, default: 2, min: 0 },
    status: { type: String, enum: Object.values(AMENITY_STATUS), default: AMENITY_STATUS.ACTIVE },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true }
);

amenitySchema.index({ status: 1, name: 1 });

amenitySchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.__v;
  return o;
};

module.exports = mongoose.model('Amenity', amenitySchema);
