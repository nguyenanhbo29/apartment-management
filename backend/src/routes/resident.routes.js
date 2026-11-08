const router = require('express').Router();
const ctrl = require('../controllers/resident.controller');
const v = require('../validators/apartment.validators');
const { idParams } = require('../validators/common');
const { validate } = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES, DEPARTMENTS } = require('../utils/constants');

router.use(authenticate);

const manager = authorize([ROLES.MANAGER]);
const viewers = authorize([ROLES.MANAGER, ROLES.ACCOUNTANT, ROLES.STAFF], {
  departments: [DEPARTMENTS.RECEPTION],
});

// UC-10: danh sách đơn đăng ký cư trú
router.get('/registrations', manager, validate({ query: v.listRegistrations }), ctrl.listRegistrations);

// UC-08: tra cứu hồ sơ cư dân toàn tòa
router.get('/', viewers, validate({ query: v.searchResidents }), ctrl.search);
router.get('/:id', viewers, validate({ params: idParams }), ctrl.getById);
router.patch('/:id', manager, validate({ params: idParams, body: v.updateResident }), ctrl.update);
router.patch('/:id/payer', manager, validate({ params: idParams }), ctrl.setPayer);

// UC-10: duyệt / từ chối
router.patch('/:id/approve', manager, validate({ params: idParams }), ctrl.approve);
router.patch(
  '/:id/reject',
  manager,
  validate({ params: idParams, body: v.rejectRegistration }),
  ctrl.reject
);

// UC-11: ghi nhận chuyển đi
router.patch('/:id/move-out', manager, validate({ params: idParams, body: v.moveOut }), ctrl.moveOut);

module.exports = router;
