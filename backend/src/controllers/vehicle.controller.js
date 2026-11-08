const service = require('../services/vehicle.service');
const { ok, created } = require('../utils/response');

exports.register = async (req, res) =>
  created(res, await service.register(req.user, req.validated.body, req.files));

exports.listMine = async (req, res) => {
  const { items, meta } = await service.listMine(req.user, req.validated.query);
  ok(res, items, meta);
};

exports.list = async (req, res) => {
  const { items, meta } = await service.list(req.validated.query);
  ok(res, items, meta);
};

exports.getById = async (req, res) => ok(res, await service.getDetail(req.user, req.params.id));

exports.approve = async (req, res) => ok(res, await service.approve(req.user, req.params.id));

exports.reject = async (req, res) =>
  ok(res, await service.reject(req.user, req.params.id, req.validated.body.reason));

exports.deactivate = async (req, res) => ok(res, await service.deactivate(req.user, req.params.id));
