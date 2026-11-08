const router = require('express').Router();
const ctrl = require('../controllers/operationalTask.controller');
const v = require('../validators/operationalTask.validators');
const { idParams } = require('../validators/common');
const { validate } = require('../middleware/validate');
const { uploadImages } = require('../middleware/upload');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES } = require('../utils/constants');

router.use(authenticate);

const manager = authorize([ROLES.MANAGER]);
const staff = authorize([ROLES.STAFF]);
const managerOrStaff = authorize([ROLES.MANAGER, ROLES.STAFF]);

// UC-41: tạo + giao
router.post('/', manager, validate({ body: v.create }), ctrl.create);
// UC-41 danh sách (Manager) / UC-42 lịch sử (Staff: chỉ của mình)
router.get('/', managerOrStaff, validate({ query: v.list }), ctrl.list);
// UC-42: chi tiết + timeline (ngoài phạm vi: 404)
router.get('/:id', managerOrStaff, validate({ params: idParams }), ctrl.getById);

router.patch('/:id/reassign', manager, validate({ params: idParams, body: v.reassign }), ctrl.transition('reassign'));
router.patch('/:id/cancel', manager, validate({ params: idParams, body: v.cancel }), ctrl.transition('cancel'));
// UC-31: nhân viên được giao
router.patch('/:id/start', staff, validate({ params: idParams }), ctrl.transition('start'));
router.patch(
  '/:id/complete',
  staff,
  uploadImages('images', 5),
  validate({ params: idParams, body: v.complete }),
  ctrl.transition('complete')
);

module.exports = router;
