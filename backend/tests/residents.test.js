const request = require('supertest');
const app = require('../src/app');
const Apartment = require('../src/models/Apartment');
const ApartmentResident = require('../src/models/ApartmentResident');
const Notification = require('../src/models/Notification');
const { setupDb, teardownDb, createUser, bearer } = require('./helpers');

let manager;
let reception;
let owner;
let member;
let outsider;
let apt;
let apt2;

const as = (actor) => ({
  get: (url) => request(app).get(url).set(bearer(actor.token)),
  post: (url, body) => request(app).post(url).set(bearer(actor.token)).send(body),
  patch: (url, body) => request(app).patch(url).set(bearer(actor.token)).send(body),
});

beforeAll(async () => {
  await setupDb();
  manager = await createUser({ role: 'manager' });
  reception = await createUser({ role: 'staff', department: 'reception' });
  owner = await createUser({ role: 'resident', fullName: 'Chủ Hộ' });
  member = await createUser({ role: 'resident', fullName: 'Thành Viên' });
  outsider = await createUser({ role: 'resident', fullName: 'Người Ngoài' });
  apt = await Apartment.create({ code: 'A-101', floor: 1, area: 70 });
  apt2 = await Apartment.create({ code: 'A-102', floor: 1, area: 60 });
});
afterAll(teardownDb);

describe('UC-08 Manage Resident Records', () => {
  let ownerRecId;

  test('Manager gắn chủ hộ: active ngay, mặc định là người nộp phí, căn chuyển "có người ở"', async () => {
    const res = await as(manager).post(`/api/apartments/${apt._id}/residents`, {
      fullName: 'Chủ Hộ',
      relation: 'owner',
      userId: String(owner.user._id),
      phone: '0901111111',
      idNumber: '012345678901',
    });
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({ status: 'active', isPayer: true, source: 'manager' });
    ownerRecId = res.body.data._id;
    expect((await Apartment.findById(apt._id)).status).toBe('occupied');
  });

  test('không được có 2 chủ hộ đang hiệu lực', async () => {
    const res = await as(manager).post(`/api/apartments/${apt._id}/residents`, {
      fullName: 'Chủ Hộ 2',
      relation: 'owner',
    });
    expect(res.status).toBe(409);
    expect(res.body.error.message).toMatch(/chủ hộ/);
  });

  test('liên kết tài khoản: phải là cư dân, không trùng hồ sơ', async () => {
    const staffLink = await as(manager).post(`/api/apartments/${apt._id}/residents`, {
      fullName: 'NV',
      relation: 'member',
      userId: String(reception.user._id),
    });
    expect(staffLink.status).toBe(400);

    const dup = await as(manager).post(`/api/apartments/${apt._id}/residents`, {
      fullName: 'Chủ Hộ',
      relation: 'member',
      userId: String(owner.user._id),
    });
    expect(dup.status).toBe(409);
  });

  test('thêm thành viên có tài khoản và thành viên không tài khoản (trẻ em)', async () => {
    const a = await as(manager).post(`/api/apartments/${apt._id}/residents`, {
      fullName: 'Thành Viên',
      relation: 'member',
      userId: String(member.user._id),
    });
    const b = await as(manager).post(`/api/apartments/${apt._id}/residents`, {
      fullName: 'Bé Na',
      relation: 'member',
      dateOfBirth: '2018-05-01',
    });
    expect(a.status).toBe(201);
    expect(b.status).toBe(201);
    expect(b.body.data.isPayer).toBe(false);
  });

  test('tra cứu toàn tòa theo tên / mã căn; Lễ tân được xem', async () => {
    const byName = await as(reception).get('/api/residents?q=bé na');
    expect(byName.status).toBe(200);
    expect(byName.body.data[0].apartmentId.code).toBe('A-101');

    const byApt = await as(manager).get('/api/residents?q=A-101');
    expect(byApt.body.meta.total).toBe(3);
  });

  test('đổi người nộp phí: chỉ một người', async () => {
    const list = await as(manager).get(`/api/apartments/${apt._id}/residents`);
    const kid = list.body.data.find((r) => r.fullName === 'Bé Na');
    const res = await as(manager).patch(`/api/residents/${kid._id}/payer`);
    expect(res.body.data.isPayer).toBe(true);
    expect(await ApartmentResident.countDocuments({ apartmentId: apt._id, isPayer: true })).toBe(1);
    // trả lại cho chủ hộ
    await as(manager).patch(`/api/residents/${ownerRecId}/payer`);
  });

  test('sửa hồ sơ', async () => {
    const res = await as(manager).patch(`/api/residents/${ownerRecId}`, { phone: '0909999999' });
    expect(res.body.data.phone).toBe('0909999999');
  });
});

