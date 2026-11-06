const mongoose = require('mongoose');

const apartmentSchema = new mongoose.Schema(
  {
    buildingId: { type: String, default: 'main' },
    code: { type: String, required: true, trim: true, uppercase: true },
    floor: { type: Number, required: true },
    area: { type: Number, required: true }, // m2
    bedrooms: Number,
    status: { type: String, enum: ['vacant', 'occupied'], default: 'vacant' },
    note: String,
  },
  { timestamps: true }
);

// Mã căn hộ duy nhất trong tòa
apartmentSchema.index({ buildingId: 1, code: 1 }, { unique: true });

module.exports = mongoose.model('Apartment', apartmentSchema);
