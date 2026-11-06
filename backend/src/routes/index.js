const router = require('express').Router();
const { authenticate } = require('../middleware/auth');
const { ok } = require('../utils/response');

router.get('/health', (_req, res) => ok(res, { status: 'ok', time: new Date().toISOString() }));

// Module routes sẽ được mount ở các bước sau:
// router.use('/auth', require('./auth.routes'));

// Dùng để kiểm tra middleware xác thực
router.get('/me-check', authenticate, (req, res) =>
  ok(res, { id: req.user.id, role: req.user.role })
);

module.exports = router;
