const request = require('supertest');
const app = require('../src/app');
const Apartment = require('../src/models/Apartment');
const ApartmentResident = require('../src/models/ApartmentResident');
const Notification = require('../src/models/Notification');
const ServiceRequest = require('../src/models/ServiceRequest');
const RequestHistory = require('../src/models/RequestHistory');
const service = require('../src/services/serviceRequest.service');
const {
  setupDb,
  teardownDb,
  createUser,
  bearer,
  createServiceRequestDoc,
} = require('./helpers');

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
const DAY = 24 * 60 * 60 * 1000;
const future = (days = 2) => new Date(Date.now() + days * DAY).toISOString();

let manager;
let tech1;
let tech2;
let guard;
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

/** Cư dân tạo phiếu qua API (JSON, không ảnh). */
async function createVia(actor, data = {}) {
  const res = await as(actor).post('/api/service-requests', {
    apartmentId: String(aptA._id),
    requestType: 'repair',
    category: 'electric',
    title: 'Mất điện phòng khách',
    description: 'Ổ cắm phòng khách không có điện',
    ...data,
  });
  expect(res.status).toBe(201);
  return res.body.data;
}

const assignBody = (staff = tech1, extra = {}) => ({
  department: 'technical',
  staffId: String(staff.user._id),
  deadline: future(),
  ...extra,
});

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager', fullName: 'Quản Lý' });
  tech1 = await createUser({ role: 'staff', department: 'technical', fullName: 'Kỹ Thuật 1' });
  tech2 = await createUser({ role: 'staff', department: 'technical', fullName: 'Kỹ Thuật 2' });
  guard = await createUser({ role: 'staff', department: 'security', fullName: 'Bảo Vệ' });
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

// ======================================================================== UC-27, 28
describe('UC-27/28 tạo phiếu', () => {
  test('tạo kèm ảnh: sinh mã, pending, có lịch sử, báo Manager', async () => {
    const res = await request(app)
      .post('/api/service-requests')
      .set(bearer(owner.token))
      .field('apartmentId', String(aptA._id))
      .field('requestType', 'repair')
      .field('category', 'plumbing')
      .field('title', 'Rò nước bồn rửa')
      .field('description', 'Nước rò dưới bồn rửa bát')
      .field('priority', 'high')
      .attach('images', PNG, { filename: 'a.png', contentType: 'image/png' })
      .attach('images', PNG, { filename: 'b.png', contentType: 'image/png' });

    expect(res.status).toBe(201);
    const r = res.body.data;
    expect(r.requestCode).toMatch(/^SR-[A-Z2-9]{6}$/);
    expect(r).toMatchObject({ status: 'pending', priority: 'high', isOverdue: false });
    expect(r.images).toHaveLength(2);
    expect(r.priorityRank).toBeUndefined();

    const history = await RequestHistory.find({ requestId: r._id });
    expect(history.map((h) => h.action)).toEqual(['created']);
    expect(await Notification.exists({ userId: manager.user._id, type: 'service_request_created' })).toBeTruthy();
  });

  test('tạo cho căn hộ mình không ở: 403 NOT_APARTMENT_RESIDENT', async () => {
    const res = await as(outsider).post('/api/service-requests', {
      apartmentId: String(aptA._id),
      requestType: 'repair',
      category: 'electric',
      title: 'Thử',
      description: 'Thử tạo hộ',
    });
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('NOT_APARTMENT_RESIDENT');
  });

  test('thiếu dữ liệu / sai danh mục: 400; Staff không tạo được: 403', async () => {
    const bad = await as(owner).post('/api/service-requests', {
      apartmentId: String(aptA._id),
      requestType: 'repair',
      category: 'magic',
      title: 'ab',
      description: 'x',
    });
    expect(bad.status).toBe(400);
    expect(bad.body.error.details.map((d) => d.field)).toEqual(
      expect.arrayContaining(['category', 'title', 'description'])
    );
    expect((await as(tech1).post('/api/service-requests', {})).status).toBe(403);
  });

  test('danh mục phải thuộc loại phiếu: sửa chữa + tiếng ồn bị 400; thang máy dùng cho cả hai', async () => {
    const body = (requestType, category) => ({
      apartmentId: String(aptA._id),
      requestType,
      category,
      title: 'Kiểm tra danh mục',
      description: 'Mô tả đủ dài',
    });
    const bad = await as(owner).post('/api/service-requests', body('repair', 'noise'));
    expect(bad.status).toBe(400);
    expect(bad.body.error.details).toEqual([
      { field: 'category', message: 'Danh mục không thuộc loại phiếu đã chọn' },
    ]);
    expect((await as(owner).post('/api/service-requests', body('complaint', 'electric'))).status).toBe(400);
    expect((await as(owner).post('/api/service-requests', body('repair', 'elevator'))).status).toBe(201);
    expect((await as(owner).post('/api/service-requests', body('complaint', 'elevator'))).status).toBe(201);
    // Dọn để không ảnh hưởng các test phạm vi xem phía sau
    await ServiceRequest.deleteMany({ title: 'Kiểm tra danh mục' });
  });
});

