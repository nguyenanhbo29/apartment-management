const { z, objectId, pagination } = require('./common');
const { VEHICLE_TYPE, VEHICLE_STATUS } = require('../utils/constants');

const status = z.enum(Object.values(VEHICLE_STATUS));
const type = z.enum(Object.values(VEHICLE_TYPE));

// Body multipart (trường ảnh 'images', tối đa 1). Định dạng biển số kiểm tra ở service
// sau khi chuẩn hóa ('30A-123.45' -> '30A12345').
const register = z.object({
  apartmentId: objectId,
  type,
  plateNumber: z.string().trim().min(5, 'Nhập biển số').max(20),
  brand: z.string().trim().max(50).optional(),
  color: z.string().trim().max(30).optional(),
});

const listMine = z.object({ ...pagination, status: status.optional() });

const list = z.object({
  ...pagination,
  status: status.optional(),
  type: type.optional(),
  plate: z.string().trim().min(1).max(20).optional(),
  apartmentId: objectId.optional(),
});

const reject = z.object({ reason: z.string().trim().min(3, 'Lý do tối thiểu 3 ký tự').max(500) });

module.exports = { register, listMine, list, reject };
