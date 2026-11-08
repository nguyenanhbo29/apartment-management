const mongoose = require('mongoose');

/**
 * Bộ đếm chỗ đã dùng của một slot (thêm so với ERD, xem kế hoạch mục 8.2).
 * Mỗi slot một document; giữ chỗ bằng update có điều kiện `used <= capacity - people`
 * nên hai người đặt cùng lúc không bao giờ vượt sức chứa.
 * Booking pending và confirmed đều giữ chỗ; hủy / từ chối phải trả chỗ ($inc âm).
 */
const amenitySlotSchema = new mongoose.Schema(
  {
    amenityId: { type: mongoose.Schema.Types.ObjectId, ref: 'Amenity', required: true },
    slotStart: { type: Date, required: true },
    used: { type: Number, default: 0, min: 0 },
  },
  { timestamps: true }
);

amenitySlotSchema.index({ amenityId: 1, slotStart: 1 }, { unique: true });

module.exports = mongoose.model('AmenitySlot', amenitySlotSchema);
