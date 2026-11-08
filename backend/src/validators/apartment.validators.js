const { z, objectId, phone, pagination } = require('./common');
const { APARTMENT_STATUS, RESIDENT_RELATION, RESIDENT_STATUS } = require('../utils/constants');

const code = z
  .string()
  .trim()
  .min(1, 'Vui lòng nhập mã căn hộ')
  .max(20)
  .regex(/^[A-Za-z0-9.\-_]+$/, 'Mã căn hộ chỉ gồm chữ, số và . - _');

const createApartment = z.object({
  code,
  floor: z.coerce.number().int().min(-5).max(200),
  area: z.coerce.number().positive('Diện tích phải lớn hơn 0').max(10000),
  bedrooms: z.coerce.number().int().min(0).max(20).optional(),
  note: z.string().trim().max(500).optional(),
});

const updateApartment = createApartment
  .partial()
  .refine((d) => Object.keys(d).length > 0, 'Không có dữ liệu cập nhật');

const listApartments = z.object({
  ...pagination,
  q: z.string().trim().max(50).optional(),
  floor: z.coerce.number().int().optional(),
  status: z.enum(Object.values(APARTMENT_STATUS)).optional(),
});

const idNumber = z
  .string()
  .trim()
  .regex(/^(\d{9}|\d{12})$/, 'CCCD/CMND gồm 9 hoặc 12 chữ số');

const personFields = {
  fullName: z.string().trim().min(1, 'Vui lòng nhập họ tên').max(100),
  phone: phone.optional(),
  idNumber: idNumber.optional(),
  dateOfBirth: z.coerce
    .date()
    .refine((d) => d <= new Date(), 'Ngày sinh không được ở tương lai')
    .optional(),
  note: z.string().trim().max(500).optional(),
};

// UC-08: Manager thêm hồ sơ cư trú trực tiếp (có hiệu lực ngay)
const createResident = z.object({
  ...personFields,
  relation: z.enum(Object.values(RESIDENT_RELATION)),
  userId: objectId.optional(),
  moveInDate: z.coerce.date().optional(),
  isPayer: z.boolean().optional(),
});

// UC-09: Chủ hộ khai báo thành viên / người thuê (chờ Manager duyệt)
const registerMember = z.object({
  ...personFields,
  relation: z.enum([RESIDENT_RELATION.MEMBER, RESIDENT_RELATION.TENANT], 'Chỉ khai báo thành viên hoặc người thuê'),
  moveInDate: z.coerce.date().optional(),
});

const updateResident = z
  .object({
    fullName: personFields.fullName.optional(),
    phone: phone.nullish(),
    idNumber: idNumber.nullish(),
    dateOfBirth: z.coerce.date().nullish(),
    note: z.string().trim().max(500).nullish(),
    relation: z.enum(Object.values(RESIDENT_RELATION)).optional(),
    // null = gỡ liên kết tài khoản
    userId: objectId.nullish(),
  })
  .refine((d) => Object.keys(d).length > 0, 'Không có dữ liệu cập nhật');

const residentStatuses = z
  .string()
  .optional()
  .transform((s) => (s ? s.split(',').map((x) => x.trim()) : undefined))
  .pipe(z.array(z.enum(Object.values(RESIDENT_STATUS))).optional());

const listApartmentResidents = z.object({ status: residentStatuses });

const searchResidents = z.object({
  ...pagination,
  q: z.string().trim().max(100).optional(),
  status: residentStatuses,
  relation: z.enum(Object.values(RESIDENT_RELATION)).optional(),
});

const listRegistrations = z.object({
  ...pagination,
  status: z.enum(Object.values(RESIDENT_STATUS)).default(RESIDENT_STATUS.PENDING),
});

const rejectRegistration = z.object({
  reason: z.string().trim().min(1, 'Vui lòng nhập lý do từ chối').max(500),
});

const moveOut = z.object({
  moveOutDate: z.coerce.date().optional(),
  reason: z.string().trim().max(500).optional(),
});

module.exports = {
  createApartment,
  updateApartment,
  listApartments,
  createResident,
  registerMember,
  updateResident,
  listApartmentResidents,
  searchResidents,
  listRegistrations,
  rejectRegistration,
  moveOut,
};
