const request = require('supertest');
const app = require('../src/app');
const User = require('../src/models/User');
const { setupDb, teardownDb, createUser, bearer } = require('./helpers');

beforeAll(setupDb);
afterAll(teardownDb);

const login = (email, password) => request(app).post('/api/auth/login').send({ email, password });

describe('UC-01 Login / Logout', () => {
  test('đăng nhập đúng trả token + user, không lộ hash', async () => {
    const { user, password } = await createUser({ email: 'Login@Test.local' });
    const res = await login('login@test.local', password);
    expect(res.status).toBe(200);
    expect(res.body.data.token).toEqual(expect.any(String));
    expect(res.body.data.user.email).toBe('login@test.local');
    expect(res.body.data.user.passwordHash).toBeUndefined();
    expect((await User.findById(user._id)).lastLoginAt).toBeInstanceOf(Date);
  });

  test('sai mật khẩu và sai email cùng một lỗi', async () => {
    const { user } = await createUser();
    const wrongPw = await login(user.email, 'wrong123');
    const wrongEmail = await login('nobody@test.local', 'wrong123');
    expect(wrongPw.status).toBe(401);
    expect(wrongPw.body.error).toEqual(wrongEmail.body.error);
    expect(wrongPw.body.error.code).toBe('INVALID_CREDENTIALS');
  });

  test('tài khoản inactive không đăng nhập được', async () => {
    const { user, password } = await createUser({ status: 'inactive' });
    const res = await login(user.email, password);
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('ACCOUNT_INACTIVE');
  });

  test('thiếu dữ liệu -> VALIDATION_ERROR', async () => {
    const res = await request(app).post('/api/auth/login').send({ email: 'abc' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(res.body.error.details.map((d) => d.field)).toEqual(
      expect.arrayContaining(['email', 'password'])
    );
  });

  test('logout cần token', async () => {
    const { token } = await createUser();
    expect((await request(app).post('/api/auth/logout')).status).toBe(401);
    expect((await request(app).post('/api/auth/logout').set(bearer(token))).status).toBe(200);
  });
});

describe('UC-02 Forgot Password', () => {
  test('luồng OTP đầy đủ, token cũ bị vô hiệu', async () => {
    const { user, token } = await createUser({ email: 'forgot@test.local' });

    const f = await request(app).post('/api/auth/forgot-password').send({ email: user.email });
    expect(f.status).toBe(200);
    const otp = f.body.data.devOtp;
    expect(otp).toMatch(/^\d{6}$/);

    // gửi lại ngay -> bị chặn 60 giây
    const again = await request(app).post('/api/auth/forgot-password').send({ email: user.email });
    expect(again.status).toBe(400);

    const wrongOtp = otp === '000000' ? '111111' : '000000';
    const bad = await request(app)
      .post('/api/auth/reset-password')
      .send({ email: user.email, otp: wrongOtp, newPassword: 'NewPass123' });
    expect(bad.status).toBe(400);

    const good = await request(app)
      .post('/api/auth/reset-password')
      .send({ email: user.email, otp, newPassword: 'NewPass123' });
    expect(good.status).toBe(200);

    // OTP dùng 1 lần
    const reuse = await request(app)
      .post('/api/auth/reset-password')
      .send({ email: user.email, otp, newPassword: 'Other1234' });
    expect(reuse.status).toBe(400);

    expect((await login(user.email, 'NewPass123')).status).toBe(200);
    expect((await request(app).get('/api/users/me').set(bearer(token))).status).toBe(401);
  });

  test('email không tồn tại vẫn trả thành công, không có OTP', async () => {
    const res = await request(app)
      .post('/api/auth/forgot-password')
      .send({ email: 'ghost@test.local' });
    expect(res.status).toBe(200);
    expect(res.body.data.devOtp).toBeUndefined();
  });

  test('khóa OTP sau 5 lần sai', async () => {
    const { user } = await createUser();
    const f = await request(app).post('/api/auth/forgot-password').send({ email: user.email });
    const otp = f.body.data.devOtp;
    const wrongOtp = otp === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i += 1) {
      await request(app)
        .post('/api/auth/reset-password')
        .send({ email: user.email, otp: wrongOtp, newPassword: 'NewPass123' });
    }
    const res = await request(app)
      .post('/api/auth/reset-password')
      .send({ email: user.email, otp, newPassword: 'NewPass123' });
    expect(res.status).toBe(400);
    expect(res.body.error.message).toMatch(/quá nhiều lần/);
  });

  test('mật khẩu mới yếu bị từ chối', async () => {
    const res = await request(app)
      .post('/api/auth/reset-password')
      .send({ email: 'a@test.local', otp: '123456', newPassword: 'short' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });
});

describe('Đổi mật khẩu (bắt buộc ở lần đăng nhập đầu)', () => {
  test('đổi mật khẩu tắt mustChangePassword và cấp token mới', async () => {
    const { user, token, password } = await createUser({ mustChangePassword: true });
    const wrong = await request(app)
      .post('/api/auth/change-password')
      .set(bearer(token))
      .send({ currentPassword: 'nope', newPassword: 'Brand1234' });
    expect(wrong.status).toBe(400);

    const res = await request(app)
      .post('/api/auth/change-password')
      .set(bearer(token))
      .send({ currentPassword: password, newPassword: 'Brand1234' });
    expect(res.status).toBe(200);
    expect(res.body.data.user.mustChangePassword).toBe(false);

    const newToken = res.body.data.token;
    expect((await request(app).get('/api/users/me').set(bearer(newToken))).status).toBe(200);
    expect((await request(app).get('/api/users/me').set(bearer(token))).status).toBe(401);
    expect((await login(user.email, 'Brand1234')).status).toBe(200);
  });
});
