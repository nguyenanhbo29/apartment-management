const router = require('express').Router();
const ctrl = require('../controllers/communication.controller');
const v = require('../validators/communication.validators');
const { idParams } = require('../validators/common');
const { validate } = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES } = require('../utils/constants');

router.use(authenticate);
const manager = authorize([ROLES.MANAGER]);

// UC-44: mọi vai trò (lọc theo đối tượng nhận ở service)
router.get('/', validate({ query: v.listAnnouncements }), ctrl.listAnnouncements);
router.get('/:id', validate({ params: idParams }), ctrl.getAnnouncement);

// UC-43: Manager đăng, ghim, gỡ
router.post('/', manager, validate({ body: v.createAnnouncement }), ctrl.createAnnouncement);
router.patch(
  '/:id/pin',
  manager,
  validate({ params: idParams, body: v.pinAnnouncement }),
  ctrl.pinAnnouncement
);
router.patch('/:id/remove', manager, validate({ params: idParams }), ctrl.removeAnnouncement);

module.exports = router;
