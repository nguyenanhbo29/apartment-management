const request = require('supertest');
const app = require('../src/app');
const {
  setupDb,
  teardownDb,
  createUser,
  bearer,
  createServiceRequestDoc,
} = require('./helpers');

let manager;
let tech1;
let tech2;
let security;
let resident;

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
  tech1 = await createUser({ role: 'staff', department: 'technical', fullName: 'An Kỹ Thuật' });
  tech2 = await createUser({ role: 'staff', department: 'technical', fullName: 'Bình Kỹ Thuật', status: 'inactive' });
  security = await createUser({ role: 'staff', department: 'security', fullName: 'Cường Bảo Vệ' });
  resident = await createUser({ role: 'resident' });
  await createServiceRequestDoc({ assignedStaffId: tech1.user._id, status: 'in_progress' });
  await createServiceRequestDoc({ assignedStaffId: tech1.user._id, status: 'assigned' });
  await createServiceRequestDoc({ assignedStaffId: tech1.user._id, status: 'closed' }); // không tính
});
afterAll(teardownDb);

const get = (actor, url) => request(app).get(url).set(bearer(actor.token));

describe('UC-40 GET /api/staff', () => {
  test('Manager thấy mọi Staff kèm số việc đang mở, không lẫn vai trò khác', async () => {
    const res = await get(manager, '/api/staff');
    expect(res.status).toBe(200);
    expect(res.body.meta.total).toBe(3);
    const t1 = res.body.data.find((s) => s._id === String(tech1.user._id));
    expect(t1).toMatchObject({ openRequests: 2, openTasks: 0, openWork: 2 });
    expect(t1.passwordHash).toBeUndefined();
  });

  test('lọc theo bộ phận và trạng thái (dùng cho màn phân công)', async () => {
    const res = await get(manager, '/api/staff?department=technical&status=active');
    expect(res.body.data.map((s) => s.fullName)).toEqual(['An Kỹ Thuật']);
  });

  test('bộ phận không hợp lệ: 400', async () => {
    expect((await get(manager, '/api/staff?department=accounting')).status).toBe(400);
  });

  test('Staff, Resident không xem được: 403', async () => {
    expect((await get(security, '/api/staff')).status).toBe(403);
    expect((await get(resident, '/api/staff')).status).toBe(403);
  });
});

describe('UC-40 GET /api/staff/departments', () => {
  test('đủ 4 bộ phận cố định, đếm nhân viên active/tổng', async () => {
    const res = await get(resident, '/api/staff/departments');
    expect(res.status).toBe(200);
    expect(res.body.data.map((d) => d.code)).toEqual(['reception', 'security', 'technical', 'facility']);
    expect(res.body.data.find((d) => d.code === 'technical')).toMatchObject({ activeStaff: 1, totalStaff: 2 });
    expect(res.body.data.find((d) => d.code === 'reception')).toMatchObject({ activeStaff: 0, totalStaff: 0 });
  });
});
