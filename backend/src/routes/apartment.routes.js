const router = require('express').Router();
const ctrl = require('../controllers/apartment.controller');
const v = require('../validators/apartment.validators');
const { idParams } = require('../validators/common');
const { validate } = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES, DEPARTMENTS } = require('../utils/constants');

router.use(authenticate);

const manager = authorize([ROLES.MANAGER]);
// Xem toàn bộ: Manager, Kế toán, Nhân viên Lễ tân
const viewers = authorize([ROLES.MANAGER, ROLES.ACCOUNTANT, ROLES.STAFF], {
  departments: [DEPARTMENTS.RECEPTION],
});
const resident = authorize([ROLES.RESIDENT]);

// UC-07: căn hộ của tôi (Resident)
router.get('/mine', resident, ctrl.mine);

// UC-06: CRUD căn hộ
router.get('/', viewers, validate({ query: v.listApartments }), ctrl.list);
router.post('/', manager, validate({ body: v.createApartment }), ctrl.create);
// Resident xem được căn mình ở: service tự kiểm tra
router.get('/:id', validate({ params: idParams }), ctrl.getById);
router.patch('/:id', manager, validate({ params: idParams, body: v.updateApartment }), ctrl.update);
router.delete('/:id', manager, validate({ params: idParams }), ctrl.remove);

// UC-12: danh sách người cư trú (service kiểm tra quyền theo căn hộ)
router.get(
  '/:id/residents',
  validate({ params: idParams, query: v.listApartmentResidents }),
  ctrl.listResidents
);
// UC-08: Manager thêm hồ sơ cư trú
router.post(
  '/:id/residents',
  manager,
  validate({ params: idParams, body: v.createResident }),
  ctrl.createResident
);
// UC-09: chủ hộ khai báo thành viên / người thuê
router.post(
  '/:id/registrations',
  resident,
  validate({ params: idParams, body: v.registerMember }),
  ctrl.registerMember
);

module.exports = router;
