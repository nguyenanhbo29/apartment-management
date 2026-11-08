const request = require('supertest');
const { DateTime } = require('luxon');
const app = require('../src/app');
const Apartment = require('../src/models/Apartment');
const ApartmentResident = require('../src/models/ApartmentResident');
const Notification = require('../src/models/Notification');
const AmenitySlot = require('../src/models/AmenitySlot');
const AmenityBooking = require('../src/models/AmenityBooking');
const bookingService = require('../src/services/amenityBooking.service');
const { TZ, combineVN } = require('../src/shared/time');
const { setupDb, teardownDb, createUser, bearer } = require('./helpers');

const vnDate = (days = 0) => DateTime.now().setZone(TZ).plus({ days }).toISODate();
const TOMORROW = vnDate(1);
const HOUR = 60 * 60 * 1000;

let manager;
let facility;
let guard;
let residents; // [{ actor, apartment }]
let member; // thành viên căn của residents[0]

const as = (actor) => ({
  get: (url) => request(app).get(url).set(bearer(actor.token)),
  post: (url, body) => request(app).post(url).set(bearer(actor.token)).send(body),
  patch: (url, body) => request(app).patch(url).set(bearer(actor.token)).send(body),
});

async function createAmenity(extra = {}) {
  const res = await as(manager).post('/api/amenities', {
    name: `Tiện ích ${Math.random().toString(36).slice(2, 7)}`,
    openTime: '06:00',
    closeTime: '10:00',
    slotDuration: 60,
    capacity: 10,
    ...extra,
  });
  expect(res.status).toBe(201);
  return res.body.data;
}

const bookVia = (who, amenity, extra = {}) =>
  as(who.actor).post('/api/amenity-bookings', {
    amenityId: amenity._id,
    apartmentId: String(who.apartment._id),
    date: TOMORROW,
    startTime: '06:00',
    numberOfParticipants: 1,
    ...extra,
  });

const usedOf = async (amenity, date = TOMORROW, hhmm = '06:00') =>
  (await AmenitySlot.findOne({ amenityId: amenity._id, slotStart: combineVN(date, hhmm) }))?.used ?? 0;

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
  facility = await createUser({ role: 'staff', department: 'facility' });
  guard = await createUser({ role: 'staff', department: 'security' });
  residents = [];
  for (let i = 0; i < 8; i += 1) {
    const actor = await createUser({ role: 'resident', fullName: `Cư Dân ${i}` });
    const apartment = await Apartment.create({ code: `T-${100 + i}`, floor: 1, area: 50 });
    await ApartmentResident.create({
      apartmentId: apartment._id,
      userId: actor.user._id,
      fullName: actor.user.fullName,
      relation: 'owner',
      status: 'active',
    });
    residents.push({ actor, apartment });
  }
  member = { actor: await createUser({ role: 'resident' }), apartment: residents[0].apartment };
  await ApartmentResident.create({
    apartmentId: member.apartment._id,
    userId: member.actor.user._id,
    fullName: 'Thành Viên',
    relation: 'member',
    status: 'active',
  });
});
afterAll(teardownDb);

// ======================================================================== UC-35
describe('UC-35 quản lý tiện ích', () => {
  test('giờ mở / đóng, slot dài hơn khung mở cửa: 400; cư dân không tạo được', async () => {
    const bad = (extra) =>
      as(manager).post('/api/amenities', { name: 'X', openTime: '10:00', closeTime: '09:00', slotDuration: 60, capacity: 1, ...extra });
    expect((await bad()).status).toBe(400);
    expect((await bad({ openTime: '09:00', closeTime: '09:30' })).status).toBe(400);
    expect((await bad({ openTime: '9h' })).status).toBe(400);
    expect((await as(residents[0].actor).post('/api/amenities', {})).status).toBe(403);
  });

  test('sửa một phần không điền lại giá trị mặc định', async () => {
    const a = await createAmenity({ requiresApproval: true, cancelDeadlineHours: 5 });
    const res = await as(manager).patch(`/api/amenities/${a._id}`, { capacity: 3 });
    expect(res.body.data).toMatchObject({ capacity: 3, requiresApproval: true, cancelDeadlineHours: 5 });
  });

  test('tạm ngưng: cư dân không thấy, Manager xem được khi includeInactive', async () => {
    const a = await createAmenity({ name: 'Sân tennis' });
    await as(manager).patch(`/api/amenities/${a._id}/deactivate`);
    const forResident = await as(residents[0].actor).get('/api/amenities');
    expect(forResident.body.data.map((x) => x._id)).not.toContain(a._id);
    expect((await as(residents[0].actor).get(`/api/amenities/${a._id}`)).status).toBe(404);
    const forManager = await as(manager).get('/api/amenities?includeInactive=true');
    expect(forManager.body.data.map((x) => x._id)).toContain(a._id);
    // Đặt vào tiện ích tạm ngưng: 409
    expect((await bookVia(residents[0], a)).status).toBe(409);
  });
});

