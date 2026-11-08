const router = require('express').Router();
const ctrl = require('../controllers/vehicle.controller');
const v = require('../validators/vehicle.validators');
const { idParams } = require('../validators/common');
const { validate } = require('../middleware/validate');
const { uploadImages } = require('../middleware/upload');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES, DEPARTMENTS } = require('../utils/constants');

router.use(authenticate);

const resident = authorize([ROLES.RESIDENT]);
const security = authorize([ROLES.STAFF], { departments: [DEPARTMENTS.SECURITY] });
// Tra cứu toàn tòa: Bảo vệ, Manager, Kế toán (đối soát phí xe)
const viewers = authorize([ROLES.STAFF, ROLES.MANAGER, ROLES.ACCOUNTANT], {
  departments: [DEPARTMENTS.SECURITY],
});

// UC-13: đăng ký xe (multipart, ảnh tùy chọn ở trường 'images')
router.post('/', resident, uploadImages('images', 1), validate({ body: v.register }), ctrl.register);
// UC-15
router.get('/mine', resident, validate({ query: v.listMine }), ctrl.listMine);
router.get('/', viewers, validate({ query: v.list }), ctrl.list);
router.get('/:id', validate({ params: idParams }), ctrl.getById);
// UC-14: Bảo vệ duyệt / từ chối
router.patch('/:id/approve', security, validate({ params: idParams }), ctrl.approve);
router.patch('/:id/reject', security, validate({ params: idParams, body: v.reject }), ctrl.reject);
// Ngừng sử dụng: cư dân (xe của căn mình, service kiểm tra) hoặc Manager
router.patch(
  '/:id/deactivate',
  authorize([ROLES.RESIDENT, ROLES.MANAGER]),
  validate({ params: idParams }),
  ctrl.deactivate
);

module.exports = router;
