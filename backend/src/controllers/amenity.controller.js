const amenityService = require('../services/amenity.service');
const bookingService = require('../services/amenityBooking.service');
const { ok, created } = require('../utils/response');
const { AMENITY_STATUS } = require('../utils/constants');

// ---------------------------------------------------------------- Tiện ích (UC-35, 36)
exports.list = async (req, res) =>
  ok(res, await amenityService.list(req.user, req.validated.query));

exports.create = async (req, res) =>
  created(res, await amenityService.create(req.user, req.validated.body));

exports.getById = async (req, res) =>
  ok(res, await amenityService.findVisibleOrThrow(req.user, req.params.id));

exports.update = async (req, res) =>
  ok(res, await amenityService.update(req.params.id, req.validated.body));

exports.deactivate = async (req, res) =>
  ok(res, await amenityService.setStatus(req.params.id, AMENITY_STATUS.INACTIVE));

exports.activate = async (req, res) =>
  ok(res, await amenityService.setStatus(req.params.id, AMENITY_STATUS.ACTIVE));

exports.slots = async (req, res) =>
  ok(res, await amenityService.getSlots(req.user, req.params.id, req.validated.query.date));

// ---------------------------------------------------------------- Đặt chỗ (UC-37 → 39)
exports.book = async (req, res) => created(res, await bookingService.book(req.user, req.validated.body));

exports.listMine = async (req, res) => {
  const { items, meta } = await bookingService.listMine(req.user, req.validated.query);
  ok(res, items, meta);
};

exports.listForStaff = async (req, res) => {
  const { items, meta } = await bookingService.listForStaff(req.validated.query);
  ok(res, items, meta);
};

exports.getBooking = async (req, res) =>
  ok(res, await bookingService.getDetail(req.user, req.params.id));

exports.approve = async (req, res) => ok(res, await bookingService.approve(req.user, req.params.id));

exports.reject = async (req, res) =>
  ok(res, await bookingService.reject(req.user, req.params.id, req.validated.body.reason));

exports.cancelByStaff = async (req, res) =>
  ok(res, await bookingService.cancelByStaff(req.user, req.params.id, req.validated.body.reason));

exports.cancel = async (req, res) =>
  ok(res, await bookingService.cancel(req.user, req.params.id, req.validated.body?.reason));