// ======================================================================== UC-36
describe('UC-36 lưới slot', () => {
  test('06:00–10:00, 60 phút → 4 slot theo giờ VN; ngày đã qua không đặt được', async () => {
    const a = await createAmenity();
    const res = await as(residents[0].actor).get(`/api/amenities/${a._id}/slots?date=${TOMORROW}`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(4);
    expect(new Date(res.body.data[0].start).toISOString()).toBe(combineVN(TOMORROW, '06:00').toISOString());
    expect(res.body.data[0]).toMatchObject({ remaining: 10, available: true });

    const past = await as(residents[0].actor).get(`/api/amenities/${a._id}/slots?date=${vnDate(-1)}`);
    expect(past.body.data.every((s) => s.available === false)).toBe(true);
    expect((await as(residents[0].actor).get(`/api/amenities/${a._id}/slots?date=10-11-2026`)).status).toBe(400);
  });

  test('giảm sức chứa dưới số đã đặt: còn lại 0, không âm', async () => {
    const a = await createAmenity({ capacity: 5 });
    await bookVia(residents[0], a, { numberOfParticipants: 4 });
    await as(manager).patch(`/api/amenities/${a._id}`, { capacity: 2 });
    const res = await as(residents[1].actor).get(`/api/amenities/${a._id}/slots?date=${TOMORROW}`);
    expect(res.body.data[0]).toMatchObject({ used: 4, remaining: 0, available: false });
  });
});

// ======================================================================== UC-37
describe('UC-37 đặt tiện ích', () => {
  test('không cần duyệt: confirmed, giữ chỗ đúng số người, chụp hạn hủy', async () => {
    const a = await createAmenity({ cancelDeadlineHours: 3 });
    const res = await bookVia(residents[0], a, { numberOfParticipants: 3, note: 'Sinh nhật' });
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({ status: 'confirmed', numberOfParticipants: 3, cancelDeadlineHours: 3 });
    expect(new Date(res.body.data.cancelDeadline).getTime()).toBe(combineVN(TOMORROW, '06:00').getTime() - 3 * HOUR);
    expect(await usedOf(a)).toBe(3);
  });

  test('giờ không khớp slot / ngày đã qua / quá 30 ngày / quá sức chứa / căn hộ khác: bị chặn', async () => {
    const a = await createAmenity({ capacity: 4 });
    expect((await bookVia(residents[0], a, { startTime: '06:30' })).status).toBe(400);
    expect((await bookVia(residents[0], a, { startTime: '10:00' })).status).toBe(400);
    expect((await bookVia(residents[0], a, { date: vnDate(-1) })).status).toBe(400);
    expect((await bookVia(residents[0], a, { date: vnDate(40) })).status).toBe(400);
    expect((await bookVia(residents[0], a, { numberOfParticipants: 5 })).status).toBe(400);
    const other = await bookVia({ actor: residents[0].actor, apartment: residents[1].apartment }, a);
    expect(other.status).toBe(403);
    expect(await usedOf(a)).toBe(0);
  });

  test('cùng căn đặt trùng slot: 409 BOOKING_DUPLICATE và không giữ thêm chỗ', async () => {
    const a = await createAmenity();
    expect((await bookVia(residents[0], a, { numberOfParticipants: 2 })).status).toBe(201);
    const dup = await bookVia(member, a, { numberOfParticipants: 3 });
    expect(dup.status).toBe(409);
    expect(dup.body.error.code).toBe('BOOKING_DUPLICATE');
    expect(await usedOf(a)).toBe(2); // transaction rollback phần giữ chỗ
  });

  test('Mongo standalone (không transaction): vẫn đặt được; đặt trùng thì trả lại chỗ đã giữ', async () => {
    const { _setTransactionSupport } = require('../src/shared/transaction');
    _setTransactionSupport(false);
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const a = await createAmenity();
      expect((await bookVia(residents[0], a, { numberOfParticipants: 2 })).status).toBe(201);
      const dup = await bookVia(member, a, { numberOfParticipants: 3 });
      expect(dup.body.error.code).toBe('BOOKING_DUPLICATE');
      expect(await usedOf(a)).toBe(2); // compensate trả lại 3 chỗ
    } finally {
      _setTransactionSupport(undefined);
      warn.mockRestore();
    }
  });

  test('TRANH CHẤP: 8 căn cùng đặt slot còn 3 chỗ → đúng 3 thành công, không vượt sức chứa', async () => {
    const a = await createAmenity({ capacity: 3 });
    const results = await Promise.all(residents.map((r) => bookVia(r, a)));
    const statuses = results.map((r) => r.status);
    expect(statuses.filter((s) => s === 201)).toHaveLength(3);
    expect(results.filter((r) => r.status === 409).every((r) => r.body.error.code === 'SLOT_FULL')).toBe(true);
    expect(await usedOf(a)).toBe(3);
    expect(await AmenityBooking.countDocuments({ amenityId: a._id, status: 'confirmed' })).toBe(3);
  });

  test('TRANH CHẤP: nhóm nhiều người tranh chỗ cuối → không vượt sức chứa', async () => {
    const a = await createAmenity({ capacity: 5 });
    const results = await Promise.all(
      residents.slice(0, 5).map((r) => bookVia(r, a, { numberOfParticipants: 2 }))
    );
    expect(results.filter((r) => r.status === 201)).toHaveLength(2); // 2 + 2 = 4, nhóm thứ 3 cần 6 > 5
    expect(await usedOf(a)).toBe(4);
    // Còn 1 chỗ: báo rõ số chỗ còn lại thay vì 'đã đầy'
    const late = await bookVia(residents[5], a, { numberOfParticipants: 2 });
    expect(late.body.error.message).toBe('Khung giờ chỉ còn 1 chỗ, không đủ cho 2 người');
  });

  test('cần duyệt: pending vẫn giữ chỗ, báo Facility', async () => {
    const a = await createAmenity({ capacity: 1, requiresApproval: true, name: 'Khu BBQ' });
    const first = await bookVia(residents[0], a);
    expect(first.body.data.status).toBe('pending');
    expect(await Notification.exists({ userId: facility.user._id, type: 'booking_submitted' })).toBeTruthy();
    const second = await bookVia(residents[1], a);
    expect(second.status).toBe(409);
    expect(second.body.error.code).toBe('SLOT_FULL');
  });
});

