const mongoose = require('mongoose');

/**
 * Lịch sử xử lý, dùng chung cho phiếu (M5, requestId) và nhiệm vụ (M7, taskId).
 * Mỗi bản ghi có đúng một trong hai. updatedBy rỗng = hệ thống (vd job tự đóng).
 * Chỉ thêm, không sửa / xóa.
 */
const requestHistorySchema = new mongoose.Schema(
  {
    requestId: { type: mongoose.Schema.Types.ObjectId, ref: 'ServiceRequest' },
    taskId: { type: mongoose.Schema.Types.ObjectId, ref: 'OperationalTask' },
    updatedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
    // created, reject, assign, reassign, start, finish, confirm, reopen, auto_closed...
    action: { type: String, required: true },
    previousStatus: String,
    newStatus: String,
    note: String,
    attachments: [String],
    // Người được giao sau hành động assign/reassign (báo cáo hiệu suất UC-48)
    assignedStaffId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    deadline: Date,
  },
  { timestamps: { createdAt: true, updatedAt: false } }
);

requestHistorySchema.pre('validate', function exactlyOneTarget() {
  if (Boolean(this.requestId) === Boolean(this.taskId)) {
    this.invalidate('requestId', 'Lịch sử phải gắn với đúng một phiếu hoặc một nhiệm vụ');
  }
});

requestHistorySchema.index({ requestId: 1, createdAt: 1 });
requestHistorySchema.index({ taskId: 1, createdAt: 1 });
requestHistorySchema.index({ action: 1, assignedStaffId: 1, createdAt: 1 });

requestHistorySchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.__v;
  return o;
};

module.exports = mongoose.model('RequestHistory', requestHistorySchema);
