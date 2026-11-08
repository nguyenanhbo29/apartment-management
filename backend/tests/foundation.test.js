const request = require('supertest');
const app = require('../src/app');
const User = require('../src/models/User');
const Notification = require('../src/models/Notification');
const { authorize } = require('../src/middleware/auth');
const { notifyUsers } = require('../src/services/notify.service');
const { setupDb, teardownDb, createUser, bearer } = require('./helpers');

beforeAll(setupDb);
afterAll(teardownDb);

describe('khung backend', () => {
  test('health trả format chung', async () => {
    const res = await request(app).get('/api/health');
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.status).toBe('ok');
  });

  test('route không tồn tại trả NOT_FOUND', async () => {
    const res = await request(app).get('/api/nope');
    expect(res.status).toBe(404);
    expect(res.body).toMatchObject({ success: false, error: { code: 'NOT_FOUND' } });
  });

  test('không token -> UNAUTHORIZED', async () => {
    const res = await request(app).get('/api/users/me');
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHORIZED');
  });

  test('token hợp lệ qua được, tài khoản khóa bị chặn', async () => {
    const { user, token } = await createUser();
    const okRes = await request(app).get('/api/users/me').set(bearer(token));
    expect(okRes.status).toBe(200);
    expect(okRes.body.data.role).toBe('resident');
    expect(okRes.body.data.passwordHash).toBeUndefined();

    user.status = 'inactive';
    await user.save();
    const blocked = await request(app).get('/api/users/me').set(bearer(token));
    expect(blocked.status).toBe(403);
    expect(blocked.body.error.code).toBe('ACCOUNT_INACTIVE');
  });

  test('email duy nhất (không phân biệt hoa thường)', async () => {
    await createUser({ email: 'dup@x.com' });
    await expect(
      User.create({ email: 'DUP@x.com', passwordHash: 'x', fullName: 'B', role: 'resident' })
    ).rejects.toMatchObject({ code: 11000 });
  });

  test('authorize chặn sai role/department', () => {
    const run = (user, roles, opts) => {
      try {
        authorize(roles, opts)({ user }, {}, () => {});
        return 'pass';
      } catch (e) {
        return e.code;
      }
    };
    expect(run({ role: 'resident' }, ['manager'])).toBe('FORBIDDEN');
    expect(run({ role: 'manager' }, ['manager'])).toBe('pass');
    expect(
      run({ role: 'staff', department: 'technical' }, ['staff'], { departments: ['security'] })
    ).toBe('FORBIDDEN');
    expect(
      run({ role: 'staff', department: 'security' }, ['staff'], { departments: ['security'] })
    ).toBe('pass');
  });

  test('notifyUsers tạo thông báo, loại trùng', async () => {
    const { user } = await createUser();
    const res = await notifyUsers({
      userIds: [user._id, user._id, null],
      type: 'test',
      title: 'Hi',
      link: { kind: 'x', id: '1' },
    });
    expect(res).toHaveLength(1);
    expect(await Notification.countDocuments({ userId: user._id })).toBe(1);
  });
});
