const { z, objectId, pagination } = require('./common');
const { ROLES } = require('../utils/constants');

const audience = z.discriminatedUnion('type', [
  z.object({ type: z.literal('all') }),
  z.object({
    type: z.literal('roles'),
    roles: z.array(z.enum(Object.values(ROLES))).min(1, 'Chọn ít nhất một vai trò'),
  }),
  z.object({
    type: z.literal('floors'),
    floors: z.array(z.number().int()).min(1, 'Chọn ít nhất một tầng'),
  }),
  z.object({
    type: z.literal('apartments'),
    apartmentIds: z.array(objectId).min(1, 'Chọn ít nhất một căn hộ'),
  }),
]);

const createAnnouncement = z.object({
  title: z.string().trim().min(1, 'Vui lòng nhập tiêu đề').max(200),
  content: z.string().trim().min(1, 'Vui lòng nhập nội dung').max(10000),
  audience,
  isPinned: z.boolean().default(false),
  expiresAt: z.coerce
    .date()
    .refine((d) => d > new Date(), 'Ngày hết hạn phải ở tương lai')
    .optional(),
});

const listAnnouncements = z.object({
  ...pagination,
  // Chỉ Manager: xem cả bảng tin đã gỡ / hết hạn
  includeInactive: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => v === 'true'),
});

const pinAnnouncement = z.object({ isPinned: z.boolean() });

const listNotifications = z.object({
  ...pagination,
  unreadOnly: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => v === 'true'),
});

module.exports = { createAnnouncement, listAnnouncements, pinAnnouncement, listNotifications };