describe('UC-07 / UC-12 xem căn hộ và thành viên', () => {
  test('cư dân thấy căn hộ của mình', async () => {
    const res = await as(owner).get('/api/apartments/mine');
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0]).toMatchObject({
      code: 'A-101',
      residentCount: 3,
      ownerName: 'Chủ Hộ',
      myMembership: { relation: 'owner', isPayer: true },
    });
  });

  test('người ngoài không xem được căn hộ / thành viên', async () => {
    expect((await as(outsider).get(`/api/apartments/${apt._id}`)).status).toBe(403);
    expect((await as(outsider).get(`/api/apartments/${apt._id}/residents`)).status).toBe(403);
    expect((await as(outsider).get('/api/apartments/mine')).body.data).toEqual([]);
  });

  test('thành viên xem danh sách nhưng không thấy CCCD', async () => {
    const res = await as(member).get(`/api/apartments/${apt._id}/residents`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(3);
    expect(res.body.data.every((r) => r.idNumber === undefined)).toBe(true);
  });

  test('thành viên không xem được đơn chờ duyệt / lịch sử', async () => {
    const res = await as(member).get(`/api/apartments/${apt._id}/residents?status=pending`);
    expect(res.status).toBe(403);
  });
});

describe('UC-09 / UC-10 khai báo và duyệt cư trú', () => {
  let regId;

  test('thành viên (không phải chủ hộ) không khai báo được', async () => {
    const res = await as(member).post(`/api/apartments/${apt._id}/registrations`, {
      fullName: 'Ai Đó',
      relation: 'tenant',
    });
    expect(res.status).toBe(403);
  });

  test('chủ hộ không tự khai báo thêm chủ hộ', async () => {
    const res = await as(owner).post(`/api/apartments/${apt._id}/registrations`, {
      fullName: 'Ai Đó',
      relation: 'owner',
    });
    expect(res.status).toBe(400);
  });

  test('chủ hộ khai báo người thuê -> pending, Manager nhận thông báo', async () => {
    const res = await as(owner).post(`/api/apartments/${apt._id}/registrations`, {
      fullName: 'Người Thuê',
      relation: 'tenant',
      phone: '0912345678',
    });
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({ status: 'pending', source: 'registration' });
    regId = res.body.data._id;

    const n = await Notification.findOne({ userId: manager.user._id, type: 'resident_registration_submitted' });
    expect(n.body).toMatch(/Người Thuê/);

    const mine = await as(owner).get(`/api/apartments/${apt._id}/residents?status=pending`);
    expect(mine.body.data.map((r) => r.fullName)).toEqual(['Người Thuê']);
  });

  test('Manager thấy đơn chờ duyệt; người khác không', async () => {
    const res = await as(manager).get('/api/residents/registrations');
    expect(res.body.data.map((r) => r.fullName)).toEqual(['Người Thuê']);
    expect(res.body.data[0].apartmentId.code).toBe('A-101');
    expect((await as(owner).get('/api/residents/registrations')).status).toBe(403);
  });

  test('từ chối phải có lý do', async () => {
    expect((await as(manager).patch(`/api/residents/${regId}/reject`, {})).status).toBe(400);
  });

  test('duyệt -> active, chủ hộ được thông báo, không duyệt lại được', async () => {
    const res = await as(manager).patch(`/api/residents/${regId}/approve`);
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('active');
    expect(res.body.data.moveInDate).toBeTruthy();

    const n = await Notification.findOne({ userId: owner.user._id, type: 'resident_registration_approved' });
    expect(n).toBeTruthy();
    expect((await as(manager).patch(`/api/residents/${regId}/approve`)).status).toBe(400);
  });

  test('từ chối có lý do -> chủ hộ thấy lý do', async () => {
    const reg = await as(owner).post(`/api/apartments/${apt._id}/registrations`, {
      fullName: 'Không Hợp Lệ',
      relation: 'member',
    });
    const res = await as(manager).patch(`/api/residents/${reg.body.data._id}/reject`, {
      reason: 'Thiếu giấy tờ',
    });
    expect(res.body.data).toMatchObject({ status: 'rejected', rejectReason: 'Thiếu giấy tờ' });

    const n = await Notification.findOne({ userId: owner.user._id, type: 'resident_registration_rejected' });
    expect(n.body).toMatch(/Thiếu giấy tờ/);
  });
});

