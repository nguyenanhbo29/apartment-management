// Format response chung:
//   thành công: { success: true, data, meta? }
//   lỗi:        { success: false, error: { code, message, details? } }
const ok = (res, data = null, meta, status = 200) => {
  const body = { success: true, data };
  if (meta) body.meta = meta;
  return res.status(status).json(body);
};
const created = (res, data) => ok(res, data, undefined, 201);

module.exports = { ok, created };
