const service = require('../services/visitor.service');
const { ok, created } = require('../utils/response');

exports.create = async (req, res) => created(res, await service.create(req.user, req.validated.body));

exports.listMine = async (req, res) => {
  const { items, meta } = await service.listMine(req.user, req.validated.query);
  ok(res, items, meta);
};

exports.listForGate = async (req, res) => {
  const { items, meta } = await service.listForGate(req.validated.query);
  ok(res, items, meta);
};

exports.getById = async (req, res) => ok(res, await service.getDetail(req.user, req.params.id));

exports.cancel = async (req, res) =>
  ok(res, await service.cancel(req.user, req.params.id, req.validated.body?.reason));

exports.checkIn = async (req, res) => ok(res, await service.checkIn(req.user, req.params.id));

exports.checkOut = async (req, res) => ok(res, await service.checkOut(req.user, req.params.id));