// ======================================================================== UC-38
describe('UC-38 duyệt / từ chối', () => {
  let a;
  beforeAll(async () => {
    a = await createAmenity({ capacity: 1, requiresApproval: true, name: 'Phòng sinh hoạt' });
  });

  test('hàng chờ chỉ Facility / Manager; duyệt → confirmed, báo cư dân; duyệt lại 409', async () => {
    const b = (await bookVia(residents[2], a)).body.data;
    expect((await as(guard).get('/api/amenity-bookings')).status).toBe(403);
    const queue = await as(facility).get('/api/amenity-bookings');
    expect(queue.body.data.map((x) => x._id)).toContain(b._id);
    expect(queue.body.data[0].amenityId.name).toBeDefined();

    expect((await as(manager).patch(`/api/amenity-bookings/${b._id}/approve`)).status).toBe(403);
    const res = await as(facility).patch(`/api/amenity-bookings/${b._id}/approve`);
    expect(res.body.data.status).toBe('confirmed');
    expect(await Notification.exists({ userId: residents[2].actor.user._id, type: 'booking_confirmed' })).toBeTruthy();
    expect((await as(facility).patch(`/api/amenity-bookings/${b._id}/approve`)).status).toBe(409);
  });

  test('từ chối: bắt buộc lý do, trả chỗ, người khác đặt được', async () => {
    const b = (await bookVia(residents[3], a, { startTime: '07:00' })).body.data;
    expect(await usedOf(a, TOMORROW, '07:00')).toBe(1);
    expect((await as(facility).patch(`/api/amenity-bookings/${b._id}/reject`, {})).status).toBe(400);
    const res = await as(facility).patch(`/api/amenity-bookings/${b._id}/reject`, { reason: 'Bảo trì' });
    expect(res.body.data).toMatchObject({ status: 'rejected', rejectReason: 'Bảo trì' });
    expect(await usedOf(a, TOMORROW, '07:00')).toBe(0);
    expect((await bookVia(residents[4], a, { startTime: '07:00' })).status).toBe(201);
  });
});

