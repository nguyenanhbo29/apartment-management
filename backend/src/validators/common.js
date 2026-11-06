const { z } = require('zod');

const objectId = z.string().regex(/^[a-f\d]{24}$/i, 'ID không hợp lệ');

// Ít nhất 8 ký tự, có cả chữ và số
const password = z
  .string()
  .min(8, 'Mật khẩu tối thiểu 8 ký tự')
  .max(72, 'Mật khẩu tối đa 72 ký tự')
  .regex(/[A-Za-z]/, 'Mật khẩu phải có chữ cái')
  .regex(/\d/, 'Mật khẩu phải có chữ số');

const email = z.string().trim().toLowerCase().pipe(z.email('Email không hợp lệ'));

const phone = z
  .string()
  .trim()
  .regex(/^(\+?\d{9,15})$/, 'Số điện thoại không hợp lệ');

const pagination = {
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
};

const idParams = z.object({ id: objectId });

module.exports = { z, objectId, password, email, phone, pagination, idParams };
