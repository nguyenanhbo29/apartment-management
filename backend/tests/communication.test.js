const request = require('supertest');
const app = require('../src/app');
const Apartment = require('../src/models/Apartment');
const ApartmentResident = require('../src/models/ApartmentResident');
const Announcement = require('../src/models/Announcement');
const Notification = require('../src/models/Notification');
const { setupDb, teardownDb, createUser, bearer } = require('./helpers');

let manager;
let accountant;
let staff;
let resA; // ở căn A-101 tầng 1
let resB; // ở căn B-501 tầng 5
let resGone; // đã chuyển đi khỏi A-101
let locked; // tài khoản bị khóa
let aptA;
let aptB;

const as = (actor) => ({
  get: (url) => request(app).get(url).set(bearer(actor.token)),
  post: (url, body) => request(app).post(url).set(bearer(actor.token)).send(body),
  patch: (url, body) => request(app).patch(url).set(bearer(actor.token)).send(body),
});

const post = (body) =>
  as(manager).post('/api/announcements', { title: 'T', content: 'Nội dung', ...body });

const titlesFor = async (actor) =>
  (await as(actor).get('/api/announcements')).body.data.map((a) => a.title);

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
  accountant = await createUser({ role: 'accountant' });
  staff = await createUser({ role: 'staff', department: 'security' });
  resA = await createUser({ role: 'resident' });
  resB = await createUser({ role: 'resident' });
  resGone = await createUser({ role: 'resident' });
  locked = await createUser({ role: 'resident', status: 'inactive' });

  aptA = await Apartment.create({ code: 'A-101', floor: 1, area: 70 });
  aptB = await Apartment.create({ code: 'B-501', floor: 5, area: 70 });
  const rec = (user, apt, status = 'active') =>
    ApartmentResident.create({
      apartmentId: apt._id,
      userId: user.user._id,
      fullName: user.user.fullName,
      relation: 'member',
      status,
    });
  await rec(resA, aptA);
  await rec(resB, aptB);
  await rec(resGone, aptA, 'ended');
  await rec(locked, aptA);
});
afterAll(teardownDb);

const notified = async (type = 'announcement') =>
  (await Notification.find({ type })).map((n) => String(n.userId));

describe('UC-43 Publish Announcements', () => {
  beforeEach(async () => {
    await Announcement.deleteMany({});
    await Notification.deleteMany({});
  });

  test('chỉ Manager được đăng', async () => {
    const res = await as(resA).post('/api/announcements', {
      title: 'x',
      content: 'y',
      audience: { type: 'all' },
    });
    expect(res.status).toBe(403);
  });

  test('gửi tất cả: mọi tài khoản active trừ người đăng nhận thông báo', async () => {
    const res = await post({ title: 'Cúp nước', audience: { type: 'all' } });
    expect(res.status).toBe(201);
    expect(res.body.data.recipientCount).toBe(5);

    const ids = await notified();
    expect(ids).toEqual(
      expect.arrayContaining([accountant, staff, resA, resB, resGone].map((u) => String(u.user._id)))
    );
    expect(ids).not.toContain(String(manager.user._id));
    expect(ids).not.toContain(String(locked.user._id));

    const n = await Notification.findOne({ userId: resA.user._id });
    expect(n).toMatchObject({ title: 'Bảng tin: Cúp nước', link: { kind: 'announcement' } });
  });

  test('theo vai trò', async () => {
    await post({ audience: { type: 'roles', roles: ['staff', 'accountant'] } });
    expect((await notified()).sort()).toEqual(
      [staff, accountant].map((u) => String(u.user._id)).sort()
    );
  });

  test('theo tầng: chỉ cư dân đang ở, bỏ người đã chuyển đi và tài khoản khóa', async () => {
    await post({ audience: { type: 'floors', floors: [1] } });
    expect(await notified()).toEqual([String(resA.user._id)]);
  });

  test('theo căn hộ', async () => {
    await post({ audience: { type: 'apartments', apartmentIds: [String(aptB._id)] } });
    expect(await notified()).toEqual([String(resB.user._id)]);
  });

  test('dữ liệu đối tượng sai', async () => {
    expect((await post({ audience: { type: 'roles', roles: [] } })).status).toBe(400);
    expect((await post({ audience: { type: 'everyone' } })).status).toBe(400);
    const ghost = await post({
      audience: { type: 'apartments', apartmentIds: ['507f1f77bcf86cd799439011'] },
    });
    expect(ghost.status).toBe(400);
    expect((await post({ audience: { type: 'all' }, expiresAt: '2000-01-01' })).status).toBe(400);
  });
});

