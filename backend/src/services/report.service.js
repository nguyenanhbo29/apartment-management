const Apartment = require('../models/Apartment');
const ServiceRequest = require('../models/ServiceRequest');
const OperationalTask = require('../models/OperationalTask');
const RequestHistory = require('../models/RequestHistory');
const AmenityBooking = require('../models/AmenityBooking');
const Vehicle = require('../models/Vehicle');
const Visitor = require('../models/Visitor');
const User = require('../models/User');
const { AppError, ERROR_CODES } = require('../utils/errors');
const {
  ROLES,
  APARTMENT_STATUS,
  OPEN_REQUEST_STATUSES,
  OPEN_TASK_STATUSES,
  REQUEST_STATUS,
  TASK_STATUS,
  VEHICLE_STATUS,
  VISITOR_STATUS,
} = require('../utils/constants');
const { nowVN, parseDateVN, dayRangeVN } = require('../shared/time');

/**
 * UC-47 Dashboard vận hành, UC-48 Báo cáo hiệu suất nhân viên (phần Người 2).
 * Xem docs/ke-hoach-nguoi-2.md mục 9.2, 9.3. Số liệu thật, tính trực tiếp từ DB.
 * Không có dữ liệu -> null (app hiển thị "—"), không trả 0 thay cho "chưa có việc".
 */

const DEFAULT_DAYS = 30;
const MAX_DAYS = 366;
const HOUR = 60 * 60 * 1000;

/** from/to dạng YYYY-MM-DD giờ VN (bao gồm cả ngày to). Mặc định 30 ngày gần nhất. */
function resolveRange({ from, to }) {
  const today = nowVN().startOf('day');
  const start = from ? parseDateVN(from) : today.minus({ days: DEFAULT_DAYS - 1 });
  const end = to ? parseDateVN(to) : today;
  if (!start || !end) throw new AppError(ERROR_CODES.BAD_REQUEST, 'Ngày không hợp lệ (YYYY-MM-DD)');
  if (start > end) throw new AppError(ERROR_CODES.BAD_REQUEST, 'Ngày bắt đầu phải trước ngày kết thúc');
  if (end.diff(start, 'days').days > MAX_DAYS) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, `Khoảng thời gian tối đa ${MAX_DAYS} ngày`);
  }
  return {
    from: start.toISODate(),
    to: end.toISODate(),
    $gte: start.toJSDate(),
    $lt: end.plus({ days: 1 }).toJSDate(),
  };
}

const countBy = async (Model, match, field = '$status') =>
  Object.fromEntries(
    (await Model.aggregate([{ $match: match }, { $group: { _id: field, n: { $sum: 1 } } }])).map(
      (r) => [r._id, r.n]
    )
  );

const ratio = (num, den) => (den ? Math.round((num / den) * 1000) / 1000 : null);

// ======================================================================== UC-47
/**
 * - byStatus của phiếu / nhiệm vụ là ảnh chụp HIỆN TẠI (khớp danh sách khi bấm vào xem).
 * - createdInRange, lượt đặt tiện ích tính trong khoảng from–to.
 */
