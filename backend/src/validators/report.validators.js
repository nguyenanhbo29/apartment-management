const { z } = require('./common');
const { DEPARTMENTS } = require('../utils/constants');

const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Ngày dạng YYYY-MM-DD');

// Khoảng ngày giờ VN, gồm cả ngày `to`. Bỏ trống: 30 ngày gần nhất.
const range = z.object({ from: date.optional(), to: date.optional() });

const staffPerformance = range.extend({
  department: z.enum(Object.values(DEPARTMENTS)).optional(),
});

module.exports = { range, staffPerformance };
