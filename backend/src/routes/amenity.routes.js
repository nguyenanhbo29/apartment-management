const ctrl = require('../controllers/amenity.controller');
const v = require('../validators/amenity.validators');
const { idParams } = require('../validators/common');
const { validate } = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const { ROLES, DEPARTMENTS } = require('../utils/constants');

const manager = authorize([ROLES.MANAGER]);
const resident = authorize([ROLES.RESIDENT]);
const facility = authorize([ROLES.STAFF], { departments: [DEPARTMENTS.FACILITY] });
// Xem hàng chờ / mọi lượt đặt: Facility + Manager
const bookingViewers = authorize([ROLES.STAFF, ROLES.MANAGER], {
  departments: [DEPARTMENTS.FACILITY],
});

// ---------------------------------------------------------------- /api/amenities
const amenities = require('express').Router();
amenities.use(authenticate);
// UC-35: mọi vai trò xem tiện ích đang mở; Manager thêm ?includeInactive=true
amenities.get('/', validate({ query: v.listAmenities }), ctrl.list);
amenities.post('/', manager, validate({ body: v.createAmenity }), ctrl.create);
amenities.get('/:id', validate({ params: idParams }), ctrl.getById);
amenities.patch('/:id', manager, validate({ params: idParams, body: v.updateAmenity }), ctrl.update);
amenities.patch('/:id/deactivate', manager, validate({ params: idParams }), ctrl.deactivate);
amenities.patch('/:id/activate', manager, validate({ params: idParams }), ctrl.activate);
// UC-36: lưới slot của một ngày
amenities.get('/:id/slots', validate({ params: idParams, query: v.slots }), ctrl.slots);

// ---------------------------------------------------------------- /api/amenity-bookings
const bookings = require('express').Router();
bookings.use(authenticate);
// UC-37
bookings.post('/', resident, validate({ body: v.book }), ctrl.book);
bookings.get('/mine', resident, validate({ query: v.listMine }), ctrl.listMine);
// UC-38: hàng chờ (mặc định pending)
bookings.get('/', bookingViewers, validate({ query: v.listForStaff }), ctrl.listForStaff);
bookings.get('/:id', validate({ params: idParams }), ctrl.getBooking);
bookings.patch('/:id/approve', facility, validate({ params: idParams }), ctrl.approve);
bookings.patch('/:id/reject', facility, validate({ params: idParams, body: v.reject }), ctrl.reject);
// Ban quản lý hủy khi có sự cố (bắt buộc lý do, không áp dụng hạn hủy)
bookings.patch(
  '/:id/cancel-by-staff',
  bookingViewers,
  validate({ params: idParams, body: v.reject }),
  ctrl.cancelByStaff
);
// UC-39: người đặt hủy (service kiểm tra người đặt + hạn hủy)
bookings.patch('/:id/cancel', resident, validate({ params: idParams, body: v.cancel }), ctrl.cancel);

module.exports = { amenities, bookings };
