const { z, objectId, pagination } = require('./common');
const {
  TASK_STATUS,
  TASK_CATEGORY,
  REQUEST_PRIORITY,
  DEPARTMENTS,
} = require('../utils/constants');

const reason = z.string().trim().min(3, 'Lý do tối thiểu 3 ký tự').max(1000);
const department = z.enum(Object.values(DEPARTMENTS));
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Ngày dạng YYYY-MM-DD');
const boolString = z.enum(['true', 'false']).transform((v) => v === 'true');

const create = z.object({
  title: z.string().trim().min(3, 'Tiêu đề tối thiểu 3 ký tự').max(150),
  description: z.string().trim().max(2000).optional(),
  category: z.enum(Object.values(TASK_CATEGORY)).default(TASK_CATEGORY.OTHER),
  location: z.string().trim().max(200).optional(),
  priority: z.enum(Object.values(REQUEST_PRIORITY)).default(REQUEST_PRIORITY.NORMAL),
  department,
  staffId: objectId,
  deadline: z.coerce.date('Hạn hoàn thành không hợp lệ'),
});

// UC-41 danh sách + UC-42 lịch sử (Staff: staffId bị bỏ qua, luôn là của mình)
const list = z.object({
  ...pagination,
  status: z.enum(Object.values(TASK_STATUS)).optional(),
  department: department.optional(),
  staffId: objectId.optional(),
  overdue: boolString.optional(),
  from: date.optional(),
  to: date.optional(),
});

const reassign = z.object({
  department,
  staffId: objectId,
  deadline: z.coerce.date('Hạn hoàn thành không hợp lệ').optional(),
  note: reason,
});

const cancel = z.object({ reason });
// Body multipart (ảnh kết quả ở trường 'images')
const complete = z.object({ note: z.string().trim().max(2000).optional() });

module.exports = { create, list, reassign, cancel, complete };