// ======================================================================== UC-39
describe('UC-39 hủy', () => {
  test('người đặt hủy được, trả chỗ; thành viên khác cùng căn: 403; hủy lại: 409', async () => {
    const a = await createAmenity({ capacity: 2 });
    const b = (await bookVia(residents[0], a, { numberOfParticipants: 2 })).body.data;
    expect((await as(member.actor).patch(`/api/amenity-bookings/${b._id}/cancel`, {})).status).toBe(403);
    expect((await as(residents[1].actor).patch(`/api/amenity-bookings/${b._id}/cancel`, {})).status).toBe(404);

    const res = await as(residents[0].actor).patch(`/api/amenity-bookings/${b._id}/cancel`, { reason: 'Bận' });
    expect(res.body.data.status).toBe('cancelled');
    expect(await usedOf(a)).toBe(0);
    expect((await as(residents[0].actor).patch(`/api/amenity-bookings/${b._id}/cancel`, {})).status).toBe(409);
  });

  test('quá hạn hủy: 409 CANCEL_DEADLINE_PASSED; nút hủy không hiện', async () => {
    // Hạn hủy 48 tiếng, slot sáng mai -> đã quá hạn ngay khi đặt
    const a = await createAmenity({ cancelDeadlineHours: 48 });
    const b = (await bookVia(residents[0], a)).body.data;
    const detail = await as(residents[0].actor).get(`/api/amenity-bookings/${b._id}`);
    expect(detail.body.data.allowedActions).toEqual([]);
    const res = await as(residents[0].actor).patch(`/api/amenity-bookings/${b._id}/cancel`, {});
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('CANCEL_DEADLINE_PASSED');
    expect(await usedOf(a)).toBe(1);
  });

  test('Manager đổi hạn hủy sau khi đặt: booking cũ giữ quy định lúc đặt', async () => {
    const a = await createAmenity({ cancelDeadlineHours: 1 });
    const b = (await bookVia(residents[0], a)).body.data;
    await as(manager).patch(`/api/amenities/${a._id}`, { cancelDeadlineHours: 72 });
    expect((await as(residents[0].actor).patch(`/api/amenity-bookings/${b._id}/cancel`, {})).status).toBe(200);
  });
});

