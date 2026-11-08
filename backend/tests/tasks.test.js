const request = require('supertest');
const app = require('../src/app');
const Notification = require('../src/models/Notification');
const OperationalTask = require('../src/models/OperationalTask');
const RequestHistory = require('../src/models/RequestHistory');
const taskService = require('../src/services/operationalTask.service');
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
let resident;

const as = (actor) => ({
  get: (url) => request(app).get(url).set(bearer(actor.token)),
  post: (url, body) => request(app).post(url).set(bearer(actor.token)).send(body),
  patch: (url, body) => request(app).patch(url).set(bearer(actor.token)).send(body),
});

async function createTask(extra = {}) {
  const res = await as(manager).post('/api/tasks', {
    title: 'Kiểm tra bình chữa cháy tầng 1-5',
    category: 'inspection',
    location: 'Khối A',
    department: 'technical',
    staffId: String(tech1.user._id),
    deadline: future(),
    ...extra,
  });
  expect(res.status).toBe(201);
  return res.body.data;
}

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
  tech1 = await createUser({ role: 'staff', department: 'technical', fullName: 'Kỹ Thuật 1' });
  tech2 = await createUser({ role: 'staff', department: 'technical', fullName: 'Kỹ Thuật 2' });
  guard = await createUser({ role: 'staff', department: 'security' });
  resident = await createUser({ role: 'resident' });
});
afterAll(teardownDb);

describe('UC-41 tạo và giao nhiệm vụ', () => {
  test('sinh mã TK-, assigned, có lịch sử, báo nhân viên', async () => {
    const t = await createTask({ priority: 'high' });
    expect(t.taskCode).toMatch(/^TK-[A-Z2-9]{6}$/);
    expect(t).toMatchObject({ status: 'assigned', priority: 'high', assignedStaffId: String(tech1.user._id), isOverdue: false });
    const h = await RequestHistory.find({ taskId: t._id });
    expect(h.map((x) => x.action)).toEqual(['created']);
    expect(String(h[0].assignedStaffId)).toBe(String(tech1.user._id));
    expect(await Notification.exists({ userId: tech1.user._id, type: 'task_assigned' })).toBeTruthy();
  });

  test('nhân viên sai bộ phận / hạn trong quá khứ / Staff tạo: bị chặn', async () => {
    const wrong = await as(manager).post('/api/tasks', {
      title: 'Tuần tra', department: 'technical', staffId: String(guard.user._id), deadline: future(),
    });
    expect(wrong.status).toBe(409);
    expect(wrong.body.error.code).toBe('ASSIGNEE_INVALID');
    const past = await as(manager).post('/api/tasks', {
      title: 'Tuần tra', department: 'technical', staffId: String(tech1.user._id), deadline: new Date(Date.now() - DAY).toISOString(),
    });
    expect(past.status).toBe(400);
    expect((await as(tech1).post('/api/tasks', {})).status).toBe(403);
  });
});