// ======================================================================== UC-29 phạm vi xem
describe('UC-29 phạm vi xem của cư dân', () => {
  let repair;
  let complaint;
  beforeAll(async () => {
    repair = await createVia(owner, { title: 'Hỏng đèn hành lang' });
    complaint = await createVia(owner, {
      requestType: 'complaint',
      category: 'noise',
      title: 'Hàng xóm ồn ào',
    });
  });

  test('thành viên cùng căn thấy phiếu sửa chữa, không thấy phản ánh của người khác', async () => {
    const mine = await as(member).get('/api/service-requests/mine?limit=100');
    const ids = mine.body.data.map((r) => r._id);
    expect(ids).toContain(repair._id);
    expect(ids).not.toContain(complaint._id);
    expect((await as(member).get(`/api/service-requests/${repair._id}`)).status).toBe(200);
    expect((await as(member).get(`/api/service-requests/${complaint._id}`)).status).toBe(404);
  });

  test('người tạo thấy cả phản ánh; lọc theo loại', async () => {
    const res = await as(owner).get('/api/service-requests/mine?type=complaint');
    expect(res.body.data.map((r) => r._id)).toEqual([complaint._id]);
  });

  test('cư dân căn khác, Staff chưa được giao: 404 (không lộ phiếu tồn tại)', async () => {
    expect((await as(outsider).get(`/api/service-requests/${repair._id}`)).status).toBe(404);
    expect((await as(tech1).get(`/api/service-requests/${repair._id}`)).status).toBe(404);
  });
});

// ======================================================================== UC-30 hàng chờ
describe('UC-30 hàng chờ của Manager', () => {
  test('mặc định chỉ pending, ưu tiên cao lên trước', async () => {
    const low = await createVia(owner, { title: 'Ưu tiên thấp', priority: 'low' });
    const urgent = await createVia(owner, { title: 'Khẩn cấp', priority: 'urgent' });
    const res = await as(manager).get('/api/service-requests?limit=100');
    expect(res.status).toBe(200);
    expect(res.body.data.every((r) => r.status === 'pending')).toBe(true);
    const order = res.body.data.map((r) => r._id);
    expect(order.indexOf(urgent._id)).toBeLessThan(order.indexOf(low._id));
    expect(res.body.data[0].createdBy.fullName).toBeDefined();
  });

  test('cư dân, Staff không xem hàng chờ: 403', async () => {
    expect((await as(owner).get('/api/service-requests')).status).toBe(403);
    expect((await as(tech1).get('/api/service-requests')).status).toBe(403);
  });
});

