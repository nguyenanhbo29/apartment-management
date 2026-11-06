const request = require('supertest');
const app = require('../src/app');
const { setupDb, teardownDb, createUser, bearer } = require('./helpers');

let manager;
let resident;

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
  resident = await createUser({ role: 'resident' });
});
afterAll(teardownDb);

const api = (token) => ({
  get: (url) => request(app).get(url).set(bearer(token)),
  post: (url, body) => request(app).post(url).set(bearer(token)).send(body),
  patch: (url, body) => request(app).patch(url).set(bearer(token)).send(body),
});

describe('UC-03 View / Update Profile', () => {
  test('xem và cập nhật hồ sơ của mình', async () => {
    const me = await api(resident.token).get('/api/users/me');
    expect(me.body.data.email).toBe(resident.user.email);

    const upd = await api(resident.token).patch('/api/users/me', {
      fullName: 'Nguyễn Văn A',
      phone: '0901234567',
    });
    expect(upd.status).toBe(200);
    expect(upd.body.data).toMatchObject({ fullName: 'Nguyễn Văn A', phone: '0901234567' });
  });

  test('không thể tự đổi role/email qua /me', async () => {
    const res = await api(resident.token).patch('/api/users/me', {
      role: 'manager',
      email: 'hack@x.com',
      fullName: 'X',
    });
    expect(res.status).toBe(200);
    expect(res.body.data.role).toBe('resident');
    expect(res.body.data.email).toBe(resident.user.email);
  });

  test('số điện thoại sai định dạng', async () => {
    const res = await api(resident.token).patch('/api/users/me', { phone: 'abc' });
    expect(res.status).toBe(400);
  });
});

describe('UC-04 Manage User Accounts', () => {
  test('resident không gọi được API quản lý', async () => {
    expect((await api(resident.token).get('/api/users')).status).toBe(403);
    expect((await api(resident.token).post('/api/users', {})).status).toBe(403);
  });

  test('Manager tạo tài khoản, bắt đổi mật khẩu lần đầu', async () => {
    const res = await api(manager.token).post('/api/users', {
      email: 'New.Resident@Test.local',
      fullName: 'Cư dân mới',
      role: 'resident',
      password: 'Temp1234',
    });
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({
      email: 'new.resident@test.local',
      mustChangePassword: true,
      status: 'active',
      department: null,
    });

    const login = await request(app)
      .post('/api/auth/login')
      .send({ email: 'new.resident@test.local', password: 'Temp1234' });
    expect(login.body.data.user.mustChangePassword).toBe(true);
  });

  test('email trùng -> CONFLICT', async () => {
    const res = await api(manager.token).post('/api/users', {
      email: resident.user.email,
      fullName: 'Trùng',
      role: 'resident',
      password: 'Temp1234',
    });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('CONFLICT');
  });

  test('staff phải có bộ phận; role khác không được có', async () => {
    const noDept = await api(manager.token).post('/api/users', {
      email: 'staff1@test.local',
      fullName: 'NV',
      role: 'staff',
      password: 'Temp1234',
    });
    expect(noDept.status).toBe(400);

    const wrong = await api(manager.token).post('/api/users', {
      email: 'acc1@test.local',
      fullName: 'KT',
      role: 'accountant',
      department: 'security',
      password: 'Temp1234',
    });
    expect(wrong.status).toBe(400);

    const okRes = await api(manager.token).post('/api/users', {
      email: 'staff1@test.local',
      fullName: 'NV Bảo vệ',
      role: 'staff',
      department: 'security',
      password: 'Temp1234',
    });
    expect(okRes.status).toBe(201);
    expect(okRes.body.data.department).toBe('security');
  });

  test('danh sách có lọc, tìm kiếm, phân trang', async () => {
    const all = await api(manager.token).get('/api/users?limit=2');
    expect(all.body.data).toHaveLength(2);
    expect(all.body.meta.total).toBeGreaterThanOrEqual(4);

    const staff = await api(manager.token).get('/api/users?role=staff&department=security');
    expect(staff.body.data.every((u) => u.department === 'security')).toBe(true);

    const search = await api(manager.token).get('/api/users?q=bảo vệ');
    expect(search.body.data[0].email).toBe('staff1@test.local');
  });

  test('khóa rồi mở tài khoản', async () => {
    const target = await createUser();
    const lock = await api(manager.token).patch(`/api/users/${target.user._id}/status`, {
      status: 'inactive',
    });
    expect(lock.body.data.status).toBe('inactive');
    expect((await api(target.token).get('/api/users/me')).status).toBe(403);

    await api(manager.token).patch(`/api/users/${target.user._id}/status`, { status: 'active' });
    expect((await api(target.token).get('/api/users/me')).status).toBe(200);
  });

  test('Manager không tự khóa / tự đổi role mình', async () => {
    const id = manager.user._id;
    expect(
      (await api(manager.token).patch(`/api/users/${id}/status`, { status: 'inactive' })).status
    ).toBe(400);
    expect(
      (await api(manager.token).patch(`/api/users/${id}/role`, { role: 'resident' })).status
    ).toBe(400);
  });

  test('Manager đặt lại mật khẩu tạm', async () => {
    const target = await createUser();
    const res = await api(manager.token).post(`/api/users/${target.user._id}/reset-password`, {
      password: 'Reset1234',
    });
    expect(res.body.data.mustChangePassword).toBe(true);
    expect((await api(target.token).get('/api/users/me')).status).toBe(401);
  });

  test('id sai định dạng / không tồn tại', async () => {
    expect((await api(manager.token).get('/api/users/abc')).status).toBe(400);
    expect((await api(manager.token).get('/api/users/507f1f77bcf86cd799439011')).status).toBe(404);
  });
});

describe('UC-05 Manage Staff Roles', () => {
  test('gán role staff + bộ phận, rồi đổi sang role khác thì xóa bộ phận', async () => {
    const target = await createUser();
    const toStaff = await api(manager.token).patch(`/api/users/${target.user._id}/role`, {
      role: 'staff',
      department: 'technical',
    });
    expect(toStaff.body.data).toMatchObject({ role: 'staff', department: 'technical' });

    const toAcc = await api(manager.token).patch(`/api/users/${target.user._id}/role`, {
      role: 'accountant',
    });
    expect(toAcc.body.data).toMatchObject({ role: 'accountant', department: null });
  });

  test('bộ phận không hợp lệ', async () => {
    const target = await createUser();
    const res = await api(manager.token).patch(`/api/users/${target.user._id}/role`, {
      role: 'staff',
      department: 'kitchen',
    });
    expect(res.status).toBe(400);
  });
});
