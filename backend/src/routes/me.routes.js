const router = require('express').Router();
const requestCtrl = require('../controllers/serviceRequest.controller');
const requestValidators = require('../validators/serviceRequest.validators');
const { validate } = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES } = require('../utils/constants');

router.use(authenticate);

// UC-31: việc của tôi (Staff). M7 sẽ trộn thêm nhiệm vụ vận hành (kind: 'task').
router.get(
  '/assignments',
  authorize([ROLES.STAFF]),
  validate({ query: requestValidators.listAssignments }),
  requestCtrl.listAssignments
);

module.exports = router;
