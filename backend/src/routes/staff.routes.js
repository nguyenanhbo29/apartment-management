const router = require('express').Router();
const ctrl = require('../controllers/staff.controller');
const v = require('../validators/staff.validators');
const { validate } = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES } = require('../utils/constants');

router.use(authenticate);

// UC-40: bộ phận (cố định) + số nhân viên — mọi vai trò đã đăng nhập
router.get('/departments', ctrl.departments);
// UC-40: nhân viên theo bộ phận + số việc đang mở — Manager
router.get('/', authorize([ROLES.MANAGER]), validate({ query: v.listStaff }), ctrl.list);

module.exports = router;
