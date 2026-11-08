const request = require('supertest');
const app = require('../src/app');
const Apartment = require('../src/models/Apartment');
const ApartmentResident = require('../src/models/ApartmentResident');
const Notification = require('../src/models/Notification');
const Vehicle = require('../src/models/Vehicle');
const vehicleService = require('../src/services/vehicle.service');
const { setupDb, teardownDb, createUser, bearer } = require('./helpers');

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);

let manager;
let accountant;
let guard;
let tech;
let owner;
let member;
let outsider;
let aptA;
let aptB;

const as = (actor) => ({
  get: (url) => request(app).get(url).set(bearer(actor.token)),
  post: (url, body) => request(app).post(url).set(bearer(actor.token)).send(body),
  patch: (url, body) => request(app).patch(url).set(bearer(actor.token)).send(body),
});

async function live(actor, apartment, relation) {
  await ApartmentResident.create({
    apartmentId: apartment._id,
    userId: actor.user._id,
    fullName: actor.user.fullName,
    relation,
    status: 'active',
  });
}

async function registerVia(actor, plateNumber, apartment = aptA, extra = {}) {
  return as(actor).post('/api/vehicles', {
    apartmentId: String(apartment._id),
    type: 'motorbike',
    plateNumber,
    ...extra,
  });
}

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
  accountant = await createUser({ role: 'accountant' });
  guard = await createUser({ role: 'staff', department: 'security', fullName: 'Bảo Vệ' });
  tech = await createUser({ role: 'staff', department: 'technical' });
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

describe('UC-13 đăng ký xe', () => {
  test('chuẩn hóa biển số, pending, kèm ảnh, báo Bảo vệ', async () => {
    const res = await request(app)
      .post('/api/vehicles')
      .set(bearer(owner.token))
      .field('apartmentId', String(aptA._id))
      .field('type', 'car')
      .field('plateNumber', ' 30a-123.45 ')
      .field('brand', 'Toyota')
      .attach('images', PNG, { filename: 'xe.png', contentType: 'image/png' });
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({ plateNumber: '30A12345', status: 'pending', type: 'car' });
    expect(res.body.data.imageUrl).toMatch(/^\/uploads\/vehicles\/.+\.png$/);
    expect(await Notification.exists({ userId: guard.user._id, type: 'vehicle_submitted' })).toBeTruthy();
  });

  test('biển số sai định dạng: 400; căn hộ không ở: 403; Staff: 403', async () => {
    const bad = await registerVia(owner, 'ABC-1234');
    expect(bad.status).toBe(400);
    expect(bad.body.error.details[0].field).toBe('plateNumber');
    expect((await registerVia(outsider, '29B11111', aptA)).status).toBe(403);
    expect((await registerVia(guard, '29B11111')).status).toBe(403);
  });
});

