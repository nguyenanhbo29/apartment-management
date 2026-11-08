const service = require('../services/serviceRequest.service');
const { ok, created } = require('../utils/response');

exports.create = async (req, res) =>
  created(res, await service.createRequest(req.user, req.validated.body, req.files));

exports.listMine = async (req, res) => {
  const { items, meta } = await service.listMine(req.user, req.validated.query);
  ok(res, items, meta);
};

exports.listForManager = async (req, res) => {
  const { items, meta } = await service.listForManager(req.validated.query);
  ok(res, items, meta);
};


exports.getById = async (req, res) => ok(res, await service.getDetail(req.user, req.params.id));

/** Một handler cho mọi hành động đổi trạng thái: PATCH /:id/<action>. */
exports.transition = (action) => async (req, res) =>
  ok(
    res,
    await service.transition(
      req.user,
      req.params.id,
      action,
      req.validated?.body || {},
      req.files
    )
  );
