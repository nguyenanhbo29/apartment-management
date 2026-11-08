const { z, objectId, pagination, phone } = require('./common');
const { VISITOR_STATUS } = require('../utils/constants');

const status = z.enum(Object.values(VISITOR_STATUS));
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Ngày dạng YYYY-MM-DD');
const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Giờ dạng HH:mm');

const create = z.object({
  apartmentId: objectId,
  visitorName: z.string().trim().min(2, 'Nhập tên khách').max(100),
  visitorPhone: phone.optional(),
  numberOfPeople: z.coerce.number().int().min(1, 'Ít nhất 1 người').max(50),
  vehiclePlate: z.string().trim().max(20).optional(),
  note: z.string().trim().max(500).optional(),
  // Ngày + giờ theo giờ Việt Nam
  visitDate: date,
  timeFrom: time,
  timeTo: time,
});

const listMine = z.object({ ...pagination, status: status.optional() });

const listForGate = z.object({
  ...pagination,
  date: date.optional(),
  code: z.string().trim().min(3).max(20).optional(),
  phone: z.string().trim().min(3).max(15).optional(),
  status: status.optional(),
});

const cancel = z.object({ reason: z.string().trim().max(500).optional() });

module.exports = { create, listMine, listForGate, cancel };
