const { z, pagination } = require('./common');
const { DEPARTMENTS, USER_STATUS } = require('../utils/constants');

const listStaff = z.object({
  ...pagination,
  department: z.enum(Object.values(DEPARTMENTS)).optional(),
  status: z.enum(Object.values(USER_STATUS)).optional(),
  q: z.string().trim().min(1).optional(),
});

module.exports = { listStaff };
