const mongoose = require('mongoose');
const ServiceRequest = require('../models/ServiceRequest');
const RequestHistory = require('../models/RequestHistory');
const OperationalTask = require('../models/OperationalTask');
const Vehicle = require('../models/Vehicle');
const Visitor = require('../models/Visitor');
const Amenity = require('../models/Amenity');
const AmenitySlot = require('../models/AmenitySlot');
const AmenityBooking = require('../models/AmenityBooking');
const { PRIORITY_RANK } = require('../models/ServiceRequest');
const { nowVN, dayRangeVN, combineVN } = require('../shared/time');

/**
 * Dữ liệu demo cho module vận hành (Người 2) — kịch bản demo mục 10.2 của kế hoạch.
 * Ghi thẳng collection (bỏ qua timestamps của Mongoose) để dựng mốc thời gian trong quá khứ
 * và lịch sử khớp từng bước. Chạy lại không tạo trùng (đánh dấu bằng mã SR-DEMO01).
 */

const H = 60 * 60 * 1000;
const D = 24 * H;
const oid = () => new mongoose.Types.ObjectId();

async function seedOperations(users, apartments) {
  if (await ServiceRequest.exists({ requestCode: 'SR-DEMO01' })) {
    console.log('= dữ liệu vận hành demo đã có, bỏ qua');
    return;
  }
  const u = (email) => users[`${email}@apartment.local`];
  const manager = Object.values(users).find((x) => x.role === 'manager');
  const [tech, tech2, guard, facility] = ['technical', 'technical2', 'security', 'facility'].map(u);
  const [r1, r3, r4] = ['resident1', 'resident3', 'resident4'].map(u);
  const apt = (code) => apartments[code]._id;
  const now = Date.now();
  const at = (offset) => new Date(now + offset);

  // ------------------------------------------------------------------ Phiếu (M5)
  const requests = [];
  const history = [];
  let n = 0;

  /**
   * steps: [[action, offsetFromNow, actor, extra?]]; trạng thái sau mỗi bước theo bảng chuyển.
   */
  function request(data, steps) {
    n += 1;
    const _id = oid();
    const createdAt = at(steps[0][1]);
    const NEXT = {
      created: 'pending', assign: 'assigned', reassign: 'assigned', start: 'in_progress',
      finish: 'waiting_confirmation', confirm: 'closed', reopen: 'reopened', reject: 'rejected',
    };
    let status;
    let previous = null;
    for (const [action, offset, actor, extra = {}] of steps) {
      status = NEXT[action];
      history.push({
        _id: oid(),
        requestId: _id,
        updatedBy: actor._id,
        action,
        previousStatus: previous,
        newStatus: status,
        note: extra.note,
        attachments: [],
        assignedStaffId: extra.staff?._id,
        deadline: extra.deadline,
        createdAt: at(offset),
      });
      previous = status;
    }
    const lastAssign = [...steps].reverse().find(([a]) => a === 'assign' || a === 'reassign');
    const finishes = steps.filter(([a]) => a === 'finish');
    const priority = data.priority || 'normal';
    requests.push({
      _id,
      requestCode: `SR-DEMO${String(n).padStart(2, '0')}`,
      requestType: 'repair',
      category: 'electric',
      priority,
      priorityRank: PRIORITY_RANK[priority],
      images: [],
      resultImages: [],
      reopenCount: steps.filter(([a]) => a === 'reopen').length,
      autoClosed: false,
      department: lastAssign ? 'technical' : null,
      assignedStaffId: lastAssign ? lastAssign[3].staff._id : null,
      assignedAt: lastAssign ? at(lastAssign[1]) : undefined,
      deadline: lastAssign ? lastAssign[3].deadline : undefined,
      firstFinishedAt: finishes[0] ? at(finishes[0][1]) : undefined,
      waitingSince: status === 'waiting_confirmation' ? at(finishes.at(-1)[1]) : undefined,
      status,
      createdAt,
      updatedAt: at(steps.at(-1)[1]),
      ...data,
    });
  }

  const a = (staff, deadlineOffset) => ({ staff, deadline: at(deadlineOffset) });

  // Kịch bản 1 (sửa chữa): cư dân A-101 có phiếu chờ nghiệm thu để demo nghiệm thu / làm lại
  request(
    { title: 'Ổ cắm phòng ngủ bị chập', description: 'Cắm sạc thì nhảy aptomat', apartmentId: apt('A-101'), createdBy: r1._id, resultNote: 'Đã thay ổ cắm mới' },
    [['created', -2 * D, r1], ['assign', -2 * D + H, manager, a(tech, D)], ['start', -2 * D + 3 * H, tech], ['finish', -D, tech, { note: 'Đã thay ổ cắm mới' }]]
  );
  // Hàng chờ của Manager
  request(
    { title: 'Bóng đèn hành lang tầng 1 bị cháy', description: 'Hành lang tối, nguy hiểm buổi tối', apartmentId: apt('A-101'), createdBy: r1._id, priority: 'high', category: 'electric' },
    [['created', -3 * H, r1]]
  );
  request(
    { title: 'Tiếng ồn sau 23h', description: 'Căn bên cạnh hát karaoke đến khuya', apartmentId: apt('A-201'), createdBy: r3._id, requestType: 'complaint', category: 'noise' },
    [['created', -5 * H, r3]]
  );
  request(
    { title: 'Nước rò dưới bồn rửa', description: 'Rò nước ra sàn bếp', apartmentId: apt('A-201'), createdBy: r3._id, category: 'plumbing', priority: 'urgent' },
    [['created', -30 * 60 * 1000, r3]]
  );
  // Việc của nhân viên: đang giao, đang làm QUÁ HẠN
  request(
    { title: 'Vòi sen phòng tắm yếu', description: 'Nước chảy rất yếu', apartmentId: apt('A-202'), createdBy: r4._id, category: 'plumbing' },
    [['created', -D, r4], ['assign', -20 * H, manager, a(tech, D)]]
  );
  request(
    { title: 'Điều hòa phòng khách không lạnh', description: 'Bật 18 độ vẫn nóng', apartmentId: apt('A-202'), createdBy: r4._id, priority: 'high' },
    [['created', -4 * D, r4], ['assign', -4 * D + 2 * H, manager, a(tech2, -D)], ['start', -3 * D, tech2]]
  );
  // Đã đóng: đúng hạn 5 sao; trễ hạn + làm lại 3 sao (cho báo cáo hiệu suất)
  request(
    { title: 'Thay bóng đèn ban công', description: 'Đèn ban công không sáng', apartmentId: apt('A-101'), createdBy: r1._id, rating: 5, feedback: 'Nhanh, gọn', closedAt: at(-5 * D), resultNote: 'Đã thay bóng LED' },
    [['created', -7 * D, r1], ['assign', -7 * D + H, manager, a(tech, -6 * D)], ['start', -7 * D + 2 * H, tech], ['finish', -7 * D + 5 * H, tech, { note: 'Đã thay bóng LED' }], ['confirm', -5 * D, r1, { note: 'Nhanh, gọn' }]]
  );
  request(
    { title: 'Cửa thang máy đóng chậm', description: 'Cửa đóng mở giật', apartmentId: apt('A-201'), createdBy: r3._id, category: 'elevator', rating: 3, feedback: 'Phải làm lại một lần', closedAt: at(-2 * D), resultNote: 'Đã chỉnh cảm biến' },
    [['created', -10 * D, r3], ['assign', -10 * D + H, manager, a(tech2, -9 * D)], ['start', -9 * D + H, tech2], ['finish', -8 * D, tech2, { note: 'Đã vệ sinh ray cửa' }], ['reopen', -7 * D, r3, { note: 'Vẫn còn giật' }], ['start', -6 * D, tech2], ['finish', -5 * D, tech2, { note: 'Đã chỉnh cảm biến' }], ['confirm', -2 * D, r3, { note: 'Phải làm lại một lần' }]]
  );
  request(
    { title: 'Sơn lại toàn bộ căn hộ', description: 'Muốn ban quản lý sơn lại tường', apartmentId: apt('A-202'), createdBy: r4._id, category: 'other', rejectReason: 'Ngoài phạm vi ban quản lý, cư dân tự thuê đơn vị sơn' },
    [['created', -3 * D, r4], ['reject', -3 * D + 4 * H, manager, { note: 'Ngoài phạm vi ban quản lý, cư dân tự thuê đơn vị sơn' }]]
  );

  await ServiceRequest.collection.insertMany(requests);
  await RequestHistory.collection.insertMany(history);

  // ------------------------------------------------------------------ Nhiệm vụ (M7)
  const taskHistory = [];
  const task = (code, data, steps) => {
    const _id = oid();
    const base = {
      _id, taskCode: code, priority: 'normal', priorityRank: PRIORITY_RANK.normal,
      createdBy: manager._id, resultImages: [], assignedAt: at(steps[0][1]), ...data,
    };
    const STATUS = { created: 'assigned', start: 'in_progress', complete: 'completed' };
    let prev = null;
    for (const [action, offset, actor] of steps) {
      base.status = STATUS[action];
      taskHistory.push({
        _id: oid(), taskId: _id, updatedBy: actor._id, action, previousStatus: prev, newStatus: base.status,
        attachments: [], assignedStaffId: action === 'created' ? data.assignedStaffId : undefined,
        deadline: action === 'created' ? data.deadline : undefined, createdAt: at(offset),
      });
      prev = base.status;
    }
    base.createdAt = at(steps[0][1]);
    base.updatedAt = at(steps.at(-1)[1]);
    return base;
  };
  await OperationalTask.collection.insertMany([
    task('TK-DEMO01', { title: 'Kiểm tra bình chữa cháy tầng 1–5', category: 'inspection', location: 'Khối A', department: 'technical', assignedStaffId: tech._id, deadline: at(2 * D), priority: 'high', priorityRank: PRIORITY_RANK.high }, [['created', -H, manager]]),
    task('TK-DEMO02', { title: 'Tuần tra hầm B1 ca đêm', category: 'patrol', location: 'Hầm B1', department: 'security', assignedStaffId: guard._id, deadline: at(-6 * H), startedAt: at(-D) }, [['created', -2 * D, manager], ['start', -D, guard]]),
    task('TK-DEMO03', { title: 'Vệ sinh hồ bơi định kỳ', category: 'cleaning', location: 'Tầng 5', department: 'facility', assignedStaffId: facility._id, deadline: at(-D), completedAt: at(-2 * D), completionNote: 'Đã thay nước, vệ sinh lọc' }, [['created', -4 * D, manager], ['start', -3 * D, facility], ['complete', -2 * D, facility]]),
  ]);
  await RequestHistory.collection.insertMany(taskHistory);

  // ------------------------------------------------------------------ Xe, khách (M3)
  await Vehicle.collection.insertMany([
    { apartmentId: apt('A-101'), ownerId: r1._id, type: 'motorbike', plateNumber: '29B112345', brand: 'Honda Vision', color: 'Trắng', status: 'approved', reviewedBy: guard._id, reviewedAt: at(-20 * D), createdAt: at(-21 * D), updatedAt: at(-20 * D) },
    { apartmentId: apt('A-101'), ownerId: r1._id, type: 'car', plateNumber: '30A12345', brand: 'Toyota Vios', color: 'Bạc', status: 'approved', reviewedBy: guard._id, reviewedAt: at(-20 * D), createdAt: at(-21 * D), updatedAt: at(-20 * D) },
    { apartmentId: apt('A-201'), ownerId: r3._id, type: 'car', plateNumber: '51F67890', brand: 'Mazda 3', color: 'Đỏ', status: 'pending', createdAt: at(-3 * H), updatedAt: at(-3 * H) },
    { apartmentId: apt('A-202'), ownerId: r4._id, type: 'motorbike', plateNumber: '43C155555', brand: 'Yamaha', status: 'rejected', rejectReason: 'Ảnh cà vẹt bị mờ', reviewedBy: guard._id, reviewedAt: at(-D), createdAt: at(-2 * D), updatedAt: at(-D) },
  ]);

  const today = dayRangeVN();
  // Giờ hẹn phải nằm trong hôm nay, kể cả khi seed lúc gần nửa đêm
  const inToday = (d) => new Date(Math.min(Math.max(d.getTime(), today.start.getTime()), today.end.getTime() - 60 * 1000));
  await Visitor.collection.insertMany([
    { appointmentCode: 'VS-DEMO01', apartmentId: apt('A-101'), createdBy: r1._id, visitorName: 'Trần Văn Khách', visitorPhone: '0912345678', numberOfPeople: 2, status: 'expected', visitDate: today.start, timeFrom: inToday(at(-10 * 60 * 1000)), timeTo: inToday(at(3 * H)), createdAt: at(-D), updatedAt: at(-D) },
    { appointmentCode: 'VS-DEMO02', apartmentId: apt('A-201'), createdBy: r3._id, visitorName: 'Lê Thị Bạn', visitorPhone: '0987654321', numberOfPeople: 1, vehiclePlate: '30G88888', status: 'checked_in', visitDate: today.start, timeFrom: inToday(at(-2 * H)), timeTo: inToday(at(2 * H)), checkInTime: at(-H), checkedInBy: guard._id, createdAt: at(-D), updatedAt: at(-H) },
  ]);

  // ------------------------------------------------------------------ Đặt tiện ích (M6)
  const pool = await Amenity.findOne({ name: 'Hồ bơi' });
  const bbq = await Amenity.findOne({ name: 'Khu BBQ' });
  if (pool && bbq) {
    const tomorrow = nowVN().plus({ days: 1 }).toISODate();
    const poolStart = combineVN(tomorrow, '07:00');
    const bbqStart = combineVN(tomorrow, '18:00');
    const bookingDate = nowVN().plus({ days: 1 }).startOf('day').toJSDate();
    await AmenityBooking.collection.insertMany([
      { amenityId: pool._id, apartmentId: apt('A-101'), bookedBy: r1._id, bookingDate, startTime: poolStart, endTime: new Date(poolStart.getTime() + H), numberOfParticipants: 3, status: 'confirmed', cancelDeadlineHours: pool.cancelDeadlineHours, cancelledByStaff: false, createdAt: at(-H), updatedAt: at(-H) },
      { amenityId: bbq._id, apartmentId: apt('A-201'), bookedBy: r3._id, bookingDate, startTime: bbqStart, endTime: new Date(bbqStart.getTime() + 2 * H), numberOfParticipants: 8, note: 'Tiệc sinh nhật', status: 'pending', cancelDeadlineHours: bbq.cancelDeadlineHours, cancelledByStaff: false, createdAt: at(-2 * H), updatedAt: at(-2 * H) },
    ]);
    // Lượt đã dùng / đã hủy trong quá khứ để dashboard có số liệu theo kỳ.
    // Slot quá khứ không cần bộ đếm vì không còn ai đặt được.
    const past = (days, time) => combineVN(nowVN().minus({ days }).toISODate(), time);
    const pastDay = (days) => nowVN().minus({ days }).startOf('day').toJSDate();
    const gym = await Amenity.findOne({ name: 'Phòng gym' });
    await AmenityBooking.collection.insertMany([
      { amenityId: pool._id, apartmentId: apt('A-201'), bookedBy: r3._id, bookingDate: pastDay(3), startTime: past(3, '17:00'), endTime: new Date(past(3, '17:00').getTime() + H), numberOfParticipants: 2, status: 'completed', completedAt: new Date(past(3, '17:00').getTime() + H), cancelDeadlineHours: pool.cancelDeadlineHours, cancelledByStaff: false, createdAt: at(-5 * D), updatedAt: at(-3 * D) },
      { amenityId: bbq._id, apartmentId: apt('A-101'), bookedBy: r1._id, bookingDate: pastDay(6), startTime: past(6, '18:00'), endTime: new Date(past(6, '18:00').getTime() + 2 * H), numberOfParticipants: 10, status: 'completed', reviewedBy: facility._id, reviewedAt: at(-8 * D), completedAt: new Date(past(6, '18:00').getTime() + 2 * H), cancelDeadlineHours: bbq.cancelDeadlineHours, cancelledByStaff: false, createdAt: at(-9 * D), updatedAt: at(-6 * D) },
      { amenityId: bbq._id, apartmentId: apt('A-202'), bookedBy: u('resident4')._id, bookingDate: pastDay(4), startTime: past(4, '20:00'), endTime: new Date(past(4, '20:00').getTime() + 2 * H), numberOfParticipants: 6, status: 'rejected', reviewedBy: facility._id, reviewedAt: at(-6 * D), rejectReason: 'Trùng lịch bảo trì khu BBQ', cancelDeadlineHours: bbq.cancelDeadlineHours, cancelledByStaff: false, createdAt: at(-7 * D), updatedAt: at(-6 * D) },
      ...(gym ? [{ amenityId: gym._id, apartmentId: apt('A-101'), bookedBy: r1._id, bookingDate: pastDay(2), startTime: past(2, '06:00'), endTime: new Date(past(2, '06:00').getTime() + H), numberOfParticipants: 1, status: 'cancelled', cancelledAt: at(-3 * D), cancelledBy: r1._id, cancelDeadlineHours: gym.cancelDeadlineHours, cancelledByStaff: false, createdAt: at(-4 * D), updatedAt: at(-3 * D) }] : []),
    ]);
    // Bộ đếm chỗ (số người) phải khớp các booking đang giữ chỗ
    await AmenitySlot.collection.insertMany([
      { amenityId: pool._id, slotStart: poolStart, used: 3, createdAt: at(-H), updatedAt: at(-H) },
      { amenityId: bbq._id, slotStart: bbqStart, used: 8, createdAt: at(-2 * H), updatedAt: at(-2 * H) },
    ]);
  }

  console.log(`+ vận hành   ${requests.length} phiếu, 3 nhiệm vụ, 4 xe, 2 khách, 6 lượt đặt tiện ích`);
}

module.exports = { seedOperations };