async function operationsDashboard(query) {
  const range = resolveRange(query);
  const inRange = { $gte: range.$gte, $lt: range.$lt };
  const now = new Date();
  const today = dayRangeVN();

  const [
    totalApartments,
    occupied,
    requestByStatus,
    requestsCreated,
    requestsOverdue,
    taskByStatus,
    tasksCreated,
    tasksOverdue,
    bookingRows,
    vehiclesPending,
    visitorsToday,
  ] = await Promise.all([
    Apartment.countDocuments({}),
    Apartment.countDocuments({ status: APARTMENT_STATUS.OCCUPIED }),
    countBy(ServiceRequest, {}),
    // Phiếu cư dân tự rút không tính là phiếu mới
    ServiceRequest.countDocuments({ createdAt: inRange, status: { $ne: REQUEST_STATUS.CANCELLED } }),
    ServiceRequest.countDocuments({ status: { $in: [...OPEN_REQUEST_STATUSES] }, deadline: { $lt: now } }),
    countBy(OperationalTask, {}),
    OperationalTask.countDocuments({ createdAt: inRange }),
    OperationalTask.countDocuments({ status: { $in: [...OPEN_TASK_STATUSES] }, deadline: { $lt: now } }),
    AmenityBooking.aggregate([
      { $match: { startTime: inRange } },
      { $group: { _id: { amenityId: '$amenityId', status: '$status' }, n: { $sum: 1 } } },
      { $lookup: { from: 'amenities', localField: '_id.amenityId', foreignField: '_id', as: 'amenity' } },
    ]),
    Vehicle.countDocuments({ status: VEHICLE_STATUS.PENDING }),
    Visitor.countDocuments({
      status: VISITOR_STATUS.EXPECTED,
      visitDate: { $gte: today.start, $lt: today.end },
    }),
  ]);

  const byAmenity = new Map();
  for (const row of bookingRows) {
    const id = String(row._id.amenityId);
    const entry = byAmenity.get(id) || { amenityId: id, name: row.amenity[0]?.name ?? '—', total: 0, byStatus: {} };
    entry.byStatus[row._id.status] = row.n;
    entry.total += row.n;
    byAmenity.set(id, entry);
  }
  const amenities = [...byAmenity.values()].sort((a, b) => b.total - a.total);
  const sum = (obj, keys) => keys.reduce((s, k) => s + (obj[k] || 0), 0);

  return {
    range: { from: range.from, to: range.to },
    apartments: { total: totalApartments, occupied, occupancyRate: ratio(occupied, totalApartments) },
    requests: {
      byStatus: requestByStatus,
      open: sum(requestByStatus, OPEN_REQUEST_STATUSES),
      pending: requestByStatus[REQUEST_STATUS.PENDING] || 0,
      overdue: requestsOverdue,
      createdInRange: requestsCreated,
    },
    tasks: {
      byStatus: taskByStatus,
      open: sum(taskByStatus, OPEN_TASK_STATUSES),
      overdue: tasksOverdue,
      createdInRange: tasksCreated,
    },
    bookings: { total: amenities.reduce((s, a) => s + a.total, 0), byAmenity: amenities },
    vehicles: { pending: vehiclesPending },
    visitors: { expectedToday: visitorsToday },
  };
}

// ======================================================================== UC-48
/**
 * Mỗi nhân viên:
 * - assigned: số VIỆC được giao trong khoảng mà người đó vẫn giữ hoặc đã làm xong
 *   (phiếu: assign/reassign; nhiệm vụ: created/reassign). Việc đã hủy / cư dân rút: không tính.
 * - transferredAway: số việc được giao trong khoảng nhưng sau đó chuyển sang người khác.
 * - completed: phiếu tính lần ĐẦU báo xong (finish đầu tiên), nhiệm vụ tính lúc complete.
 * - onTimeRate: hoàn thành trước hạn / tổng hoàn thành. Tính theo lúc NHÂN VIÊN báo xong,
 *   không theo lúc cư dân nghiệm thu (closedAt) — tránh trừ điểm vì cư dân chậm.
 * - avgHandlingHours: từ lần được giao gần nhất (cho chính người đó) tới lúc hoàn thành.
 * - avgRating: điểm của phiếu đóng trong khoảng (người được giao hiện tại).
 * - reopenCount: số lần cư dân yêu cầu làm lại, tính cho người đã báo xong trước đó.
 */