// ======================================================================== Luồng đầy đủ
describe('Luồng đầy đủ: giao → làm → báo xong → làm lại → nghiệm thu', () => {
  let r;
  const url = (action = '') => `/api/service-requests/${r._id}${action ? `/${action}` : ''}`;

  beforeAll(async () => {
    r = await createVia(owner, { title: 'Điều hòa không lạnh' });
  });

  test('phân công sai bộ phận / nhân viên khóa / hạn trong quá khứ: bị chặn', async () => {
    const wrongDept = await as(manager).patch(url('assign'), assignBody(guard));
    expect(wrongDept.status).toBe(409);
    expect(wrongDept.body.error.code).toBe('ASSIGNEE_INVALID');

    const past = await as(manager).patch(
      url('assign'),
      assignBody(tech1, { deadline: new Date(Date.now() - DAY).toISOString() })
    );
    expect(past.status).toBe(400);
  });

  test('phân công: assigned, báo nhân viên và cư dân, cư dân thấy nút chờ', async () => {
    const res = await as(manager).patch(
      url('assign'),
      assignBody(tech1, { priority: 'urgent', note: 'Khách VIP, xử lý sớm' })
    );
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({
      status: 'assigned',
      department: 'technical',
      assignedStaffId: String(tech1.user._id),
      priority: 'urgent',
    });
    expect(await Notification.exists({ userId: tech1.user._id, type: 'service_request_assigned' })).toBeTruthy();
    expect(await Notification.exists({ userId: owner.user._id, type: 'service_request_accepted' })).toBeTruthy();
  });

  test('nhân viên khác không bắt đầu được (404); người được giao thấy nút start', async () => {
    expect((await as(tech2).patch(url('start'))).status).toBe(404);
    const detail = await as(tech1).get(url());
    expect(detail.body.data.allowedActions).toEqual(['start']);
  });

  test('bắt đầu đồng thời 2 lần: đúng 1 thành công, lần kia 409', async () => {
    const results = await Promise.all([as(tech1).patch(url('start')), as(tech1).patch(url('start'))]);
    expect(results.map((x) => x.status).sort()).toEqual([200, 409]);
    expect(await RequestHistory.countDocuments({ requestId: r._id, action: 'start' })).toBe(1);
  });

  test('báo xong: bắt buộc ghi chú, nhận ảnh sau xử lý', async () => {
    expect((await as(tech1).patch(url('finish'), {})).status).toBe(400);
    const res = await request(app)
      .patch(url('finish'))
      .set(bearer(tech1.token))
      .field('note', 'Đã nạp gas điều hòa')
      .attach('images', PNG, { filename: 'after.png', contentType: 'image/png' });
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('waiting_confirmation');
    expect(res.body.data.resultImages).toHaveLength(1);
    expect(res.body.data.waitingSince).toBeDefined();
    expect(res.body.data.firstFinishedAt).toBeDefined();
  });

  test('thành viên khác (không phải người tạo) không nghiệm thu được: 403', async () => {
    expect((await as(member).patch(url('confirm'), { rating: 5 })).status).toBe(403);
  });

  test('yêu cầu làm lại: bắt buộc lý do, tăng reopenCount, báo nhân viên + Manager', async () => {
    expect((await as(owner).patch(url('reopen'), {})).status).toBe(400);
    const res = await as(owner).patch(url('reopen'), { reason: 'Vẫn chưa lạnh' });
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ status: 'reopened', reopenCount: 1 });
    expect(await Notification.exists({ userId: tech1.user._id, type: 'service_request_reopened' })).toBeTruthy();
    expect(await Notification.exists({ userId: manager.user._id, type: 'service_request_reopened' })).toBeTruthy();
  });

  test('làm lại → báo xong → nghiệm thu 5 sao; firstFinishedAt giữ lần đầu', async () => {
    const before = await ServiceRequest.findById(r._id);
    expect((await as(tech1).patch(url('start'))).body.data.status).toBe('in_progress');
    await as(tech1).patch(url('finish'), { note: 'Thay block điều hòa' });

    expect((await as(owner).patch(url('confirm'), { rating: 6 })).status).toBe(400);
    const res = await as(owner).patch(url('confirm'), { rating: 5, feedback: 'Nhanh, gọn' });
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ status: 'closed', rating: 5, autoClosed: false });
    expect(res.body.data.closedAt).toBeDefined();
    const after = await ServiceRequest.findById(r._id);
    expect(after.firstFinishedAt.getTime()).toBe(before.firstFinishedAt.getTime());

    // Trạng thái cuối: không đi tiếp
    expect((await as(owner).patch(url('reopen'), { reason: 'Thử lại' })).status).toBe(409);
  });

  test('timeline đủ bước; cư dân không thấy ghi chú nội bộ khi giao việc', async () => {
    const forManager = await as(manager).get(url());
    expect(forManager.body.data.timeline.map((h) => h.action)).toEqual([
      'created', 'assign', 'start', 'finish', 'reopen', 'start', 'finish', 'confirm',
    ]);
    expect(forManager.body.data.timeline[1].note).toBe('Khách VIP, xử lý sớm');

    const forResident = await as(owner).get(url());
    expect(forResident.body.data.timeline[1].note).toBeUndefined();
    expect(forResident.body.data.timeline[4].note).toBe('Vẫn chưa lạnh');
    expect(forResident.body.data.allowedActions).toEqual([]);
  });
});

