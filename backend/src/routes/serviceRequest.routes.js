const router = require('express').Router();
const ctrl = require('../controllers/serviceRequest.controller');
const v = require('../validators/serviceRequest.validators');
const { idParams } = require('../validators/common');
const { validate } = require('../middleware/validate');
const { uploadImages } = require('../middleware/upload');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES } = require('../utils/constants');

router.use(authenticate);

const manager = authorize([ROLES.MANAGER]);
const staff = authorize([ROLES.STAFF]);
const resident = authorize([ROLES.RESIDENT]);
const MAX_IMAGES = 5;

// UC-27, UC-28: tạo phiếu (multipart, trường ảnh 'images')
router.post(
  '/',
  resident,
  uploadImages('images', MAX_IMAGES),
  validate({ body: v.createRequest }),
  ctrl.create
);
// UC-29: phiếu của tôi (đặt trước '/:id')
router.get('/mine', resident, validate({ query: v.listMine }), ctrl.listMine);
// UC-30: hàng chờ của Manager
router.get('/', manager, validate({ query: v.listForManager }), ctrl.listForManager);
// UC-29: chi tiết + timeline (service tự kiểm tra phạm vi theo vai trò, ngoài phạm vi trả 404)
router.get('/:id', validate({ params: idParams }), ctrl.getById);

// UC-30: Manager
router.patch('/:id/reject', manager, validate({ params: idParams, body: v.reject }), ctrl.transition('reject'));
router.patch('/:id/assign', manager, validate({ params: idParams, body: v.assign }), ctrl.transition('assign'));
router.patch('/:id/reassign', manager, validate({ params: idParams, body: v.reassign }), ctrl.transition('reassign'));
// UC-32, UC-33: nhân viên được giao
router.patch('/:id/start', staff, validate({ params: idParams }), ctrl.transition('start'));
router.patch(
  '/:id/finish',
  staff,
  uploadImages('images', MAX_IMAGES),
  validate({ params: idParams, body: v.finish }),
  ctrl.transition('finish')
);
// UC-34: người tạo phiếu
router.patch('/:id/confirm', resident, validate({ params: idParams, body: v.confirm }), ctrl.transition('confirm'));
router.patch('/:id/reopen', resident, validate({ params: idParams, body: v.reopen }), ctrl.transition('reopen'));
router.patch('/:id/cancel', resident, validate({ params: idParams, body: v.cancel }), ctrl.transition('cancel'));

module.exports = router;
