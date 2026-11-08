const mongoose = require('mongoose');
const { ROLES } = require('../utils/constants');

const AUDIENCE_TYPES = ['all', 'roles', 'floors', 'apartments'];

/**
 * Bảng tin do Manager đăng (UC-43).
 * audience.type:
 *   all        - mọi tài khoản
 *   roles      - theo vai trò (audience.roles)
 *   floors     - cư dân đang ở các tầng (audience.floors)
 *   apartments - cư dân đang ở các căn hộ (audience.apartmentIds)
 * Đăng rồi không sửa nội dung; chỉ ghim/bỏ ghim hoặc gỡ (status = removed).
 */
const announcementSchema = new mongoose.Schema(
  {
    title: { type: String, required: true, trim: true },
    content: { type: String, required: true },
    audience: {
      type: { type: String, enum: AUDIENCE_TYPES, required: true },
      roles: [{ type: String, enum: Object.values(ROLES) }],
      floors: [Number],
      apartmentIds: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Apartment' }],
    },
    isPinned: { type: Boolean, default: false },
    // Nhiều tin ghim: tin ghim gần nhất lên đầu
    pinnedAt: Date,
    expiresAt: Date,
    status: { type: String, enum: ['published', 'removed'], default: 'published' },
    publishedAt: { type: Date, default: Date.now },
    recipientCount: { type: Number, default: 0 },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    removedAt: Date,
    removedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true }
);

announcementSchema.index({ status: 1, isPinned: -1, pinnedAt: -1, publishedAt: -1 });

announcementSchema.pre('save', function setPinnedAt() {
  if (this.isModified('isPinned') || this.isNew) {
    this.pinnedAt = this.isPinned ? new Date() : undefined;
  }
});

announcementSchema.methods.toJSON = function toJSON() {
  const o = this.toObject();
  delete o.__v;
  return o;
};

module.exports = mongoose.model('Announcement', announcementSchema);
module.exports.AUDIENCE_TYPES = AUDIENCE_TYPES;
