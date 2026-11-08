const mongoose = require('mongoose');
const { BOOKING_STATUS } = require('../utils/constants');

/**
 * Lượt đặt tiện ích (M6, UC-37 → 39). Mỗi booking đúng một slot.
 * pending -> confirmed | rejected | cancelled; confirmed -> cancelled | completed.
 */
const amenityBookingSchema = new mongoose.Schema(
  {
    amenityId: { type: mongoose.Schema.Types.ObjectId, ref: 'Amenity', required: true },
    apartmentId: { type: mongoose.Schema.Types.ObjectId, ref: 'Apartment', required: true },
    bookedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    // Đầu ngày theo giờ VN; startTime/endTime là mốc thật (UTC)
    bookingDate: { type: Date, required: true },
    startTime: { type: Date, required: true },
    endTime: { type: Date, required: true },
    numberOfParticipants: { type: Number, required: true, min: 1 },
    note: String,
    status: { type: String, enum: Object.values(BOOKING_STATUS), required: true },
    // Chụp lại quy định lúc đặt: Manager sửa tiện ích sau đó không ảnh hưởng booking cũ
    cancelDeadlineHours: { type: Number, default: 0 },

    reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    reviewedAt: Date,
    rejectReason: String,
    cancelledAt: Date,
    cancelReason: String,
    // Người hủy: cư dân (người đặt) hoặc ban quản lý (Facility / Manager, khi có sự cố)
    cancelledBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    cancelledByStaff: { type: Boolean, default: false },
    completedAt: Date,
  },
  { timestamps: true }
);

// Một căn hộ chỉ có một booking đang hoạt động ở cùng slot của cùng tiện ích
amenityBookingSchema.index(
  { apartmentId: 1, amenityId: 1, startTime: 1 },
  {
    unique: true,
    partialFilterExpression: { status: { $in: [BOOKING_STATUS.PENDING, BOOKING_STATUS.CONFIRMED] } },
    name: 'one_active_booking_per_apartment_slot',
  }
);
amenityBookingSchema.index({ status: 1, startTime: 1 });
amenityBookingSchema.index({ apartmentId: 1, startTime: -1 });
amenityBookingSchema.index({ amenityId: 1, startTime: 1 });

amenityBookingSchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.__v;
  return o;
};

module.exports = mongoose.model('AmenityBooking', amenityBookingSchema);