async function staffPerformance(query) {
  const range = resolveRange(query);
  const inRange = { $gte: range.$gte, $lt: range.$lt };
  const staffFilter = { role: ROLES.STAFF };
  if (query.department) staffFilter.department = query.department;
  const staff = await User.find(staffFilter).select('fullName department status').sort({ department: 1, fullName: 1 });

  const stats = new Map(
    staff.map((s) => [
      String(s._id),
      {
        assigned: 0,
        transferredAway: 0,
        completed: 0,
        onTime: 0,
        handlingHours: [],
        ratingSum: 0,
        ratingCount: 0,
        reopenCount: 0,
      },
    ])
  );
  const forStaff = (id) => (id ? stats.get(String(id)) : undefined);

  // --- Giao việc trong khoảng (đếm theo việc, không theo số lần giao)
  // Mỗi (nhân viên, việc) được giao trong khoảng:
  //   - sau đó việc đã chuyển sang người khác -> transferredAway
  //   - việc đã hủy / cư dân rút -> không tính cho ai (không phải lỗi hay công của nhân viên)
  //   - còn lại (đang giữ hoặc đã xong) -> assigned
  const ASSIGN_ACTIONS = ['assign', 'reassign', 'created'];
  const assignEvents = await RequestHistory.find({
    action: { $in: ASSIGN_ACTIONS },
    assignedStaffId: { $ne: null },
    createdAt: inRange,
  }).select('requestId taskId assignedStaffId');
  const itemKey = (h) => String(h.requestId || h.taskId);
  const reqIds = [...new Set(assignEvents.filter((e) => e.requestId).map((e) => String(e.requestId)))];
  const tskIds = [...new Set(assignEvents.filter((e) => e.taskId).map((e) => String(e.taskId)))];
  const [itemAssignHistory, cancelledReqs, cancelledTasks] = await Promise.all([
    RequestHistory.find({
      $or: [{ requestId: { $in: reqIds } }, { taskId: { $in: tskIds } }],
      action: { $in: ASSIGN_ACTIONS },
      assignedStaffId: { $ne: null },
    })
      .sort({ createdAt: 1, _id: 1 })
      .select('requestId taskId assignedStaffId'),
    ServiceRequest.find({ _id: { $in: reqIds }, status: REQUEST_STATUS.CANCELLED }).distinct('_id'),
    OperationalTask.find({ _id: { $in: tskIds }, status: TASK_STATUS.CANCELLED }).distinct('_id'),
  ]);
  const cancelled = new Set([...cancelledReqs, ...cancelledTasks].map(String));
  // Người được giao cuối cùng của mỗi việc
  const lastAssignee = new Map();
  for (const h of itemAssignHistory) lastAssignee.set(itemKey(h), String(h.assignedStaffId));

  const counted = new Set();
  for (const e of assignEvents) {
    const key = `${e.assignedStaffId}|${itemKey(e)}`;
    if (counted.has(key) || cancelled.has(itemKey(e))) continue;
    counted.add(key);
    const s = forStaff(e.assignedStaffId);
    if (!s) continue;
    if (lastAssignee.get(itemKey(e)) === String(e.assignedStaffId)) s.assigned += 1;
    else s.transferredAway += 1;
  }

  // --- Hoàn thành: phiếu (lần finish đầu tiên) + nhiệm vụ (complete)
  const requestIdsFinishedInRange = await RequestHistory.find({
    action: 'finish',
    createdAt: inRange,
  }).distinct('requestId');
  const allFinish = await RequestHistory.find({ action: 'finish', requestId: { $in: requestIdsFinishedInRange } })
    .sort({ createdAt: 1 })
    .select('requestId updatedBy createdAt');
  const firstFinish = new Map();
  for (const e of allFinish) if (!firstFinish.has(String(e.requestId))) firstFinish.set(String(e.requestId), e);

  const completions = [...firstFinish.values()]
    .filter((e) => e.createdAt >= range.$gte && e.createdAt < range.$lt)
    .map((e) => ({ staffId: e.updatedBy, kind: 'request', itemId: e.requestId, at: e.createdAt }));
  const taskCompletes = await RequestHistory.find({ action: 'complete', taskId: { $ne: null }, createdAt: inRange })
    .select('taskId updatedBy createdAt');
  completions.push(...taskCompletes.map((e) => ({ staffId: e.updatedBy, kind: 'task', itemId: e.taskId, at: e.createdAt })));

  const requestIds = completions.filter((c) => c.kind === 'request').map((c) => c.itemId);
  const taskIds = completions.filter((c) => c.kind === 'task').map((c) => c.itemId);
  const [requestDocs, taskDocs, assignHistory] = await Promise.all([
    ServiceRequest.find({ _id: { $in: requestIds } }).select('deadline'),
    OperationalTask.find({ _id: { $in: taskIds } }).select('deadline'),
    RequestHistory.find({
      $or: [{ requestId: { $in: requestIds } }, { taskId: { $in: taskIds } }],
      action: { $in: ['assign', 'reassign', 'created'] },
      assignedStaffId: { $ne: null },
    })
      .sort({ createdAt: 1 })
      .select('requestId taskId assignedStaffId createdAt'),
  ]);
  const deadlineOf = new Map([...requestDocs, ...taskDocs].map((d) => [String(d._id), d.deadline]));

  for (const c of completions) {
    const s = forStaff(c.staffId);
    if (!s) continue;
    s.completed += 1;
    const deadline = deadlineOf.get(String(c.itemId));
    if (deadline && c.at <= deadline) s.onTime += 1;
    // Lần được giao gần nhất cho chính người này trước lúc hoàn thành
    const assignedAt = assignHistory
      .filter(
        (h) =>
          String(h.requestId || h.taskId) === String(c.itemId) &&
          String(h.assignedStaffId) === String(c.staffId) &&
          h.createdAt <= c.at
      )
      .pop()?.createdAt;
    if (assignedAt) s.handlingHours.push((c.at - assignedAt) / HOUR);
  }

  // --- Đánh giá của cư dân (phiếu đóng trong khoảng, có điểm)
  const ratings = await ServiceRequest.aggregate([
    { $match: { status: REQUEST_STATUS.CLOSED, closedAt: inRange, rating: { $ne: null } } },
    { $group: { _id: '$assignedStaffId', sum: { $sum: '$rating' }, n: { $sum: 1 } } },
  ]);
  for (const r of ratings) {
    const s = forStaff(r._id);
    if (s) {
      s.ratingSum = r.sum;
      s.ratingCount = r.n;
    }
  }

  // --- Bị yêu cầu làm lại: quy cho người báo xong ngay trước đó
  const reopens = await RequestHistory.find({ action: 'reopen', createdAt: inRange }).select('requestId createdAt');
  if (reopens.length) {
    const finishes = await RequestHistory.find({
      action: 'finish',
      requestId: { $in: reopens.map((r) => r.requestId) },
    })
      .sort({ createdAt: 1 })
      .select('requestId updatedBy createdAt');
    for (const r of reopens) {
      const by = finishes
        .filter((f) => String(f.requestId) === String(r.requestId) && f.createdAt <= r.createdAt)
        .pop()?.updatedBy;
      const s = forStaff(by);
      if (s) s.reopenCount += 1;
    }
  }

  const round1 = (x) => Math.round(x * 10) / 10;
  const items = staff
    .map((u) => {
      const s = stats.get(String(u._id));
      const hours = s.handlingHours;
      return {
        staff: { _id: u._id, fullName: u.fullName, department: u.department, status: u.status },
        assigned: s.assigned,
        transferredAway: s.transferredAway,
        completed: s.completed,
        onTime: s.onTime,
        onTimeRate: ratio(s.onTime, s.completed),
        avgHandlingHours: hours.length ? round1(hours.reduce((a, b) => a + b, 0) / hours.length) : null,
        avgRating: s.ratingCount ? round1(s.ratingSum / s.ratingCount) : null,
        ratingCount: s.ratingCount,
        reopenCount: s.reopenCount,
      };
    })
    .sort((a, b) => b.completed - a.completed || b.assigned - a.assigned);

  const totals = items.reduce(
    (t, i) => ({
      assigned: t.assigned + i.assigned,
      transferredAway: t.transferredAway + i.transferredAway,
      completed: t.completed + i.completed,
      onTime: t.onTime + i.onTime,
      reopenCount: t.reopenCount + i.reopenCount,
    }),
    { assigned: 0, transferredAway: 0, completed: 0, onTime: 0, reopenCount: 0 }
  );
  return {
    range: { from: range.from, to: range.to },
    totals: { ...totals, onTimeRate: ratio(totals.onTime, totals.completed) },
    items,
  };
}

module.exports = { resolveRange, operationsDashboard, staffPerformance };
