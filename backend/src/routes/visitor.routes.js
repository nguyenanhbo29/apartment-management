const router = require('express').Router();
const ctrl = require('../controllers/visitor.controller');
const v = require('../validators/visitor.validators');
const { idParams } = require('../validators/common');
const { validate } = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES, DEPARTMENTS } = require('../utils/constants');

router.use(authenticate);

const resident = authorize([ROLES.RESIDENT]);
const security = authorize([ROLES.STAFF], { departments: [DEPARTMENTS.SECURITY] });
// Xem danh sách khách tại cổng: Bảo vệ, Lễ tân, Manager
const gateViewers = authorize([ROLES.STAFF, ROLES.MANAGER], {
  departments: [DEPARTMENTS.SECURITY, DEPARTMENTS.RECEPTION],
});

// UC-16
router.post('/', resident, validate({ body: v.create }), ctrl.create);
router.get('/mine', resident, validate({ query: v.listMine }), ctrl.listMine);
// UC-17: mặc định khách hôm nay; tìm theo mã hẹn / SĐT
router.get('/', gateViewers, validate({ query: v.listForGate }), ctrl.listForGate);
router.get('/:id', validate({ params: idParams }), ctrl.getById);
router.patch('/:id/cancel', resident, validate({ params: idParams, body: v.cancel }), ctrl.cancel);
// UC-17, UC-18: Bảo vệ
router.patch('/:id/check-in', security, validate({ params: idParams }), ctrl.checkIn);
router.patch('/:id/check-out', security, validate({ params: idParams }), ctrl.checkOut);

module.exports = router;
