const router = require('express').Router();
const ctrl = require('../controllers/user.controller');
const v = require('../validators/user.validators');
const { idParams } = require('../validators/common');
const { validate } = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES } = require('../utils/constants');

router.use(authenticate);

// UC-03: hồ sơ cá nhân (mọi vai trò)
router.get('/me', ctrl.getMe);
router.patch('/me', validate({ body: v.updateMe }), ctrl.updateMe);

// UC-04, UC-05: chỉ Manager
const manager = authorize([ROLES.MANAGER]);
router.post('/', manager, validate({ body: v.createUser }), ctrl.create);
router.get('/', manager, validate({ query: v.listUsers }), ctrl.list);
router.get('/:id', manager, validate({ params: idParams }), ctrl.getById);
router.patch('/:id', manager, validate({ params: idParams, body: v.updateUser }), ctrl.update);
router.patch(
  '/:id/status',
  manager,
  validate({ params: idParams, body: v.updateStatus }),
  ctrl.updateStatus
);
router.patch(
  '/:id/role',
  manager,
  validate({ params: idParams, body: v.updateRole }),
  ctrl.updateRole
);
router.post(
  '/:id/reset-password',
  manager,
  validate({ params: idParams, body: v.adminResetPassword }),
  ctrl.resetPassword
);

module.exports = router;