// ======================================================================== Ban quản lý hủy
describe('Ban quản lý hủy khi có sự cố', () => {
  test('Facility hủy lượt đã xác nhận dù quá hạn hủy: trả chỗ, báo người đặt, ghi người hủy', async () => {
    const a = await createAmenity({ capacity: 3, cancelDeadlineHours: 48 });
    const b = (await bookVia(residents[0], a, { numberOfParticipants: 3 })).body.data;
    // Cư dân đã quá hạn hủy, nhưng ban quản lý vẫn thấy nút hủy
    const detail = await as(facility).get(`/api/amenity-bookings/${b._id}`);
    expect(detail.body.data.allowedActions).toContain('cancel-by-staff');

    const url = `/api/amenity-bookings/${b._id}/cancel-by-staff`;
    expect((await as(facility).patch(url, {})).status).toBe(400); // bắt buộc lý do
    const res = await as(facility).patch(url, { reason: 'Hồ bơi bảo trì máy lọc' });
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({
      status: 'cancelled',
      cancelReason: 'Hồ bơi bảo trì máy lọc',
      cancelledByStaff: true,
      cancelledBy: String(facility.user._id),
    });
    expect(await usedOf(a)).toBe(0);
    expect(
      await Notification.exists({ userId: residents[0].actor.user._id, type: 'booking_cancelled_by_staff' })
    ).toBeTruthy();
    expect((await as(facility).patch(url, { reason: 'Lần hai' })).status).toBe(409);
  });

  test('Manager hủy được lượt chờ duyệt; cư dân, Bảo vệ: 403', async () => {
    const a = await createAmenity({ requiresApproval: true });
    const b = (await bookVia(residents[1], a)).body.data;
    const url = `/api/amenity-bookings/${b._id}/cancel-by-staff`;
    expect((await as(residents[1].actor).patch(url, { reason: 'Tự hủy' })).status).toBe(403);
    expect((await as(guard).patch(url, { reason: 'Thử' })).status).toBe(403);
    const res = await as(manager).patch(url, { reason: 'Khu vực đang sửa' });
    expect(res.body.data).toMatchObject({ status: 'cancelled', cancelledByStaff: true });
    expect(await usedOf(a)).toBe(0);
  });

  test('lượt đã kết thúc: không hủy được (409)', async () => {
    const a = await createAmenity();
    const start = new Date(Date.now() - 3 * HOUR);
    const past = await AmenityBooking.create({
      amenityId: a._id,
      apartmentId: residents[2].apartment._id,
      bookedBy: residents[2].actor.user._id,
      bookingDate: start,
      startTime: start,
      endTime: new Date(start.getTime() + HOUR),
      numberOfParticipants: 1,
      status: 'confirmed',
    });
    const res = await as(facility).patch(`/api/amenity-bookings/${past._id}/cancel-by-staff`, { reason: 'Thử hủy' });
    expect(res.status).toBe(409);
    expect((await as(facility).get(`/api/amenity-bookings/${past._id}`)).body.data.allowedActions).not.toContain(
      'cancel-by-staff'
    );
  });
});

// ======================================================================== Job + hook
describe('Job và hook chuyển đi', () => {
  async function bookingDoc(amenity, extra) {
    const start = new Date(Date.now() - 3 * HOUR);
    return AmenityBooking.create({
      amenityId: amenity._id,
      apartmentId: residents[5].apartment._id,
      bookedBy: residents[5].actor.user._id,
      bookingDate: start,
      startTime: start,
      endTime: new Date(start.getTime() + HOUR),
      numberOfParticipants: 1,
      ...extra,
    });
  }

  test('confirmed đã dùng xong → completed; pending quá giờ → rejected "Hết hạn duyệt"', async () => {
    const a = await createAmenity();
    const done = await bookingDoc(a, { status: 'confirmed' });
    const stale = await bookingDoc(a, { status: 'pending', startTime: new Date(Date.now() - 10 * 60 * 1000), endTime: new Date(Date.now() + HOUR) });

    expect(await bookingService.completeFinished()).toBeGreaterThanOrEqual(1);
    expect((await AmenityBooking.findById(done._id)).status).toBe('completed');
    expect(await bookingService.expireStalePending()).toBeGreaterThanOrEqual(1);
    expect(await AmenityBooking.findById(stale._id)).toMatchObject({ status: 'rejected', rejectReason: 'Hết hạn duyệt' });
  });

  test('cư dân cuối cùng chuyển đi: booking tương lai bị hủy và trả chỗ', async () => {
    const a = await createAmenity({ capacity: 4 });
    const who = residents[6];
    const b = (await bookVia(who, a, { numberOfParticipants: 3 })).body.data;
    expect(await usedOf(a)).toBe(3);
    const rec = await ApartmentResident.findOne({ userId: who.actor.user._id, status: 'active' });
    expect((await as(manager).patch(`/api/residents/${rec._id}/move-out`, {})).status).toBe(200);
    expect((await AmenityBooking.findById(b._id)).status).toBe('cancelled');
    expect(await usedOf(a)).toBe(0);
  });
});