describe('Luồng: bắt đầu → hoàn thành; chuyển người; hủy', () => {
  test('bắt đầu đồng thời 2 lần: 1 thành công; hoàn thành kèm ảnh, báo Manager', async () => {
    const t = await createTask();
    const url = `/api/tasks/${t._id}`;
    expect((await as(tech2).patch(`${url}/start`)).status).toBe(404);
    const results = await Promise.all([as(tech1).patch(`${url}/start`), as(tech1).patch(`${url}/start`)]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);

    const res = await request(app)
      .patch(`${url}/complete`)
      .set(bearer(tech1.token))
      .field('note', 'Đã kiểm tra 40 bình, thay 2 bình hết hạn')
      .attach('images', PNG, { filename: 'kq.png', contentType: 'image/png' });
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ status: 'completed', completionNote: 'Đã kiểm tra 40 bình, thay 2 bình hết hạn' });
    expect(res.body.data.completedAt).toBeDefined();
    expect(res.body.data.resultImages).toHaveLength(1);
    expect(await Notification.exists({ userId: manager.user._id, type: 'task_completed' })).toBeTruthy();

    const detail = await as(manager).get(url);
    expect(detail.body.data.timeline.map((h) => h.action)).toEqual(['created', 'start', 'complete']);
    expect(detail.body.data.allowedActions).toEqual([]);
  });

  test('chuyển người: bắt buộc lý do, khác người cũ, báo cả hai, người cũ mất quyền xem', async () => {
    const t = await createTask();
    const url = `/api/tasks/${t._id}`;
    await as(tech1).patch(`${url}/start`);
    const body = { department: 'technical', staffId: String(tech2.user._id) };
    expect((await as(manager).patch(`${url}/reassign`, body)).status).toBe(400);
    expect(
      (await as(manager).patch(`${url}/reassign`, { ...body, staffId: String(tech1.user._id), note: 'Đổi' })).status
    ).toBe(400);
    const res = await as(manager).patch(`${url}/reassign`, { ...body, note: 'Kỹ thuật 1 nghỉ phép' });
    // Đang làm mà chuyển người -> về assigned để người mới bắt đầu lại
    expect(res.body.data).toMatchObject({ status: 'assigned', assignedStaffId: String(tech2.user._id) });
    expect(await Notification.exists({ userId: tech1.user._id, type: 'task_unassigned' })).toBeTruthy();
    expect((await as(tech1).get(url)).status).toBe(404);
    expect((await as(tech2).get(url)).body.data.allowedActions).toEqual(['start']);
  });

  test('hủy: bắt buộc lý do, báo nhân viên, sau đó không bắt đầu được', async () => {
    const t = await createTask();
    const url = `/api/tasks/${t._id}`;
    expect((await as(manager).patch(`${url}/cancel`, {})).status).toBe(400);
    const res = await as(manager).patch(`${url}/cancel`, { reason: 'Đã gộp vào đợt kiểm tra lớn' });
    expect(res.body.data).toMatchObject({ status: 'cancelled', cancelReason: 'Đã gộp vào đợt kiểm tra lớn' });
    expect(await Notification.exists({ userId: tech1.user._id, type: 'task_cancelled' })).toBeTruthy();
    expect((await as(tech1).patch(`${url}/start`)).status).toBe(409);
  });

  test('máy trạng thái: mọi cặp hành động / trạng thái sai đều 409, không ghi lịch sử', async () => {
    const actor = { reassign: manager.user, cancel: manager.user, start: tech1.user, complete: tech1.user };
    const input = {
      reassign: { department: 'technical', staffId: String(tech2.user._id), note: 'abc' },
      cancel: { reason: 'abc' },
      start: {},
      complete: {},
    };
    for (const status of ['assigned', 'in_progress', 'completed', 'cancelled']) {
      for (const [action, rule] of Object.entries(taskService.TRANSITIONS)) {
        if (rule.from.includes(status)) continue;
        const doc = await OperationalTask.create({
          taskCode: `TK-S${Math.random().toString(36).slice(2, 8)}`,
          title: 'x',
          department: 'technical',
          assignedStaffId: tech1.user._id,
          createdBy: manager.user._id,
          deadline: new Date(Date.now() + DAY),
          status,
        });
        await expect(taskService.transition(actor[action], doc._id, action, input[action])).rejects.toMatchObject({
          code: 'INVALID_STATE',
        });
        expect(await RequestHistory.countDocuments({ taskId: doc._id })).toBe(0);
      }
    }
  });
});

