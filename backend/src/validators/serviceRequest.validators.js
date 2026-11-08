const { z, objectId, pagination } = require('./common');
const {
  REQUEST_TYPE,
  REQUEST_CATEGORY,
  REQUEST_CATEGORIES_BY_TYPE,
  REQUEST_PRIORITY,
  REQUEST_STATUS,
  DEPARTMENTS,
} = require('../utils/constants');

// Body multipart: mọi trường là chuỗi -> dùng coerce cho số / ngày
const reason = z.string().trim().min(3, 'Lý do tối thiểu 3 ký tự').max(1000);
const type = z.enum(Object.values(REQUEST_TYPE));
const priority = z.enum(Object.values(REQUEST_PRIORITY));
const status = z.enum(Object.values(REQUEST_STATUS));
const department = z.enum(Object.values(DEPARTMENTS));
const boolString = z.enum(['true', 'false']).transform((v) => v === 'true');

const createRequest = z.object({
  apartmentId: objectId,
  requestType: type,
  category: z.enum(Object.values(REQUEST_CATEGORY)),
  title: z.string().trim().min(3, 'Tiêu đề tối thiểu 3 ký tự').max(150),
  description: z.string().trim().min(5, 'Mô tả tối thiểu 5 ký tự').max(2000),
  priority: priority.default(REQUEST_PRIORITY.NORMAL),
}).superRefine((d, ctx) => {
  // Danh mục phải thuộc loại phiếu (vd "Sửa chữa" không có "Tiếng ồn")
  if (!REQUEST_CATEGORIES_BY_TYPE[d.requestType].includes(d.category)) {
    ctx.addIssue({
      code: 'custom',
      path: ['category'],
      message: 'Danh mục không thuộc loại phiếu đã chọn',
    });
  }
});

const listMine = z.object({ ...pagination, status: status.optional(), type: type.optional() });

const listForManager = z.object({
  ...pagination,
  // Mặc định hàng chờ phiếu mới; 'all' = mọi trạng thái
  status: z.union([status, z.literal('all')]).default(REQUEST_STATUS.PENDING),
  priority: priority.optional(),
  type: type.optional(),
  department: department.optional(),
  overdue: boolString.optional(),
});

const listAssignments = z.object({
  ...pagination,
  tab: z.enum(['active', 'overdue', 'done']).default('active'),
});

const reject = z.object({ reason });

const assign = z.object({
  department,
  staffId: objectId,
  deadline: z.coerce.date('Hạn xử lý không hợp lệ'),
  priority: priority.optional(),
  note: z.string().trim().max(1000).optional(),
});

const reassign = z.object({
  department,
  staffId: objectId,
  // Bỏ trống thì giữ hạn cũ
  deadline: z.coerce.date('Hạn xử lý không hợp lệ').optional(),
  note: reason,
});

const finish = z.object({ note: z.string().trim().min(3, 'Ghi chú tối thiểu 3 ký tự').max(2000) });

const confirm = z.object({
  rating: z.coerce.number().int().min(1, 'Điểm từ 1 đến 5').max(5, 'Điểm từ 1 đến 5'),
  feedback: z.string().trim().max(1000).optional(),
});

const reopen = z.object({ reason });

// Rút phiếu: lý do không bắt buộc
const cancel = z.object({ reason: z.string().trim().max(1000).optional() });

module.exports = {
  cancel,
  createRequest,
  listMine,
  listForManager,
  listAssignments,
  reject,
  assign,
  reassign,
  finish,
  confirm,
  reopen,
};
