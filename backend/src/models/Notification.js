const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    type: { type: String, required: true }, // vd: fee_issued, resident_approved
    title: { type: String, required: true },
    body: { type: String, default: '' },
    // Liên kết tới dữ liệu liên quan, vd { kind: 'fee_statement', id: '...' }
    link: {
      kind: String,
      id: String,
    },
    isRead: { type: Boolean, default: false },
    readAt: Date,
  },
  { timestamps: true }
);

notificationSchema.index({ userId: 1, createdAt: -1 });

module.exports = mongoose.model('Notification', notificationSchema);
