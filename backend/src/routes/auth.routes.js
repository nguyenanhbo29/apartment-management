const router = require('express').Router();
const ctrl = require('../controllers/auth.controller');
const v = require('../validators/auth.validators');
const { validate } = require('../middleware/validate');
const { authenticate } = require('../middleware/auth');

router.post('/login', validate({ body: v.login }), ctrl.login);
router.post('/logout', authenticate, ctrl.logout);
router.post('/forgot-password', validate({ body: v.forgotPassword }), ctrl.forgotPassword);
router.post('/reset-password', validate({ body: v.resetPassword }), ctrl.resetPassword);
router.post(
  '/change-password',
  authenticate,
  validate({ body: v.changePassword }),
  ctrl.changePassword
);

module.exports = router;
