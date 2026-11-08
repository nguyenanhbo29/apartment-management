const ctrl = require('../controllers/report.controller');
const v = require('../validators/report.validators');
const { validate } = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES } = require('../utils/constants');

const manager = [authenticate, authorize([ROLES.MANAGER])];

// /api/dashboard — UC-47
const dashboard = require('express').Router();
dashboard.get('/operations', ...manager, validate({ query: v.range }), ctrl.operations);

// /api/reports — UC-48 (Người 1 làm phần báo cáo tài chính, có thể thêm route vào đây)
const reports = require('express').Router();
reports.get('/staff-performance', ...manager, validate({ query: v.staffPerformance }), ctrl.staffPerformance);

module.exports = { dashboard, reports };
