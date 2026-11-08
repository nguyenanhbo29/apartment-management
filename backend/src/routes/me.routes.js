const router = require('express').Router();
const taskCtrl = require('../controllers/operationalTask.controller');
const requestValidators = require('../validators/serviceRequest.validators');
const { validate } = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES } = require('../utils/constants');

router.use(authenticate);

// UC-31: việc của tôi (Staff) = phiếu M5 + nhiệm vụ M7, mỗi mục có kind 'request' | 'task'
router.get(
  '/assignments',
  authorize([ROLES.STAFF]),
  validate({ query: requestValidators.listAssignments }),
  taskCtrl.listAssignments
);

module.exports = router;