// ======================================================================== Từ chối, chuyển người
describe('Từ chối và chuyển người', () => {
  test('từ chối: bắt buộc lý do, báo cư dân, sau đó không phân công được', async () => {
    const r = await createVia(owner, { title: 'Yêu cầu không hợp lệ' });
    const u = `/api/service-requests/${r._id}`;
    expect((await as(manager).patch(`${u}/reject`, {})).status).toBe(400);
    const res = await as(manager).patch(`${u}/reject`, { reason: 'Ngoài phạm vi ban quản lý' });
    expect(res.body.data).toMatchObject({ status: 'rejected', rejectReason: 'Ngoài phạm vi ban quản lý' });
    expect(await Notification.exists({ userId: owner.user._id, type: 'service_request_rejected' })).toBeTruthy();
    expect((await as(manager).patch(`${u}/assign`, assignBody())).status).toBe(409);
  });

  test('chuyển người: bắt buộc lý do, khác người cũ, báo cả hai', async () => {
    const r = await createVia(owner, { title: 'Thang máy kêu' });
    const u = `/api/service-requests/${r._id}`;
    await as(manager).patch(`${u}/assign`, assignBody(tech1));

    expect((await as(manager).patch(`${u}/reassign`, assignBody(tech2))).status).toBe(400); // thiếu note
    expect(
      (await as(manager).patch(`${u}/reassign`, assignBody(tech1, { note: 'Đổi người' }))).status
    ).toBe(400);

    const res = await as(manager).patch(`${u}/reassign`, assignBody(tech2, { note: 'Kỹ thuật 1 nghỉ ốm' }));
    expect(res.status).toBe(200);
    expect(res.body.data.assignedStaffId).toBe(String(tech2.user._id));
    expect(await Notification.exists({ userId: tech1.user._id, type: 'service_request_unassigned' })).toBeTruthy();
    // Người cũ không còn thấy phiếu
    expect((await as(tech1).get(u)).status).toBe(404);
  });
});

