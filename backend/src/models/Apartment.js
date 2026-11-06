const mongoose = require('mongoose');
const { APARTMENT_STATUS } = require('../utils/constants');

const apartmentSchema = new mongoose.Schema(
  {
    // Demo một tòa nhà; giữ buildingId để mở rộng nhiều tòa
    buildingId: { type: String, default: 'main' },
    code: { type: String, required: true, trim: true, uppercase: true },
    floor: { type: Number, required: true },
    area: { type: Number, required: true }, // m2, dùng để tính phí quản lý (M4)
    bedrooms: Number,
    // Tự cập nhật theo số cư dân đang ở, không sửa tay
    status: {
      type: String,
      enum: Object.values(APARTMENT_STATUS),
      default: APARTMENT_STATUS.VACANT,
    },
    note: String,
  },
  { timestamps: true }
);

// Mã căn hộ duy nhất trong tòa
apartmentSchema.index({ buildingId: 1, code: 1 }, { unique: true });

apartmentSchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.__v;
  return o;
};

module.exports = mongoose.model('Apartment', apartmentSchema);
