const service = require('../services/operationalTask.service');
const assignmentService = require('../services/assignment.service');
const { ok, created } = require('../utils/response');

exports.create = async (req, res) => created(res, await service.create(req.user, req.validated.body));

exports.list = async (req, res) => {
  const { items, meta } = await service.list(req.user, req.validated.query);
  ok(res, items, meta);
};

exports.getById = async (req, res) => ok(res, await service.getDetail(req.user, req.params.id));

/** Một handler cho mọi hành động đổi trạng thái: PATCH /:id/<action>. */
exports.transition = (action) => async (req, res) =>
  ok(
    res,
    await service.transition(req.user, req.params.id, action, req.validated?.body || {}, req.files)
  );

// UC-31: việc của tôi (phiếu + nhiệm vụ)
exports.listAssignments = async (req, res) => {
  const { items, meta } = await assignmentService.listAssignments(req.user, req.validated.query);
  ok(res, items, meta);
};
