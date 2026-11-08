const request = require('supertest');
const app = require('../src/app');
const Apartment = require('../src/models/Apartment');
const ApartmentResident = require('../src/models/ApartmentResident');
const ServiceRequest = require('../src/models/ServiceRequest');
const Vehicle = require('../src/models/Vehicle');
const Visitor = require('../src/models/Visitor');
const Amenity = require('../src/models/Amenity');
const AmenityBooking = require('../src/models/AmenityBooking');
const requestService = require('../src/services/serviceRequest.service');
const taskService = require('../src/services/operationalTask.service');
const { dayRangeVN } = require('../src/shared/time');
const { setupDb, teardownDb, createUser, bearer, createServiceRequestDoc } = require('./helpers');

const DAY = 24 * 60 * 60 * 1000;
const future = () => new Date(Date.now() + 2 * DAY);

let manager;
let staffA;
let staffB;
let staffC;
let resident;
let apt;

const get = (actor, url) => request(app).get(url).set(bearer(actor.token));

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
  staffA = await createUser({ role: 'staff', department: 'technical', fullName: 'A Kỹ Thuật' });
  staffB = await createUser({ role: 'staff', department: 'technical', fullName: 'B Kỹ Thuật' });
  staffC = await createUser({ role: 'staff', department: 'security', fullName: 'C Bảo Vệ' });
  resident = await createUser({ role: 'resident' });
  apt = await Apartment.create({ code: 'R-101', floor: 1, area: 50, status: 'occupied' });
  await Apartment.create({ code: 'R-102', floor: 1, area: 50 });
  await ApartmentResident.create({
    apartmentId: apt._id,
    userId: resident.user._id,
    fullName: 'Cư Dân',
    relation: 'owner',
    status: 'active',
  });
});
afterAll(teardownDb);

describe('UC-48 báo cáo hiệu suất: số khớp tính tay', () => {
  const M = () => manager.user;
  const A = () => staffA.user;
  const B = () => staffB.user;
  const R = () => resident.user;
  const assign = (id, staff) =>
    requestService.transition(M(), id, 'assign', { department: 'technical', staffId: String(staff._id), deadline: future() });

  beforeAll(async () => {
    const newRequest = (title) =>
      requestService.createRequest(R(), {
        apartmentId: String(apt._id),
        requestType: 'repair',
        category: 'electric',
        title,
        description: 'Mô tả phiếu báo cáo',
        priority: 'normal',
      });

    // req1: A làm đúng hạn, cư dân chấm 5
    const r1 = await newRequest('Phiếu 1');
    await assign(r1._id, A());
    await requestService.transition(A(), r1._id, 'start');
    await requestService.transition(A(), r1._id, 'finish', { note: 'xong' });
    await requestService.transition(R(), r1._id, 'confirm', { rating: 5 });

    // req2: A làm trễ hạn, bị yêu cầu làm lại, báo xong lần 2 (không tính thêm), cư dân chấm 3
    const r2 = await newRequest('Phiếu 2');
    await assign(r2._id, A());
    await ServiceRequest.updateOne({ _id: r2._id }, { deadline: new Date(Date.now() - DAY) });
    await requestService.transition(A(), r2._id, 'start');
    await requestService.transition(A(), r2._id, 'finish', { note: 'xong' });
    await requestService.transition(R(), r2._id, 'reopen', { reason: 'Chưa ổn' });
    await requestService.transition(A(), r2._id, 'start');
    await requestService.transition(A(), r2._id, 'finish', { note: 'xong lần 2' });
    await requestService.transition(R(), r2._id, 'confirm', { rating: 3 });

    // req3: giao A rồi chuyển B; B làm đúng hạn (chưa nghiệm thu)
    const r3 = await newRequest('Phiếu 3');
    await assign(r3._id, A());
    await requestService.transition(M(), r3._id, 'reassign', {
      department: 'technical',
      staffId: String(B()._id),
      note: 'Chuyển người',
    });
    await requestService.transition(B(), r3._id, 'start');
    await requestService.transition(B(), r3._id, 'finish', { note: 'xong' });

    // req4: giao A rồi cư dân rút phiếu -> không tính cho ai
    const r4 = await newRequest('Phiếu 4');
    await assign(r4._id, A());
    await requestService.transition(R(), r4._id, 'cancel', { reason: 'Tự sửa được' });

    // task1: giao B, B hoàn thành đúng hạn
    const t1 = await taskService.create(M(), {
      title: 'Kiểm tra PCCC',
      department: 'technical',
      staffId: String(B()._id),
      deadline: future(),
    });
    await taskService.transition(B(), t1._id, 'start');
    await taskService.transition(B(), t1._id, 'complete', { note: 'ok' });
  });

  test('từng nhân viên', async () => {
    const res = await get(manager, '/api/reports/staff-performance');
    expect(res.status).toBe(200);
    const byName = Object.fromEntries(res.body.data.items.map((i) => [i.staff.fullName, i]));

    // A: được giao 2 (r1, r2), bị chuyển đi 1 (r3), r4 cư dân rút không tính;
    // hoàn thành 2 (r1 đúng hạn, r2 trễ — chỉ tính lần báo xong đầu)
    expect(byName['A Kỹ Thuật']).toMatchObject({
      assigned: 2,
      transferredAway: 1,
      completed: 2,
      onTime: 1,
      onTimeRate: 0.5,
      avgRating: 4,
      ratingCount: 2,
      reopenCount: 1,
    });
    expect(byName['A Kỹ Thuật'].avgHandlingHours).toEqual(expect.any(Number));

    // B: được giao 2 (reassign r3 + task1); hoàn thành 2, đều đúng hạn; chưa có đánh giá
    expect(byName['B Kỹ Thuật']).toMatchObject({
      assigned: 2,
      transferredAway: 0,
      completed: 2,
      onTime: 2,
      onTimeRate: 1,
      avgRating: null,
      reopenCount: 0,
    });

    // C: chưa có việc -> null, không phải 0%
    expect(byName['C Bảo Vệ']).toMatchObject({
      assigned: 0,
      completed: 0,
      onTimeRate: null,
      avgHandlingHours: null,
      avgRating: null,
    });

    expect(res.body.data.totals).toMatchObject({ assigned: 4, transferredAway: 1, completed: 4, onTime: 3, onTimeRate: 0.75 });
    // Sắp xếp: hoàn thành nhiều trước, rồi được giao nhiều trước
    expect(res.body.data.items.map((i) => i.staff.fullName)).toEqual(['A Kỹ Thuật', 'B Kỹ Thuật', 'C Bảo Vệ']);
  });

  test('lọc bộ phận; khoảng không có dữ liệu trả null; ngày sai / ngược: 400; chỉ Manager', async () => {
    const security = await get(manager, '/api/reports/staff-performance?department=security');
    expect(security.body.data.items.map((i) => i.staff.fullName)).toEqual(['C Bảo Vệ']);

    const empty = await get(manager, '/api/reports/staff-performance?from=2000-01-01&to=2000-01-31');
    expect(empty.body.data.totals).toMatchObject({ assigned: 0, completed: 0, onTimeRate: null });
    expect(empty.body.data.range).toEqual({ from: '2000-01-01', to: '2000-01-31' });

    expect((await get(manager, '/api/reports/staff-performance?from=2026-02-10&to=2026-02-01')).status).toBe(400);
    expect((await get(manager, '/api/reports/staff-performance?from=10-02-2026')).status).toBe(400);
    expect((await get(staffA, '/api/reports/staff-performance')).status).toBe(403);
  });
});

