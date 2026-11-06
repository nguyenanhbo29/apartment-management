const request = require('supertest');
const mongoose = require('mongoose');
const app = require('../src/app');
const { connectDb } = require('../src/config/db');
const User = require('../src/models/User');
const Notification = require('../src/models/Notification');
const { signToken, authorize } = require('../src/middleware/auth');
const { notifyUsers } = require('../src/services/notify.service');

beforeAll(async () => {
  await connectDb();
  await mongoose.connection.dropDatabase();
  await User.init();
});
afterAll(async () => {
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
});

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
    const res = await request(app).get('/api/me-check');
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHORIZED');
  });

  test('token hợp lệ qua được, tài khoản khóa bị chặn', async () => {
    const user = await User.create({
      email: 'a@x.com',
      passwordHash: await User.hashPassword('pw123456'),
      fullName: 'A',
      role: 'resident',
    });
    const token = signToken(user);
    const okRes = await request(app).get('/api/me-check').set('Authorization', `Bearer ${token}`);
    expect(okRes.status).toBe(200);
    expect(okRes.body.data.role).toBe('resident');

    user.status = 'inactive';
    await user.save();
    const blocked = await request(app).get('/api/me-check').set('Authorization', `Bearer ${token}`);
    expect(blocked.status).toBe(403);
    expect(blocked.body.error.code).toBe('ACCOUNT_INACTIVE');
  });

  test('email duy nhất', async () => {
    await expect(
      User.create({ email: 'A@x.com', passwordHash: 'x', fullName: 'B', role: 'resident' })
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
    const u = await User.findOne({ email: 'a@x.com' });
    const res = await notifyUsers({
      userIds: [u._id, u._id, null],
      type: 'test',
      title: 'Hi',
      link: { kind: 'x', id: '1' },
    });
    expect(res).toHaveLength(1);
    expect(await Notification.countDocuments({ userId: u._id })).toBe(1);
  });
});
