const service = require('../services/report.service');
const { ok } = require('../utils/response');

// UC-47
exports.operations = async (req, res) => ok(res, await service.operationsDashboard(req.validated.query));

// UC-48 (phần hiệu suất nhân viên)
exports.staffPerformance = async (req, res) =>
  ok(res, await service.staffPerformance(req.validated.query));
