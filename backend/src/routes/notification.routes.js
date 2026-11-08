const router = require('express').Router();
const ctrl = require('../controllers/communication.controller');
const v = require('../validators/communication.validators');
const { idParams } = require('../validators/common');
const { validate } = require('../middleware/validate');
const { authenticate } = require('../middleware/auth');

// UC-45, UC-46: mỗi người chỉ thấy thông báo của mình
router.use(authenticate);

router.get('/', validate({ query: v.listNotifications }), ctrl.listNotifications);
router.get('/unread-count', ctrl.unreadCount);
router.patch('/read-all', ctrl.markAllRead);
router.patch('/:id/read', validate({ params: idParams }), ctrl.markRead);

module.exports = router;
