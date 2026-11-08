const mongoose = require('mongoose');
const { PRIORITY_RANK } = require('./ServiceRequest');
const {
  TASK_STATUS,
  TASK_CATEGORY,
  REQUEST_PRIORITY,
  DEPARTMENTS,
} = require('../utils/constants');

/**
 * Nhiệm vụ vận hành do Manager tạo (M7, UC-41, 42): kiểm tra PCCC, vệ sinh hầm...
 * Không có cư dân nghiệm thu. assigned -> in_progress -> completed; assigned/in_progress -> cancelled.
 * Lịch sử dùng chung RequestHistory (trường taskId).
 */
const operationalTaskSchema = new mongoose.Schema(
  {
    taskCode: { type: String, required: true, unique: true },
    title: { type: String, required: true, trim: true },
    description: { type: String, trim: true },
    category: { type: String, enum: Object.values(TASK_CATEGORY), default: TASK_CATEGORY.OTHER },
    location: { type: String, trim: true },
    priority: {
      type: String,
      enum: Object.values(REQUEST_PRIORITY),
      default: REQUEST_PRIORITY.NORMAL,
    },
    priorityRank: { type: Number, default: PRIORITY_RANK.normal },

    // Một người chịu trách nhiệm chính
    department: { type: String, enum: Object.values(DEPARTMENTS), required: true },
    assignedStaffId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    assignedAt: Date,
    deadline: { type: Date, required: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },

    status: { type: String, enum: Object.values(TASK_STATUS), default: TASK_STATUS.ASSIGNED },
    startedAt: Date,
    completedAt: Date,
    completionNote: String,
    resultImages: [String],
    cancelReason: String,
    cancelledAt: Date,
  },
  { timestamps: true }
);

operationalTaskSchema.index({ assignedStaffId: 1, status: 1 });
operationalTaskSchema.index({ status: 1, deadline: 1 });
operationalTaskSchema.index({ createdAt: -1 });

operationalTaskSchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.__v;
  delete o.priorityRank;
  return o;
};

module.exports = mongoose.model('OperationalTask', operationalTaskSchema);