describe('UC-14 duyệt xe và chống trùng biển số', () => {
  test('nhiều hồ sơ pending trùng biển được; duyệt trước thắng, sau bị 409', async () => {
    const a = await registerVia(owner, '51F-678.90');
    const b = await registerVia(outsider, '51f67890', aptB);
    expect([a.status, b.status]).toEqual([201, 201]);

    const ok = await as(guard).patch(`/api/vehicles/${a.body.data._id}/approve`);
    expect(ok.status).toBe(200);
    expect(ok.body.data).toMatchObject({ status: 'approved', reviewedBy: String(guard.user._id) });
    expect(await Notification.exists({ userId: owner.user._id, type: 'vehicle_approved' })).toBeTruthy();

    const dup = await as(guard).patch(`/api/vehicles/${b.body.data._id}/approve`);
    expect(dup.status).toBe(409);
    expect(dup.body.error.code).toBe('VEHICLE_PLATE_DUPLICATE');

    // Đăng ký mới khi đã có xe approved (nhập khác định dạng): chặn ngay
    const again = await registerVia(member, '51F 678 90');
    expect(again.status).toBe(409);
    expect(again.body.error.code).toBe('VEHICLE_PLATE_DUPLICATE');
  });

  test('duyệt đồng thời 2 hồ sơ trùng biển: đúng 1 thành công', async () => {
    const a = await registerVia(owner, '43A11122');
    const b = await registerVia(outsider, '43-A-111.22', aptB);
    const results = await Promise.all([
      as(guard).patch(`/api/vehicles/${a.body.data._id}/approve`),
      as(guard).patch(`/api/vehicles/${b.body.data._id}/approve`),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(await Vehicle.countDocuments({ plateNumber: '43A11122', status: 'approved' })).toBe(1);
  });

  test('duyệt lại hồ sơ đã xử lý: 409 INVALID_STATE; id không tồn tại: 404', async () => {
    const v = await registerVia(owner, '88C33333');
    await as(guard).patch(`/api/vehicles/${v.body.data._id}/approve`);
    const twice = await as(guard).patch(`/api/vehicles/${v.body.data._id}/approve`);
    expect(twice.status).toBe(409);
    expect(twice.body.error.code).toBe('INVALID_STATE');
    expect((await as(guard).patch('/api/vehicles/000000000000000000000000/approve')).status).toBe(404);
  });

  test('chỉ Bảo vệ duyệt được; từ chối bắt buộc lý do, báo cư dân', async () => {
    const v = await registerVia(owner, '77D44444');
    const id = v.body.data._id;
    expect((await as(tech).patch(`/api/vehicles/${id}/approve`)).status).toBe(403);
    expect((await as(manager).patch(`/api/vehicles/${id}/approve`)).status).toBe(403);
    expect((await as(owner).patch(`/api/vehicles/${id}/approve`)).status).toBe(403);

    expect((await as(guard).patch(`/api/vehicles/${id}/reject`, {})).status).toBe(400);
    const res = await as(guard).patch(`/api/vehicles/${id}/reject`, { reason: 'Ảnh cà vẹt mờ' });
    expect(res.body.data).toMatchObject({ status: 'rejected', rejectReason: 'Ảnh cà vẹt mờ' });
    expect(await Notification.exists({ userId: owner.user._id, type: 'vehicle_rejected' })).toBeTruthy();
  });

  test('xe đã inactive: biển số đăng ký và duyệt lại được', async () => {
    const v = await registerVia(owner, '36K55555');
    await as(guard).patch(`/api/vehicles/${v.body.data._id}/approve`);
    await as(owner).patch(`/api/vehicles/${v.body.data._id}/deactivate`);

    const again = await registerVia(outsider, '36K-555.55', aptB);
    expect(again.status).toBe(201);
    expect((await as(guard).patch(`/api/vehicles/${again.body.data._id}/approve`)).status).toBe(200);
  });
});

describe('UC-15 danh sách và phạm vi xem', () => {
  test('cư dân chỉ thấy xe của căn mình; người ngoài xem chi tiết: 404', async () => {
    const v = await registerVia(owner, '15B12121');
    const mine = await as(member).get('/api/vehicles/mine?limit=100');
    expect(mine.body.data.every((x) => x.apartmentId.code === 'A-101')).toBe(true);
    expect(mine.body.data.map((x) => x._id)).toContain(v.body.data._id);
    expect((await as(outsider).get(`/api/vehicles/${v.body.data._id}`)).status).toBe(404);
  });

  test('tra cứu biển số chuẩn hóa một phần; Kế toán xem được; cư dân không', async () => {
    const res = await as(guard).get('/api/vehicles?plate=30a-123');
    expect(res.status).toBe(200);
    expect(res.body.data.map((x) => x.plateNumber)).toContain('30A12345');
    expect(res.body.data[0].ownerId.fullName).toBeDefined();
    expect((await as(accountant).get('/api/vehicles?status=approved')).status).toBe(200);
    expect((await as(owner).get('/api/vehicles')).status).toBe(403);
    expect((await as(tech).get('/api/vehicles')).status).toBe(403);
  });

  test('allowedActions theo vai trò', async () => {
    const v = await registerVia(owner, '20C98765');
    const id = v.body.data._id;
    expect((await as(guard).get(`/api/vehicles/${id}`)).body.data.allowedActions).toEqual(['approve', 'reject']);
    expect((await as(owner).get(`/api/vehicles/${id}`)).body.data.allowedActions).toEqual(['deactivate']);
    expect((await as(accountant).get(`/api/vehicles/${id}`)).body.data.allowedActions).toEqual([]);
  });
});

describe('Ngừng sử dụng và xe tính phí (cho Người 1)', () => {
  test('thành viên cùng căn hủy hồ sơ pending; người ngoài: 404; hủy lại: 409', async () => {
    const v = await registerVia(owner, '61H10101');
    const id = v.body.data._id;
    expect((await as(outsider).patch(`/api/vehicles/${id}/deactivate`)).status).toBe(404);
    const res = await as(member).patch(`/api/vehicles/${id}/deactivate`);
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('inactive');
    expect(res.body.data.deactivatedAt).toBeDefined();
    expect((await as(member).patch(`/api/vehicles/${id}/deactivate`)).status).toBe(409);
  });

  test('Manager ngừng xe đã duyệt thì báo chủ xe', async () => {
    const v = await registerVia(owner, '62H20202');
    await as(guard).patch(`/api/vehicles/${v.body.data._id}/approve`);
    expect((await as(manager).patch(`/api/vehicles/${v.body.data._id}/deactivate`)).status).toBe(200);
    expect(await Notification.exists({ userId: owner.user._id, type: 'vehicle_deactivated' })).toBeTruthy();
  });

  test('getBillableVehicles chỉ trả xe approved của đúng căn hộ', async () => {
    const billable = await vehicleService.getBillableVehicles(aptA._id);
    expect(billable.length).toBeGreaterThan(0);
    expect(billable.every((v) => v.status === 'approved' && String(v.apartmentId) === String(aptA._id))).toBe(true);
    const expected = await Vehicle.countDocuments({ apartmentId: aptA._id, status: 'approved' });
    expect(billable).toHaveLength(expected);
  });
});
