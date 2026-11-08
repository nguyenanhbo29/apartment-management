const mongoose = require('mongoose');
const request = require('supertest');
const app = require('../src/app');
const Apartment = require('../src/models/Apartment');
const ApartmentResident = require('../src/models/ApartmentResident');
const Vehicle = require('../src/models/Vehicle');
const {
  setupDb,
  teardownDb,
  createUser,
  bearer,
  createServiceRequestDoc,
} = require('./helpers');

let manager;
const api = (token) => ({
  post: (url, body) => request(app).post(url).set(bearer(token)).send(body),
  patch: (url, body) => request(app).patch(url).set(bearer(token)).send(body),
});

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
});
afterAll(teardownDb);

describe('Môi trường test', () => {
  test('hỗ trợ transaction: lỗi giữa chừng thì rollback', async () => {
    const col = mongoose.connection.db.collection('tx_probe');
    const session = await mongoose.startSession();
    await expect(
      session.withTransaction(async () => {
        await col.insertOne({ a: 1 }, { session });
        throw new Error('rollback');
      })
    ).rejects.toThrow('rollback');
    await session.endSession();
    expect(await col.countDocuments()).toBe(0);
  });
});

describe('onResidentMovedOut (gọi từ UC-11 move-out)', () => {
  async function addResident(apt, relation) {
    const u = await createUser({ role: 'resident' });
    const res = await api(manager.token).post(`/api/apartments/${apt._id}/residents`, {
      fullName: u.user.fullName,
      relation,
      userId: String(u.user._id),
    });
    expect(res.status).toBe(201);
    return { ...u, recId: res.body.data._id };
  }

  const addVehicle = (apt, owner, plateNumber, status) =>
    Vehicle.create({ apartmentId: apt._id, ownerId: owner.user._id, type: 'motorbike', plateNumber, status });

  test('cư dân cuối cùng chuyển đi: xe approved/pending chuyển inactive', async () => {
    const apt = await Apartment.create({ code: 'H-101', floor: 1, area: 50 });
    const owner = await addResident(apt, 'owner');
    const approved = await addVehicle(apt, owner, '30A11111', 'approved');
    const pending = await addVehicle(apt, owner, '30A22222', 'pending');
    const rejected = await addVehicle(apt, owner, '30A33333', 'rejected');

    const res = await api(manager.token).patch(`/api/residents/${owner.recId}/move-out`, {});
    expect(res.status).toBe(200);

    expect((await Vehicle.findById(approved._id)).status).toBe('inactive');
    expect((await Vehicle.findById(approved._id)).deactivatedAt).toBeInstanceOf(Date);
    expect((await Vehicle.findById(pending._id)).status).toBe('inactive');
    expect((await Vehicle.findById(rejected._id)).status).toBe('rejected');
  });

  test('căn hộ còn người ở: xe giữ nguyên', async () => {
    const apt = await Apartment.create({ code: 'H-102', floor: 1, area: 50 });
    const owner = await addResident(apt, 'owner');
    const member = await addResident(apt, 'member');
    const v = await addVehicle(apt, owner, '30A44444', 'approved');

    await api(manager.token).patch(`/api/residents/${member.recId}/move-out`, {});

    expect((await Vehicle.findById(v._id)).status).toBe('approved');
    expect(await ApartmentResident.countDocuments({ apartmentId: apt._id, status: 'active' })).toBe(1);
  });
});

describe('assertNoOpenWork (gọi từ UC-05 khóa / đổi vai trò)', () => {
  test('Staff còn phiếu đang mở: không khóa, không đổi vai trò, không đổi bộ phận', async () => {
    const staff = await createUser({ role: 'staff', department: 'technical' });
    await createServiceRequestDoc({ assignedStaffId: staff.user._id, status: 'in_progress' });
    const url = `/api/users/${staff.user._id}`;

    const lock = await api(manager.token).patch(`${url}/status`, { status: 'inactive' });
    expect(lock.status).toBe(409);
    expect(lock.body.error.code).toBe('HAS_OPEN_WORK');

    const toResident = await api(manager.token).patch(`${url}/role`, { role: 'resident' });
    expect(toResident.status).toBe(409);

    const move = await api(manager.token).patch(`${url}/role`, { role: 'staff', department: 'security' });
    expect(move.status).toBe(409);
  });

  test('Staff chỉ có phiếu đã đóng: khóa được', async () => {
    const staff = await createUser({ role: 'staff', department: 'technical' });
    await createServiceRequestDoc({ assignedStaffId: staff.user._id, status: 'closed' });

    const res = await api(manager.token).patch(`/api/users/${staff.user._id}/status`, {
      status: 'inactive',
    });
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('inactive');
  });
});