describe('UC-11 Record Resident Move-out', () => {
  test('chuyển đi: giữ lịch sử, tài khoản vẫn còn, mất quyền xem căn', async () => {
    const list = await as(manager).get(`/api/apartments/${apt._id}/residents`);
    const memberRec = list.body.data.find((r) => r.fullName === 'Thành Viên');

    const res = await as(manager).patch(`/api/residents/${memberRec._id}/move-out`, {
      reason: 'Chuyển công tác',
    });
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ status: 'ended', moveOutReason: 'Chuyển công tác' });

    expect((await as(member).get('/api/users/me')).status).toBe(200);
    expect((await as(member).get(`/api/apartments/${apt._id}`)).status).toBe(403);

    const history = await as(manager).get(`/api/apartments/${apt._id}/residents?status=ended`);
    expect(history.body.data.map((r) => r.fullName)).toContain('Thành Viên');
  });

  test('không chuyển đi 2 lần, ngày chuyển đi không trước ngày chuyển đến', async () => {
    const ended = await ApartmentResident.findOne({ fullName: 'Thành Viên' });
    expect((await as(manager).patch(`/api/residents/${ended._id}/move-out`, {})).status).toBe(400);

    const kid = await ApartmentResident.findOne({ fullName: 'Bé Na' });
    const res = await as(manager).patch(`/api/residents/${kid._id}/move-out`, {
      moveOutDate: '2000-01-01',
    });
    expect(res.status).toBe(400);
  });

  test('người nộp phí chuyển đi -> chủ hộ thành người nộp phí; hết người -> căn trống', async () => {
    const rec = await as(manager).post(`/api/apartments/${apt2._id}/residents`, {
      fullName: 'Chủ A102',
      relation: 'owner',
    });
    const tenant = await as(manager).post(`/api/apartments/${apt2._id}/residents`, {
      fullName: 'Thuê A102',
      relation: 'tenant',
      isPayer: true,
    });
    expect(tenant.body.data.isPayer).toBe(true);

    await as(manager).patch(`/api/residents/${tenant.body.data._id}/move-out`, {});
    expect((await ApartmentResident.findById(rec.body.data._id)).isPayer).toBe(true);

    await as(manager).patch(`/api/residents/${rec.body.data._id}/move-out`, {});
    expect((await Apartment.findById(apt2._id)).status).toBe('vacant');

    // Chủ hộ cũ đã chuyển đi -> gắn được chủ hộ mới
    const newOwner = await as(manager).post(`/api/apartments/${apt2._id}/residents`, {
      fullName: 'Chủ mới',
      relation: 'owner',
    });
    expect(newOwner.status).toBe(201);
  });
});