describe('UC-47 dashboard vận hành', () => {
  test('số liệu thật từ các module', async () => {
    const before = (await get(manager, '/api/dashboard/operations')).body.data;

    // Thêm dữ liệu đã biết rồi so chênh lệch
    await createServiceRequestDoc({
      status: 'in_progress',
      assignedStaffId: staffA.user._id,
      deadline: new Date(Date.now() - DAY),
    });
    await Vehicle.create({ apartmentId: apt._id, ownerId: resident.user._id, type: 'car', plateNumber: '30A99999' });
    const today = dayRangeVN();
    await Visitor.create({
      appointmentCode: 'VS-DASH01',
      apartmentId: apt._id,
      createdBy: resident.user._id,
      visitorName: 'Khách',
      numberOfPeople: 1,
      visitDate: today.start,
      timeFrom: new Date(),
      timeTo: new Date(Date.now() + 3600 * 1000),
    });
    const pool = await Amenity.create({ name: 'Hồ bơi', openTime: '06:00', closeTime: '10:00', slotDuration: 60, capacity: 5 });
    const start = new Date(Date.now() + 3600 * 1000);
    await AmenityBooking.create({
      amenityId: pool._id,
      apartmentId: apt._id,
      bookedBy: resident.user._id,
      bookingDate: today.start,
      startTime: start,
      endTime: new Date(start.getTime() + 3600 * 1000),
      numberOfParticipants: 2,
      status: 'confirmed',
    });

    const res = await get(manager, '/api/dashboard/operations');
    expect(res.status).toBe(200);
    const d = res.body.data;
    expect(d.apartments).toEqual({ total: 2, occupied: 1, occupancyRate: 0.5 });
    expect(d.requests.overdue).toBe(before.requests.overdue + 1);
    expect(d.requests.open).toBe(before.requests.open + 1);
    expect(d.requests.byStatus.in_progress).toBe((before.requests.byStatus.in_progress || 0) + 1);
    expect(d.vehicles.pending).toBe(before.vehicles.pending + 1);
    expect(d.visitors.expectedToday).toBe(before.visitors.expectedToday + 1);
    expect(d.bookings.byAmenity).toEqual([
      { amenityId: String(pool._id), name: 'Hồ bơi', total: 1, byStatus: { confirmed: 1 } },
    ]);
    expect(d.tasks).toMatchObject({ byStatus: { completed: 1 }, open: 0, createdInRange: 1 });
    expect(d.range.from).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  test('chỉ Manager; khoảng quá dài: 400', async () => {
    expect((await get(staffA, '/api/dashboard/operations')).status).toBe(403);
    expect((await get(resident, '/api/dashboard/operations')).status).toBe(403);
    expect((await get(manager, '/api/dashboard/operations?from=2020-01-01&to=2026-01-01')).status).toBe(400);
  });
});