// ======================================================================== Cư dân rút phiếu
describe('Cư dân rút phiếu', () => {
  test('chờ tiếp nhận: người tạo rút được (không cần lý do), có lịch sử, không báo ai', async () => {
    const r = await createVia(owner, { title: 'Gửi nhầm' });
    const u = `/api/service-requests/${r._id}`;
    expect((await as(owner).get(u)).body.data.allowedActions).toContain('cancel');
    const res = await as(owner).patch(`${u}/cancel`, {});
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ status: 'cancelled' });
    expect((await as(owner).get(u)).body.data.allowedActions).toEqual([]);
    expect(res.body.data.cancelledAt).toBeTruthy();
    expect(await RequestHistory.exists({ requestId: r._id, action: 'cancel', newStatus: 'cancelled' })).toBeTruthy();
    expect(await Notification.exists({ type: 'service_request_cancelled' })).toBeFalsy();
  });

  test('đã phân công: rút được, báo nhân viên; nhân viên không còn thấy trong việc đang làm', async () => {
    const r = await createVia(owner, { title: 'Tự sửa được rồi' });
    const u = `/api/service-requests/${r._id}`;
    await as(manager).patch(`${u}/assign`, assignBody(tech1));
    const res = await as(owner).patch(`${u}/cancel`, { reason: 'Đã tự thay cầu chì' });
    expect(res.body.data).toMatchObject({ status: 'cancelled', cancelReason: 'Đã tự thay cầu chì' });
    expect(
      await Notification.exists({ userId: tech1.user._id, type: 'service_request_cancelled' })
    ).toBeTruthy();
    const mine = await as(tech1).get('/api/me/assignments?tab=active');
    expect(mine.body.data.map((i) => i._id)).not.toContain(r._id);
    // Đã rút thì không làm gì tiếp được
    expect((await as(tech1).patch(`${u}/start`)).status).toBe(409);
  });

  test('đang xử lý: không rút được (409); người không phải người tạo: 403', async () => {
    const r = await createVia(owner, { title: 'Đang sửa' });
    const u = `/api/service-requests/${r._id}`;
    expect((await as(member).patch(`${u}/cancel`, {})).status).toBe(403);
    await as(manager).patch(`${u}/assign`, assignBody(tech1));
    await as(tech1).patch(`${u}/start`);
    expect((await as(owner).get(u)).body.data.allowedActions).not.toContain('cancel');
    expect((await as(owner).patch(`${u}/cancel`, {})).status).toBe(409);
  });

  test('đã từng xử lý (làm lại rồi giao lại): không rút được, dùng nghiệm thu', async () => {
    const r = await createVia(owner, { title: 'Làm lại' });
    const u = `/api/service-requests/${r._id}`;
    await as(manager).patch(`${u}/assign`, assignBody(tech1));
    await as(tech1).patch(`${u}/start`);
    await as(tech1).patch(`${u}/finish`, { note: 'Đã xử lý xong' });
    await as(owner).patch(`${u}/reopen`, { reason: 'Chưa ổn' });
    await as(manager).patch(`${u}/assign`, assignBody(tech2));
    expect((await as(owner).patch(`${u}/cancel`, {})).status).toBe(403);
  });
});

// ======================================================================== Máy trạng thái (bảng)
describe('Máy trạng thái: mọi cặp hành động / trạng thái sai đều 409', () => {
  const ACTORS = () => ({
    reject: manager.user,
    assign: manager.user,
    reassign: manager.user,
    start: tech1.user,
    finish: tech1.user,
    confirm: owner.user,
    reopen: owner.user,
    cancel: owner.user,
  });
  const INPUT = {
    reject: { reason: 'abc' },
    assign: { department: 'technical', deadline: new Date(Date.now() + DAY) },
    reassign: { department: 'technical', deadline: new Date(Date.now() + DAY), note: 'abc' },
    start: {},
    finish: { note: 'abc' },
    confirm: { rating: 4 },
    reopen: { reason: 'abc' },
    cancel: {},
  };
  const STATUSES = ['pending', 'rejected', 'assigned', 'in_progress', 'waiting_confirmation', 'reopened', 'closed', 'cancelled'];

  test.each(STATUSES)('từ trạng thái %s', async (status) => {
    const actors = ACTORS();
    for (const [action, rule] of Object.entries(service.TRANSITIONS)) {
      if (rule.from.includes(status)) continue;
      const doc = await createServiceRequestDoc({
        status,
        apartmentId: aptA._id,
        createdBy: owner.user._id,
        assignedStaffId: tech1.user._id,
      });
      const input = { ...INPUT[action], staffId: String(tech2.user._id) };
      await expect(service.transition(actors[action], doc._id, action, input)).rejects.toMatchObject({
        code: 'INVALID_STATE',
      });
      expect(await RequestHistory.countDocuments({ requestId: doc._id })).toBe(0);
      expect((await ServiceRequest.findById(doc._id)).status).toBe(status);
    }
  });
});

