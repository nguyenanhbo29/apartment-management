const mongoose = require('mongoose');
const {
  REQUEST_TYPE,
  REQUEST_CATEGORY,
  REQUEST_PRIORITY,
  REQUEST_STATUS,
  DEPARTMENTS,
} = require('../utils/constants');

// Số nhỏ = ưu tiên cao, để sắp xếp hàng chờ (chuỗi không sắp đúng thứ tự)
const PRIORITY_RANK = Object.freeze({ urgent: 0, high: 1, normal: 2, low: 3 });

/**
 * Phiếu yêu cầu sửa chữa / phản ánh (M5, UC-27 → 34).
 * Mọi đổi trạng thái đi qua serviceRequest.service.transition (có điều kiện + lịch sử).
 */
const serviceRequestSchema = new mongoose.Schema(
  {
    requestCode: { type: String, required: true, unique: true },
    requestType: { type: String, enum: Object.values(REQUEST_TYPE), required: true },
    category: { type: String, enum: Object.values(REQUEST_CATEGORY), required: true },
    title: { type: String, required: true, trim: true },
    description: { type: String, required: true, trim: true },
    priority: {
      type: String,
      enum: Object.values(REQUEST_PRIORITY),
      default: REQUEST_PRIORITY.NORMAL,
    },
    priorityRank: { type: Number, default: PRIORITY_RANK.normal },
    apartmentId: { type: mongoose.Schema.Types.ObjectId, ref: 'Apartment', required: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    images: [String],

    status: { type: String, enum: Object.values(REQUEST_STATUS), default: REQUEST_STATUS.PENDING },

    // Phân công
    department: { type: String, enum: [...Object.values(DEPARTMENTS), null], default: null },
    assignedStaffId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
    assignedAt: Date,
    deadline: Date,

    // Kết quả xử lý
    resultNote: String,
    resultImages: [String],
    // Lần báo xong gần nhất (job tự đóng tính từ đây)
    waitingSince: Date,
    // Lần báo xong đầu tiên (báo cáo đúng hạn, UC-48)
    firstFinishedAt: Date,
    reopenCount: { type: Number, default: 0 },

    // Kết thúc
    rejectReason: String,
    cancelledAt: Date,
    cancelReason: String,
    closedAt: Date,
    autoClosed: { type: Boolean, default: false },
    rating: { type: Number, min: 1, max: 5 },
    feedback: String,
  },
  { timestamps: true }
);

serviceRequestSchema.index({ apartmentId: 1, createdAt: -1 });
serviceRequestSchema.index({ assignedStaffId: 1, status: 1 });
serviceRequestSchema.index({ status: 1, priorityRank: 1, createdAt: 1 });
serviceRequestSchema.index({ status: 1, waitingSince: 1 });

serviceRequestSchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.__v;
  delete o.priorityRank;
  return o;
};

module.exports = mongoose.model('ServiceRequest', serviceRequestSchema);
module.exports.PRIORITY_RANK = PRIORITY_RANK;