describe('UC-42 lịch sử nhiệm vụ', () => {
  test('Staff truyền staffId người khác vẫn chỉ thấy việc của mình; Manager lọc theo người', async () => {
    await createTask({ staffId: String(tech2.user._id), title: 'Việc của KT2' });
    const forTech1 = await as(tech1).get(`/api/tasks?staffId=${tech2.user._id}&limit=100`);
    expect(forTech1.body.data.every((t) => t.assignedStaffId._id === String(tech1.user._id))).toBe(true);

    const forManager = await as(manager).get(`/api/tasks?staffId=${tech2.user._id}&limit=100`);
    expect(forManager.body.data.length).toBeGreaterThan(0);
    expect(forManager.body.data.every((t) => t.assignedStaffId._id === String(tech2.user._id))).toBe(true);
    expect((await as(resident).get('/api/tasks')).status).toBe(403);
  });

  test('lọc quá hạn và theo khoảng ngày tạo', async () => {
    const late = await OperationalTask.create({
      taskCode: 'TK-LATE01',
      title: 'Quá hạn',
      department: 'technical',
      assignedStaffId: tech1.user._id,
      createdBy: manager.user._id,
      deadline: new Date(Date.now() - DAY),
      status: 'in_progress',
    });
    const res = await as(manager).get('/api/tasks?overdue=true&limit=100');
    expect(res.body.data.map((t) => t._id)).toContain(String(late._id));
    expect(res.body.data.every((t) => t.isOverdue)).toBe(true);
    expect((await as(manager).get('/api/tasks?from=2000-01-01&to=2000-01-02')).body.data).toEqual([]);
    expect((await as(manager).get('/api/tasks?from=01-01-2000')).status).toBe(400);
  });
});

describe('UC-31 việc của tôi: phiếu + nhiệm vụ trong một danh sách', () => {
  test('trộn đúng thứ tự hạn, có kind, phân trang không trùng / sót', async () => {
    const staff = await createUser({ role: 'staff', department: 'technical' });
    const at = (h) => new Date(Date.now() + h * 60 * 60 * 1000);
    const r1 = await createServiceRequestDoc({ assignedStaffId: staff.user._id, status: 'assigned', deadline: at(1) });
    const t1 = await OperationalTask.create({
      taskCode: 'TK-MIX001', title: 'NV 1', department: 'technical', assignedStaffId: staff.user._id,
      createdBy: manager.user._id, deadline: at(2),
    });
    const r2 = await createServiceRequestDoc({ assignedStaffId: staff.user._id, status: 'in_progress', deadline: at(3) });
    const t2 = await OperationalTask.create({
      taskCode: 'TK-MIX002', title: 'NV 2', department: 'technical', assignedStaffId: staff.user._id,
      createdBy: manager.user._id, deadline: at(4), status: 'in_progress',
    });
    await OperationalTask.create({
      taskCode: 'TK-MIX003', title: 'Xong', department: 'technical', assignedStaffId: staff.user._id,
      createdBy: manager.user._id, deadline: at(5), status: 'completed',
    });

    const page = async (p) => (await as(staff).get(`/api/me/assignments?tab=active&limit=3&page=${p}`)).body;
    const p1 = await page(1);
    const p2 = await page(2);
    expect(p1.meta.total).toBe(4);
    expect([...p1.data, ...p2.data].map((x) => `${x.kind}:${x._id}`)).toEqual([
      `request:${r1._id}`, `task:${t1._id}`, `request:${r2._id}`, `task:${t2._id}`,
    ]);
    const done = (await as(staff).get('/api/me/assignments?tab=done')).body.data;
    expect(done.map((x) => x.kind)).toEqual(['task']);
  });

  test('nhiệm vụ đang mở chặn khóa nhân viên; đếm vào tải việc', async () => {
    const staff = await createUser({ role: 'staff', department: 'technical' });
    await createTask({ staffId: String(staff.user._id) });
    const lock = await as(manager).patch(`/api/users/${staff.user._id}/status`, { status: 'inactive' });
    expect(lock.status).toBe(409);
    expect(lock.body.error.code).toBe('HAS_OPEN_WORK');
    const list = await as(manager).get('/api/staff?department=technical&limit=100');
    expect(list.body.data.find((s) => s._id === String(staff.user._id))).toMatchObject({ openTasks: 1 });
  });
});
