const apartmentService = require('../services/apartment.service');
const residentService = require('../services/resident.service');
const { ok, created } = require('../utils/response');

exports.list = async (req, res) => {
  const { items, meta } = await apartmentService.listApartments(req.validated.query);
  ok(res, items, meta);
};

exports.mine = async (req, res) => ok(res, await apartmentService.listMyApartments(req.user._id));

exports.create = async (req, res) =>
  created(res, await apartmentService.createApartment(req.validated.body));

exports.getById = async (req, res) =>
  ok(res, await apartmentService.getApartmentDetail(req.user, req.params.id));

exports.update = async (req, res) =>
  ok(res, await apartmentService.updateApartment(req.params.id, req.validated.body));

exports.remove = async (req, res) => {
  await apartmentService.deleteApartment(req.params.id);
  ok(res, { deleted: true });
};

exports.listResidents = async (req, res) =>
  ok(
    res,
    await residentService.listByApartment(req.user, req.params.id, req.validated.query.status)
  );

exports.createResident = async (req, res) =>
  created(res, await residentService.createRecord(req.user, req.params.id, req.validated.body));

exports.registerMember = async (req, res) =>
  created(res, await residentService.registerMember(req.user, req.params.id, req.validated.body));
