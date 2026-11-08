const request = require('supertest');
const { DateTime } = require('luxon');
const app = require('../src/app');
const Apartment = require('../src/models/Apartment');
const ApartmentResident = require('../src/models/ApartmentResident');
const Notification = require('../src/models/Notification');
const Visitor = require('../src/models/Visitor');
const { TZ, dayRangeVN } = require('../src/shared/time');
const { setupDb, teardownDb, createUser, bearer } = require('./helpers');

const MIN = 60 * 1000;
let manager;
let guard;
let reception;
let owner;
let member;
let outsider;
let aptA;
let aptB;
let seq = 0;

const as = (actor) => ({
  get: (url) => request(app).get(url).set(bearer(actor.token)),
  post: (url, body) => request(app).post(url).set(bearer(actor.token)).send(body),
  patch: (url, body) => request(app).patch(url).set(bearer(actor.token)).send(body),
});

const vnDate = (days = 0) => DateTime.now().setZone(TZ).plus({ days }).toISODate();

async function live(actor, apartment, relation) {
  await ApartmentResident.create({
    apartmentId: apartment._id,
    userId: actor.user._id,
    fullName: actor.user.fullName,
    relation,
    status: 'active',
  });
}

/** Tạo lịch hẹn trực tiếp với khung giờ tương đối so với bây giờ (để test check-in). */
function visitorAt(fromMin, toMin, extra = {}) {
  seq += 1;
  const now = Date.now();
  return Visitor.create({
    appointmentCode: `VS-T${String(seq).padStart(5, '0')}`,
    apartmentId: aptA._id,
    createdBy: owner.user._id,
    visitorName: `Khách ${seq}`,
    visitorPhone: `09120000${String(seq).padStart(2, '0')}`,
    numberOfPeople: 2,
    visitDate: dayRangeVN().start,
    timeFrom: new Date(now + fromMin * MIN),
    timeTo: new Date(now + toMin * MIN),
    ...extra,
  });
}

const createBody = (extra = {}) => ({
  apartmentId: String(aptA._id),
  visitorName: 'Nguyễn Khách',
  visitorPhone: '0912345678',
  numberOfPeople: 3,
  visitDate: vnDate(1),
  timeFrom: '09:00',
  timeTo: '11:00',
  ...extra,
});

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
  guard = await createUser({ role: 'staff', department: 'security' });
  reception = await createUser({ role: 'staff', department: 'reception' });
  owner = await createUser({ role: 'resident', fullName: 'Chủ Hộ' });
  member = await createUser({ role: 'resident', fullName: 'Thành Viên' });
  outsider = await createUser({ role: 'resident', fullName: 'Người Ngoài' });
  aptA = await Apartment.create({ code: 'A-101', floor: 1, area: 70 });
  aptB = await Apartment.create({ code: 'B-201', floor: 2, area: 60 });
  await live(owner, aptA, 'owner');
  await live(member, aptA, 'member');
  await live(outsider, aptB, 'owner');
});
afterAll(teardownDb);

describe('UC-16 đăng ký khách', () => {
  test('sinh mã hẹn, expected, giờ lưu theo giờ Việt Nam', async () => {
    const res = await as(owner).post('/api/visitors', createBody());
    expect(res.status).toBe(201);
    const v = res.body.data;
    expect(v.appointmentCode).toMatch(/^VS-[A-Z2-9]{6}$/);
    expect(v).toMatchObject({ status: 'expected', numberOfPeople: 3, isOverdue: false });
    // 09:00 giờ VN = 02:00 UTC
    expect(new Date(v.timeFrom).toISOString()).toBe(`${vnDate(1)}T02:00:00.000Z`);
  });

  test('giờ về trước giờ đến / quá khứ / quá 30 ngày / 0 người: 400', async () => {
    const bad = async (extra) => (await as(owner).post('/api/visitors', createBody(extra))).status;
    expect(await bad({ timeFrom: '11:00', timeTo: '09:00' })).toBe(400);
    expect(await bad({ visitDate: vnDate(-1) })).toBe(400);
    expect(await bad({ visitDate: vnDate(40) })).toBe(400);
    expect(await bad({ numberOfPeople: 0 })).toBe(400);
    expect(await bad({ timeFrom: '9h' })).toBe(400);
  });

  test('đăng ký cho căn hộ không ở: 403', async () => {
    const res = await as(outsider).post('/api/visitors', createBody());
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('NOT_APARTMENT_RESIDENT');
  });

  test('cư dân cùng căn thấy lịch; hủy khi expected; hủy lại: 409; người ngoài: 404', async () => {
    const created = (await as(owner).post('/api/visitors', createBody())).body.data;
    const mine = await as(member).get('/api/visitors/mine?limit=100');
    expect(mine.body.data.map((v) => v._id)).toContain(created._id);

    expect((await as(outsider).patch(`/api/visitors/${created._id}/cancel`, {})).status).toBe(404);
    const res = await as(member).patch(`/api/visitors/${created._id}/cancel`, { reason: 'Khách bận' });
    expect(res.body.data).toMatchObject({ status: 'cancelled', cancelReason: 'Khách bận' });
    expect((await as(member).patch(`/api/visitors/${created._id}/cancel`, {})).status).toBe(409);
  });
});