// ======================================================================== UC-31 việc của tôi
describe('UC-31 GET /api/me/assignments', () => {
  test('tab đang làm / quá hạn / đã xong, có isOverdue, chỉ việc của mình', async () => {
    const staff = await createUser({ role: 'staff', department: 'technical' });
    const base = { apartmentId: aptA._id, createdBy: owner.user._id, assignedStaffId: staff.user._id };
    const late = await createServiceRequestDoc({ ...base, status: 'in_progress', deadline: new Date(Date.now() - DAY) });
    const onTime = await createServiceRequestDoc({ ...base, status: 'assigned', deadline: new Date(Date.now() + DAY) });
    const done = await createServiceRequestDoc({ ...base, status: 'closed' });
    await createServiceRequestDoc({ ...base, assignedStaffId: tech2.user._id, status: 'assigned' });

    const tab = async (t) => (await as(staff).get(`/api/me/assignments?tab=${t}`)).body.data;
    const active = await tab('active');
    expect(active.map((x) => x._id)).toEqual([String(late._id), String(onTime._id)]);
    expect(active[0]).toMatchObject({ kind: 'request', isOverdue: true });
    expect(active[1].isOverdue).toBe(false);
    expect((await tab('overdue')).map((x) => x._id)).toEqual([String(late._id)]);
    expect((await tab('done')).map((x) => x._id)).toEqual([String(done._id)]);

    expect((await as(owner).get('/api/me/assignments')).status).toBe(403);
  });
});

// ======================================================================== Job tự đóng
describe('Job tự đóng sau 7 ngày', () => {
  test('quá 7 ngày thì đóng (không đánh giá, có lịch sử hệ thống); chưa đủ thì giữ', async () => {
    const base = {
      status: 'waiting_confirmation',
      apartmentId: aptA._id,
      createdBy: owner.user._id,
      assignedStaffId: tech1.user._id,
    };
    const old = await createServiceRequestDoc({ ...base, waitingSince: new Date(Date.now() - 8 * DAY) });
    const fresh = await createServiceRequestDoc({ ...base, waitingSince: new Date(Date.now() - 6 * DAY) });

    const n = await service.autoCloseExpired();
    expect(n).toBeGreaterThanOrEqual(1);

    const closed = await ServiceRequest.findById(old._id);
    expect(closed).toMatchObject({ status: 'closed', autoClosed: true });
    expect(closed.rating).toBeUndefined();
    const h = await RequestHistory.findOne({ requestId: old._id });
    expect(h).toMatchObject({ action: 'auto_closed', updatedBy: null, newStatus: 'closed' });
    expect(await Notification.exists({ userId: owner.user._id, type: 'service_request_auto_closed' })).toBeTruthy();

    expect((await ServiceRequest.findById(fresh._id)).status).toBe('waiting_confirmation');
    // Chạy lại không đóng trùng
    expect(await service.autoCloseExpired()).toBe(0);
  });
});

// ======================================================================== Hook với Người 1
describe('Hook: khóa nhân viên còn phiếu đang mở', () => {
  test('nhân viên đang giữ phiếu thật (qua API) thì không khóa được', async () => {
    const staff = await createUser({ role: 'staff', department: 'technical' });
    const r = await createVia(owner, { title: 'Phiếu giữ nhân viên' });
    await as(manager).patch(`/api/service-requests/${r._id}/assign`, assignBody(staff));
    const res = await as(manager).patch(`/api/users/${staff.user._id}/status`, { status: 'inactive' });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('HAS_OPEN_WORK');
  });
});
