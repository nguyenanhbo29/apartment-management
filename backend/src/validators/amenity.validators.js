const { z, objectId, pagination } = require('./common');
const { BOOKING_STATUS } = require('../utils/constants');

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Giờ dạng HH:mm');
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Ngày dạng YYYY-MM-DD');
const boolString = z.enum(['true', 'false']).transform((v) => v === 'true');

const amenityFields = {
  name: z.string().trim().min(2, 'Nhập tên tiện ích').max(100),
  description: z.string().trim().max(2000).optional(),
  rules: z.string().trim().max(4000).optional(),
  location: z.string().trim().max(200).optional(),
  openTime: time,
  closeTime: time,
  slotDuration: z.coerce.number().int().min(15, 'Tối thiểu 15 phút').max(720),
  capacity: z.coerce.number().int().min(1, 'Sức chứa tối thiểu 1').max(1000),
  requiresApproval: z.boolean(),
  cancelDeadlineHours: z.coerce.number().int().min(0).max(168),
};

// Mặc định chỉ khi tạo; khi sửa, trường không gửi thì giữ nguyên (không điền mặc định)
const createAmenity = z.object({
  ...amenityFields,
  requiresApproval: amenityFields.requiresApproval.default(false),
  cancelDeadlineHours: amenityFields.cancelDeadlineHours.default(2),
});
const updateAmenity = z
  .object(Object.fromEntries(Object.entries(amenityFields).map(([k, s]) => [k, s.optional()])))
  .transform((o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined)))
  .refine((o) => Object.keys(o).length > 0, 'Không có thay đổi');

const listAmenities = z.object({ includeInactive: boolString.optional() });
const slots = z.object({ date });

const book = z.object({
  amenityId: objectId,
  apartmentId: objectId,
  date,
  startTime: time,
  numberOfParticipants: z.coerce.number().int().min(1, 'Ít nhất 1 người'),
  note: z.string().trim().max(500).optional(),
});

const status = z.enum(Object.values(BOOKING_STATUS));
const listMine = z.object({ ...pagination, status: status.optional() });
const listForStaff = z.object({
  ...pagination,
  status: z.union([status, z.literal('all')]).default(BOOKING_STATUS.PENDING),
  amenityId: objectId.optional(),
});
const reject = z.object({ reason: z.string().trim().min(3, 'Lý do tối thiểu 3 ký tự').max(500) });
const cancel = z.object({ reason: z.string().trim().max(500).optional() });

module.exports = {
  createAmenity,
  updateAmenity,
  listAmenities,
  slots,
  book,
  listMine,
  listForStaff,
  reject,
  cancel,
};
