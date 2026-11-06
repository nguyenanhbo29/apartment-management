const userService = require('../services/user.service');
const { ok, created } = require('../utils/response');

exports.getMe = async (req, res) => ok(res, req.user);

exports.updateMe = async (req, res) =>
  ok(res, await userService.updateProfile(req.user._id, req.validated.body));

exports.create = async (req, res) => created(res, await userService.createUser(req.validated.body));

exports.list = async (req, res) => {
  const { items, meta } = await userService.listUsers(req.validated.query);
  ok(res, items, meta);
};

exports.getById = async (req, res) => ok(res, await userService.findOrThrow(req.params.id));

exports.update = async (req, res) =>
  ok(res, await userService.updateProfile(req.params.id, req.validated.body));

exports.updateStatus = async (req, res) =>
  ok(res, await userService.updateStatus(req.user._id, req.params.id, req.validated.body.status));

exports.updateRole = async (req, res) =>
  ok(res, await userService.updateRole(req.user._id, req.params.id, req.validated.body));

exports.resetPassword = async (req, res) =>
  ok(res, await userService.adminResetPassword(req.params.id, req.validated.body.password));