describe('UC-44 View Announcements', () => {
  let removedId;

  beforeAll(async () => {
    await Announcement.deleteMany({});
    await post({ title: 'Chung', audience: { type: 'all' } });
    await post({ title: 'Nhân viên', audience: { type: 'roles', roles: ['staff'] } });
    await post({ title: 'Tầng 1', audience: { type: 'floors', floors: [1] } });
    await post({ title: 'Căn B', audience: { type: 'apartments', apartmentIds: [String(aptB._id)] } });
    await post({ title: 'Quan trọng', audience: { type: 'all' }, isPinned: true });
    removedId = (await post({ title: 'Đã gỡ', audience: { type: 'all' } })).body.data._id;
    await as(manager).patch(`/api/announcements/${removedId}/remove`);
    await Announcement.create({
      title: 'Hết hạn',
      content: 'x',
      audience: { type: 'all' },
      expiresAt: new Date(Date.now() - 1000),
      createdBy: manager.user._id,
    });
  });

  test('mỗi người chỉ thấy bảng tin dành cho mình, tin ghim lên đầu', async () => {
    expect(await titlesFor(resA)).toEqual(['Quan trọng', 'Tầng 1', 'Chung']);
    expect(await titlesFor(resB)).toEqual(['Quan trọng', 'Căn B', 'Chung']);
    expect(await titlesFor(staff)).toEqual(['Quan trọng', 'Nhân viên', 'Chung']);
    expect(await titlesFor(resGone)).toEqual(['Quan trọng', 'Chung']);
  });

  test('Manager thấy tất cả tin đang hiệu lực; includeInactive thấy cả tin đã gỡ/hết hạn', async () => {
    expect(await titlesFor(manager)).toHaveLength(5);
    const all = await as(manager).get('/api/announcements?includeInactive=true');
    expect(all.body.data.map((a) => a.title)).toEqual(
      expect.arrayContaining(['Đã gỡ', 'Hết hạn'])
    );
    // cư dân truyền includeInactive cũng không có tác dụng
    const res = await as(resA).get('/api/announcements?includeInactive=true');
    expect(res.body.data.map((a) => a.title)).not.toContain('Đã gỡ');
  });

  test('xem chi tiết: không xem được tin không dành cho mình hoặc đã gỡ', async () => {
    const list = await as(resB).get('/api/announcements');
    const forB = list.body.data.find((a) => a.title === 'Căn B');
    expect((await as(resB).get(`/api/announcements/${forB._id}`)).status).toBe(200);
    expect((await as(resA).get(`/api/announcements/${forB._id}`)).status).toBe(404);
    expect((await as(resA).get(`/api/announcements/${removedId}`)).status).toBe(404);
    expect((await as(manager).get(`/api/announcements/${removedId}`)).status).toBe(200);
  });

  test('ghim / bỏ ghim; không gỡ 2 lần', async () => {
    const list = await as(manager).get('/api/announcements');
    const chung = list.body.data.find((a) => a.title === 'Chung');
    await as(manager).patch(`/api/announcements/${chung._id}/pin`, { isPinned: true });
    expect((await titlesFor(resA))[0]).toBe('Chung');
    await as(manager).patch(`/api/announcements/${chung._id}/pin`, { isPinned: false });

    expect((await as(manager).patch(`/api/announcements/${removedId}/remove`)).status).toBe(400);
    expect((await as(resA).patch(`/api/announcements/${chung._id}/pin`, { isPinned: true })).status).toBe(403);
  });
});

describe('UC-45 / UC-46 Notifications', () => {
  beforeAll(async () => {
    await Notification.deleteMany({});
    const mk = (user, title, isRead = false) =>
      Notification.create({ userId: user.user._id, type: 't', title, isRead });
    await mk(resA, 'Một');
    await mk(resA, 'Hai');
    await mk(resA, 'Cũ', true);
    await mk(resB, 'Của B');
  });

  test('chỉ thấy thông báo của mình, mới nhất trước, kèm số chưa đọc', async () => {
    const res = await as(resA).get('/api/notifications');
    expect(res.body.data.map((n) => n.title)).toEqual(['Cũ', 'Hai', 'Một']);
    expect(res.body.meta.unread).toBe(2);

    const unread = await as(resA).get('/api/notifications?unreadOnly=true');
    expect(unread.body.data).toHaveLength(2);
    expect((await as(resA).get('/api/notifications/unread-count')).body.data.count).toBe(2);
  });

  test('đánh dấu đã đọc; không đọc được thông báo của người khác', async () => {
    const bNote = await Notification.findOne({ userId: resB.user._id });
    expect((await as(resA).patch(`/api/notifications/${bNote._id}/read`)).status).toBe(404);

    const mine = await Notification.findOne({ userId: resA.user._id, title: 'Một' });
    const res = await as(resA).patch(`/api/notifications/${mine._id}/read`);
    expect(res.body.data.isRead).toBe(true);
    expect((await as(resA).get('/api/notifications/unread-count')).body.data.count).toBe(1);
  });

  test('đánh dấu tất cả đã đọc chỉ ảnh hưởng người gọi', async () => {
    const res = await as(resA).patch('/api/notifications/read-all');
    expect(res.body.data.updated).toBe(1);
    expect((await as(resA).get('/api/notifications/unread-count')).body.data.count).toBe(0);
    expect((await as(resB).get('/api/notifications/unread-count')).body.data.count).toBe(1);
  });

  test('sự kiện nghiệp vụ M2 sinh thông báo xem được qua API', async () => {
    const owner = await createUser({ role: 'resident' });
    const apt = await Apartment.create({ code: 'C-1', floor: 3, area: 50 });
    await ApartmentResident.create({
      apartmentId: apt._id,
      userId: owner.user._id,
      fullName: 'Chủ C',
      relation: 'owner',
      status: 'active',
    });
    const reg = await as(owner).post(`/api/apartments/${apt._id}/registrations`, {
      fullName: 'Con',
      relation: 'member',
    });
    await as(manager).patch(`/api/residents/${reg.body.data._id}/approve`);

    const res = await as(owner).get('/api/notifications');
    expect(res.body.data[0]).toMatchObject({
      type: 'resident_registration_approved',
      isRead: false,
      link: { kind: 'apartment', id: String(apt._id) },
    });
  });
});
