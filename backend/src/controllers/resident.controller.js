const residentService = require('../services/resident.service');
const { ok } = require('../utils/response');

exports.search = async (req, res) => {
  const { items, meta } = await residentService.searchResidents(req.validated.query);
  ok(res, items, meta);
};

exports.listRegistrations = async (req, res) => {
  const { items, meta } = await residentService.listRegistrations(req.validated.query);
  ok(res, items, meta);
};

exports.getById = async (req, res) => ok(res, await residentService.getRecord(req.params.id));

exports.update = async (req, res) =>
  ok(res, await residentService.updateRecord(req.params.id, req.validated.body));

exports.setPayer = async (req, res) => ok(res, await residentService.setPayer(req.params.id));

exports.approve = async (req, res) =>
  ok(res, await residentService.approve(req.user, req.params.id));

exports.reject = async (req, res) =>
  ok(res, await residentService.reject(req.user, req.params.id, req.validated.body.reason));

exports.moveOut = async (req, res) =>
  ok(res, await residentService.moveOut(req.params.id, req.validated.body));
