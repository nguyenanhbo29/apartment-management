const request = require('supertest');
const app = require('../src/app');
const ApartmentResident = require('../src/models/ApartmentResident');
const { setupDb, teardownDb, createUser, bearer } = require('./helpers');

let manager;
let accountant;
let reception;
let security;
let resident;

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
  accountant = await createUser({ role: 'accountant' });
  reception = await createUser({ role: 'staff', department: 'reception' });
  security = await createUser({ role: 'staff', department: 'security' });
  resident = await createUser({ role: 'resident' });
});
afterAll(teardownDb);

const as = (actor) => ({
  get: (url) => request(app).get(url).set(bearer(actor.token)),
  post: (url, body) => request(app).post(url).set(bearer(actor.token)).send(body),
  patch: (url, body) => request(app).patch(url).set(bearer(actor.token)).send(body),
  del: (url) => request(app).delete(url).set(bearer(actor.token)),
});

describe('UC-06 Manage Apartments', () => {
  let aptId;

  test('Manager tạo căn hộ, mã tự viết hoa, mặc định trống', async () => {
    const res = await as(manager).post('/api/apartments', {
      code: 'a-101',
      floor: 1,
      area: 72.5,
      bedrooms: 2,
    });
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({ code: 'A-101', status: 'vacant', buildingId: 'main' });
    aptId = res.body.data._id;
  });

  test('mã căn hộ trùng -> CONFLICT', async () => {
    const res = await as(manager).post('/api/apartments', { code: 'A-101', floor: 1, area: 50 });
    expect(res.status).toBe(409);
  });

  test('dữ liệu sai -> VALIDATION_ERROR', async () => {
    const res = await as(manager).post('/api/apartments', { code: 'A 1!', floor: 1, area: -3 });
    expect(res.status).toBe(400);
    expect(res.body.error.details.map((d) => d.field)).toEqual(
      expect.arrayContaining(['code', 'area'])
    );
  });

  test('chỉ Manager được tạo/sửa/xóa', async () => {
    for (const actor of [accountant, reception, resident]) {
      expect((await as(actor).post('/api/apartments', { code: 'X1', floor: 1, area: 1 })).status).toBe(403);
      expect((await as(actor).patch(`/api/apartments/${aptId}`, { area: 1 })).status).toBe(403);
    }
  });

  test('Manager, Kế toán, Lễ tân xem danh sách; Bảo vệ và Cư dân không', async () => {
    await as(manager).post('/api/apartments', { code: 'B-201', floor: 2, area: 90 });
    for (const actor of [manager, accountant, reception]) {
      const res = await as(actor).get('/api/apartments');
      expect(res.status).toBe(200);
      expect(res.body.meta.total).toBe(2);
    }
    expect((await as(security).get('/api/apartments')).status).toBe(403);
    expect((await as(resident).get('/api/apartments')).status).toBe(403);
  });

  test('lọc theo tầng, tìm theo mã', async () => {
    const byFloor = await as(manager).get('/api/apartments?floor=2');
    expect(byFloor.body.data.map((a) => a.code)).toEqual(['B-201']);
    const byCode = await as(manager).get('/api/apartments?q=a-1');
    expect(byCode.body.data.map((a) => a.code)).toEqual(['A-101']);
  });

  test('sửa căn hộ, không đổi được trạng thái bằng tay', async () => {
    const res = await as(manager).patch(`/api/apartments/${aptId}`, {
      area: 75,
      status: 'occupied',
    });
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ area: 75, status: 'vacant' });
  });

  test('xóa: căn chưa có hồ sơ thì được, đã có thì không', async () => {
    const tmp = await as(manager).post('/api/apartments', { code: 'TMP', floor: 9, area: 10 });
    expect((await as(manager).del(`/api/apartments/${tmp.body.data._id}`)).status).toBe(200);

    await ApartmentResident.create({
      apartmentId: aptId,
      fullName: 'X',
      relation: 'member',
      status: 'ended',
    });
    const res = await as(manager).del(`/api/apartments/${aptId}`);
    expect(res.status).toBe(409);
  });
});
