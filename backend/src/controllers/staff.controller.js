const staffService = require('../services/staff.service');
const { ok } = require('../utils/response');

exports.list = async (req, res) => {
  const { items, meta } = await staffService.listStaff(req.validated.query);
  ok(res, items, meta);
};

exports.departments = async (_req, res) => ok(res, await staffService.listDepartments());
