const mongoose = require('mongoose');
const { VEHICLE_TYPE, VEHICLE_STATUS } = require('../utils/constants');

// Schema dùng chung. Người 2 làm nghiệp vụ M3; Người 1 đọc để tính phí xe (M4).
const vehicleSchema = new mongoose.Schema(
  {
    apartmentId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Apartment',
      required: true,
      index: true,
    },
    ownerId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    type: { type: String, enum: Object.values(VEHICLE_TYPE), required: true },
    plateNumber: { type: String, required: true, uppercase: true, trim: true },
    brand: String,
    color: String,
    status: { type: String, enum: Object.values(VEHICLE_STATUS), default: VEHICLE_STATUS.PENDING },
    rejectReason: String,
    reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    reviewedAt: Date,
    // Thời điểm ngừng sử dụng (cư dân hủy, Manager vô hiệu, hoặc căn hộ không còn người ở)
    deactivatedAt: Date,
    // Ảnh xe / cà vẹt (Người 2, M3) — đường dẫn '/uploads/vehicles/...'
    imageUrl: String,
  },
  { timestamps: true }
);

// Không được có 2 xe approved trùng biển số
vehicleSchema.index(
  { plateNumber: 1 },
  {
    unique: true,
    partialFilterExpression: { status: VEHICLE_STATUS.APPROVED },
    name: 'unique_approved_plate',
  }
);

module.exports = mongoose.model('Vehicle', vehicleSchema);