describe('UC-17 danh sách tại cổng', () => {
  test('mặc định hôm nay; tìm theo mã thì bỏ qua ngày; tìm theo SĐT', async () => {
    const today = await visitorAt(-10, 60);
    const tomorrow = (await as(owner).post('/api/visitors', createBody({ visitorPhone: '0987654321' }))).body.data;

    const list = await as(guard).get('/api/visitors?limit=100');
    const ids = list.body.data.map((v) => v._id);
    expect(ids).toContain(String(today._id));
    expect(ids).not.toContain(tomorrow._id);
    expect(list.body.data[0].apartmentId.code).toBe('A-101');

    const byCode = await as(guard).get(`/api/visitors?code=${tomorrow.appointmentCode.toLowerCase()}`);
    expect(byCode.body.data.map((v) => v._id)).toEqual([tomorrow._id]);

    const byPhone = await as(guard).get(`/api/visitors?date=${vnDate(1)}&phone=0987654`);
    expect(byPhone.body.data.map((v) => v._id)).toEqual([tomorrow._id]);
  });

  test('Lễ tân, Manager xem được; cư dân không; quá giờ chưa đến có isOverdue', async () => {
    const late = await visitorAt(-120, -30);
    const res = await as(reception).get('/api/visitors?limit=100');
    expect(res.status).toBe(200);
    expect(res.body.data.find((v) => v._id === String(late._id)).isOverdue).toBe(true);
    expect((await as(manager).get('/api/visitors')).status).toBe(200);
    expect((await as(owner).get('/api/visitors')).status).toBe(403);
  });
});

describe('UC-17, 18 check-in / check-out', () => {
  test('trong khung giờ: check-in, báo cư dân; bấm đồng thời 2 lần chỉ 1 thành công', async () => {
    const v = await visitorAt(-5, 60);
    const results = await Promise.all([
      as(guard).patch(`/api/visitors/${v._id}/check-in`),
      as(guard).patch(`/api/visitors/${v._id}/check-in`),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    const saved = await Visitor.findById(v._id);
    expect(saved).toMatchObject({ status: 'checked_in' });
    expect(String(saved.checkedInBy)).toBe(String(guard.user._id));
    expect(await Notification.exists({ userId: owner.user._id, type: 'visitor_checked_in' })).toBeTruthy();
  });

  test('đến sớm trong 30 phút: được; sớm hơn hoặc quá giờ: 409 VISITOR_OUT_OF_WINDOW', async () => {
    const early = await visitorAt(20, 120);
    expect((await as(guard).patch(`/api/visitors/${early._id}/check-in`)).status).toBe(200);

    const tooEarly = await visitorAt(45, 120);
    const r1 = await as(guard).patch(`/api/visitors/${tooEarly._id}/check-in`);
    expect(r1.status).toBe(409);
    expect(r1.body.error.code).toBe('VISITOR_OUT_OF_WINDOW');

    const tooLate = await visitorAt(-120, -1);
    expect((await as(guard).patch(`/api/visitors/${tooLate._id}/check-in`)).body.error.code).toBe(
      'VISITOR_OUT_OF_WINDOW'
    );
  });

  test('check-out chỉ khi đã check-in; ghi người và giờ; lần 2: 409', async () => {
    const v = await visitorAt(-5, 60);
    expect((await as(guard).patch(`/api/visitors/${v._id}/check-out`)).status).toBe(409);
    await as(guard).patch(`/api/visitors/${v._id}/check-in`);
    const res = await as(guard).patch(`/api/visitors/${v._id}/check-out`);
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('checked_out');
    expect(res.body.data.checkOutTime).toBeDefined();
    expect((await as(guard).patch(`/api/visitors/${v._id}/check-out`)).status).toBe(409);
  });

  test('Lễ tân, cư dân không check-in được: 403; lịch đã hủy: 409', async () => {
    const v = await visitorAt(-5, 60);
    expect((await as(reception).patch(`/api/visitors/${v._id}/check-in`)).status).toBe(403);
    expect((await as(owner).patch(`/api/visitors/${v._id}/check-in`)).status).toBe(403);
    await as(owner).patch(`/api/visitors/${v._id}/cancel`, {});
    expect((await as(guard).patch(`/api/visitors/${v._id}/check-in`)).body.error.code).toBe('INVALID_STATE');
  });

  test('allowedActions theo vai trò', async () => {
    const v = await visitorAt(-5, 60);
    expect((await as(guard).get(`/api/visitors/${v._id}`)).body.data.allowedActions).toEqual(['check-in']);
    expect((await as(owner).get(`/api/visitors/${v._id}`)).body.data.allowedActions).toEqual(['cancel']);
    expect((await as(reception).get(`/api/visitors/${v._id}`)).body.data.allowedActions).toEqual([]);
  });
});

describe('Hook: cư dân cuối cùng chuyển đi', () => {
  test('lịch khách expected của căn hộ bị hủy', async () => {
    const apt = await Apartment.create({ code: 'C-301', floor: 3, area: 50 });
    const solo = await createUser({ role: 'resident' });
    const rec = await ApartmentResident.create({
      apartmentId: apt._id,
      userId: solo.user._id,
      fullName: solo.user.fullName,
      relation: 'owner',
      status: 'active',
    });
    const v = await as(solo).post('/api/visitors', createBody({ apartmentId: String(apt._id) }));
    expect(v.status).toBe(201);

    expect((await as(manager).patch(`/api/residents/${rec._id}/move-out`, {})).status).toBe(200);
    expect((await Visitor.findById(v.body.data._id)).status).toBe('cancelled');
  });
});
