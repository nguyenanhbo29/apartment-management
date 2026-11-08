const mongoose = require('mongoose');
const { VISITOR_STATUS } = require('../utils/constants');

/**
 * Lịch hẹn khách (M3, UC-16 → 18). Thời gian lưu UTC; visitDate là đầu ngày theo giờ VN.
 * expected -> checked_in -> checked_out; expected -> cancelled.
 * Quá giờ mà khách không đến: không đổi trạng thái, API trả cờ isOverdue.
 */
const visitorSchema = new mongoose.Schema(
  {
    appointmentCode: { type: String, required: true, unique: true },
    apartmentId: { type: mongoose.Schema.Types.ObjectId, ref: 'Apartment', required: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },

    visitorName: { type: String, required: true, trim: true },
    visitorPhone: { type: String, trim: true },
    numberOfPeople: { type: Number, required: true, min: 1 },
    vehiclePlate: { type: String, trim: true, uppercase: true },
    note: String,

    visitDate: { type: Date, required: true },
    timeFrom: { type: Date, required: true },
    timeTo: { type: Date, required: true },

    status: {
      type: String,
      enum: Object.values(VISITOR_STATUS),
      default: VISITOR_STATUS.EXPECTED,
    },
    checkInTime: Date,
    checkedInBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    checkOutTime: Date,
    checkedOutBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    cancelReason: String,
    cancelledAt: Date,
  },
  { timestamps: true }
);

visitorSchema.index({ visitDate: 1, status: 1 });
visitorSchema.index({ apartmentId: 1, visitDate: -1 });
visitorSchema.index({ visitorPhone: 1 });

visitorSchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.__v;
  return o;
};

module.exports = mongoose.model('Visitor', visitorSchema);
