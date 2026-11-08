const router = require('express').Router();
const { ok } = require('../utils/response');

router.get('/health', (_req, res) => ok(res, { status: 'ok', time: new Date().toISOString() }));

// M1 - Authentication & User Management
router.use('/auth', require('./auth.routes'));
router.use('/users', require('./user.routes'));

// M2 - Apartment & Resident Management
router.use('/apartments', require('./apartment.routes'));
router.use('/residents', require('./resident.routes'));

// M8 - Communication & Notifications
router.use('/announcements', require('./announcement.routes'));
router.use('/notifications', require('./notification.routes'));

// Module vận hành (Người 2) - UC-40 nhân viên theo bộ phận
router.use('/staff', require('./staff.routes'));

module.exports = router;
