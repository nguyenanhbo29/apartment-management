const ServiceRequest = require('../models/ServiceRequest');
const RequestHistory = require('../models/RequestHistory');
const User = require('../models/User');
const { PRIORITY_RANK } = require('../models/ServiceRequest');
const { AppError, ERROR_CODES } = require('../utils/errors');
const {
  ROLES,
  USER_STATUS,
  REQUEST_TYPE,
  REQUEST_STATUS: S,
  OPEN_REQUEST_STATUSES,
} = require('../utils/constants');
const { assertActiveResident, myApartmentIds } = require('../shared/residency');
const { assertAssignable } = require('../shared/assignee');
const { createWithCode } = require('../shared/code');
const { withTransaction } = require('../shared/transaction');
const { saveImages, removeImages } = require('./upload.service');
const { notifyUsers } = require('./notify.service');

/**
 * M5 — Phiếu yêu cầu sửa chữa / phản ánh (UC-27 → 34).
 * Xem docs/ke-hoach-nguoi-2.md mục 6.
 */

const AUTO_CLOSE_DAYS = 7;
const UPLOAD_FOLDER = 'service-requests';
const isOpenStatus = (status) => OPEN_REQUEST_STATUSES.includes(status);
const sameId = (a, b) => a != null && b != null && String(a) === String(b);

// ---------------------------------------------------------------- Quyền theo vai trò / dữ liệu
const isManager = (u) => u.role === ROLES.MANAGER;
const isAssignee = (u, r) => u.role === ROLES.STAFF && sameId(r.assignedStaffId, u._id);
const isCreator = (u, r) => u.role === ROLES.RESIDENT && sameId(r.createdBy, u._id);

/** Bảng chuyển trạng thái (mục 6.2): dữ liệu, không phải chuỗi if/else. */
const TRANSITIONS = Object.freeze({
  reject: { from: [S.PENDING], to: S.REJECTED, can: isManager },
  assign: { from: [S.PENDING, S.REOPENED], to: S.ASSIGNED, can: isManager },
  reassign: { from: [S.ASSIGNED, S.IN_PROGRESS], to: S.ASSIGNED, can: isManager },
  start: { from: [S.ASSIGNED, S.REOPENED], to: S.IN_PROGRESS, can: isAssignee },
  finish: { from: [S.IN_PROGRESS], to: S.WAITING_CONFIRMATION, can: isAssignee },
  confirm: { from: [S.WAITING_CONFIRMATION], to: S.CLOSED, can: isCreator },
  reopen: { from: [S.WAITING_CONFIRMATION], to: S.REOPENED, can: isCreator },
  // Cư dân rút phiếu khi chưa ai bắt đầu làm. Phiếu đã từng xử lý (làm lại rồi giao lại)
  // không rút được: việc đã làm, cư dân dùng nghiệm thu.
  cancel: {
    from: [S.PENDING, S.ASSIGNED],
    to: S.CANCELLED,
    can: (u, r) => isCreator(u, r) && !r.firstFinishedAt,
  },
});

/** Các hành động người xem được làm ngay lúc này (để app hiện nút; backend vẫn kiểm tra lại). */
const allowedActions = (actor, request) =>
  Object.entries(TRANSITIONS)
    .filter(([, rule]) => rule.from.includes(request.status) && rule.can(actor, request))
    .map(([action]) => action);

const computeOverdue = (r, now = new Date()) =>
  Boolean(r.deadline && isOpenStatus(r.status) && r.deadline < now);

const withOverdue = (doc) => {
  const o = typeof doc.toJSON === 'function' ? doc.toJSON() : doc;
  return { ...o, isOverdue: computeOverdue(o) };
};

/**
 * Cư dân xem được: phiếu do mình tạo; phiếu sửa chữa của căn mình đang ở
 * (thành viên cùng căn thấy nhau). Phản ánh chỉ người tạo thấy. (mục 2.2 #4)
 */
async function residentScope(userId) {
  const apartmentIds = await myApartmentIds(userId);
  return {
    $or: [
      { createdBy: userId },
      { apartmentId: { $in: apartmentIds }, requestType: REQUEST_TYPE.REPAIR },
    ],
  };
}

/** Phạm vi xem theo vai trò; null = không được xem gì. */
async function scopeFor(actor) {
  if (isManager(actor)) return {};
  if (actor.role === ROLES.STAFF) return { assignedStaffId: actor._id };
  if (actor.role === ROLES.RESIDENT) return residentScope(actor._id);
  return null;
}

/** Không thuộc phạm vi trả 404 như không tồn tại (mục 2.2 #10). */
async function findVisibleOrThrow(actor, id) {
  const scope = await scopeFor(actor);
  const request = scope && (await ServiceRequest.findOne({ _id: id, ...scope }));
  if (!request) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy phiếu');
  return request;
}

const activeManagerIds = async () =>
  (await User.find({ role: ROLES.MANAGER, status: USER_STATUS.ACTIVE }).select('_id')).map(
    (u) => u._id
  );

const paged = (page, limit, total) => ({
  page,
  limit,
  total,
  totalPages: Math.ceil(total / limit),
});

const POPULATE = [
  { path: 'apartmentId', select: 'code floor' },
  { path: 'createdBy', select: 'fullName phone' },
  { path: 'assignedStaffId', select: 'fullName phone department' },
];

// ---------------------------------------------------------------- UC-27, UC-28: tạo phiếu
async function createRequest(actor, data, files = []) {
  await assertActiveResident(actor._id, data.apartmentId);
  const images = await saveImages(files, UPLOAD_FOLDER);
  let request;
  try {
    request = await withTransaction(async (session) => {
      const doc = await createWithCode(
        ServiceRequest,
        'requestCode',
        'SR-',
        {
          ...data,
          priorityRank: PRIORITY_RANK[data.priority || 'normal'],
          createdBy: actor._id,
          images,
          status: S.PENDING,
        },
        { session }
      );
      await RequestHistory.create(
        [
          {
            requestId: doc._id,
            updatedBy: actor._id,
            action: 'created',
            newStatus: S.PENDING,
            attachments: images,
          },
        ],
        { session }
      );
      return doc;
    });
  } catch (err) {
    await removeImages(images);
    throw err;
  }

  await notifyUsers({
    userIds: await activeManagerIds(),
    type: 'service_request_created',
    title: `Phiếu mới ${request.requestCode}`,
    body: `${actor.fullName}: ${request.title}`,
    link: { kind: 'service_request', id: String(request._id) },
  });
  return withOverdue(request);
}

// ---------------------------------------------------------------- UC-29: danh sách của tôi
async function listMine(actor, { page, limit, status, type }) {
  const filter = await residentScope(actor._id);
  if (status) filter.status = status;
  if (type) filter.requestType = type;
  const [items, total] = await Promise.all([
    ServiceRequest.find(filter)
      .populate('apartmentId', 'code floor')
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    ServiceRequest.countDocuments(filter),
  ]);
  return { items: items.map(withOverdue), meta: paged(page, limit, total) };
}

// ---------------------------------------------------------------- UC-30: hàng chờ của Manager
async function listForManager({ page, limit, status, priority, type, department, overdue }) {
  const filter = {};
  if (status && status !== 'all') filter.status = status;
  if (priority) filter.priority = priority;
  if (type) filter.requestType = type;
  if (department) filter.department = department;
  if (overdue) {
    filter.status = { $in: [...OPEN_REQUEST_STATUSES] };
    filter.deadline = { $lt: new Date() };
  }
  const [items, total] = await Promise.all([
    ServiceRequest.find(filter)
      .populate(POPULATE)
      .sort({ priorityRank: 1, createdAt: 1 })
      .skip((page - 1) * limit)
      .limit(limit),
    ServiceRequest.countDocuments(filter),
  ]);
  return { items: items.map(withOverdue), meta: paged(page, limit, total) };
}

// UC-31 (việc của tôi): gộp phiếu + nhiệm vụ ở services/assignment.service.js

// ---------------------------------------------------------------- UC-29: chi tiết + timeline
// Ghi chú nội bộ (lý do giao / chuyển người) không hiện cho cư dân
const INTERNAL_NOTE_ACTIONS = ['assign', 'reassign'];

async function getDetail(actor, id) {
  const request = await findVisibleOrThrow(actor, id);
  await request.populate(POPULATE);
  const history = await RequestHistory.find({ requestId: request._id })
    .populate('updatedBy', 'fullName role')
    .populate('assignedStaffId', 'fullName')
    .sort({ createdAt: 1 });

  const hideInternal = actor.role === ROLES.RESIDENT;
  const timeline = history.map((h) => {
    const o = h.toJSON();
    if (hideInternal && INTERNAL_NOTE_ACTIONS.includes(o.action)) delete o.note;
    return o;
  });

  // allowedActions cần id thô của người tạo / người được giao
  const raw = {
    status: request.status,
    createdBy: request.createdBy?._id ?? request.createdBy,
    assignedStaffId: request.assignedStaffId?._id ?? request.assignedStaffId,
  };
  return { ...withOverdue(request), timeline, allowedActions: allowedActions(actor, raw) };
}

// ---------------------------------------------------------------- UC-30 → 34: đổi trạng thái
/**
 * Kiểm tra dữ liệu riêng của từng hành động, trả về thay đổi cho câu update,
 * ghi chú và tệp đính kèm cho lịch sử.
 */
async function buildChanges(action, request, input, now) {
  switch (action) {
    case 'reject':
      return { set: { rejectReason: input.reason }, note: input.reason };

    case 'assign':
    case 'reassign': {
      const staff = await assertAssignable(input.staffId, input.department);
      if (action === 'reassign' && sameId(staff._id, request.assignedStaffId)) {
        throw new AppError(ERROR_CODES.BAD_REQUEST, 'Nhân viên mới phải khác nhân viên hiện tại');
      }
      const deadline = input.deadline || request.deadline;
      if (!deadline || deadline <= now) {
        throw new AppError(ERROR_CODES.BAD_REQUEST, 'Hạn xử lý phải ở tương lai');
      }
      const set = {
        department: input.department,
        assignedStaffId: staff._id,
        assignedAt: now,
        deadline,
      };
      if (input.priority) {
        set.priority = input.priority;
        set.priorityRank = PRIORITY_RANK[input.priority];
      }
      return {
        set,
        note: input.note,
        assignedStaffId: staff._id,
        deadline,
        previousStaffId: request.assignedStaffId,
      };
    }

    case 'start':
      return { set: {} };

    case 'finish':
      return {
        set: {
          resultNote: input.note,
          resultImages: input.images,
          waitingSince: now,
          firstFinishedAt: request.firstFinishedAt || now,
        },
        note: input.note,
        attachments: input.images,
      };

    case 'confirm':
      return {
        set: { closedAt: now, rating: input.rating, feedback: input.feedback, waitingSince: null },
        note: input.feedback,
      };

    case 'reopen':
      return { set: { waitingSince: null }, inc: { reopenCount: 1 }, note: input.reason };

    case 'cancel':
      return { set: { cancelledAt: now, cancelReason: input.reason }, note: input.reason };

    default:
      throw new Error(`Hành động không hỗ trợ: ${action}`);
  }
}

async function transition(actor, id, action, input = {}, files = []) {
  const rule = TRANSITIONS[action];
  const request = await findVisibleOrThrow(actor, id);
  if (!rule.can(actor, request)) {
    throw new AppError(ERROR_CODES.FORBIDDEN, 'Bạn không có quyền thao tác phiếu này');
  }
  // Báo sai trạng thái sớm (trước khi lưu ảnh); câu update có điều kiện vẫn chặn tranh chấp
  if (!rule.from.includes(request.status)) {
    throw new AppError(ERROR_CODES.INVALID_STATE, 'Phiếu đã thay đổi trạng thái, vui lòng tải lại');
  }

  const now = new Date();
  const images = action === 'finish' ? await saveImages(files, UPLOAD_FOLDER) : [];
  let updated;
  let changes;
  try {
    changes = await buildChanges(action, request, { ...input, images }, now);
    updated = await withTransaction(async (session) => {
      const update = { $set: { status: rule.to, ...changes.set } };
      if (changes.inc) update.$inc = changes.inc;
      const doc = await ServiceRequest.findOneAndUpdate(
        { _id: request._id, status: { $in: rule.from } },
        update,
        { new: true, session }
      );
      if (!doc) {
        throw new AppError(ERROR_CODES.INVALID_STATE, 'Phiếu đã thay đổi trạng thái, vui lòng tải lại');
      }
      await RequestHistory.create(
        [
          {
            requestId: doc._id,
            updatedBy: actor._id,
            action,
            previousStatus: request.status,
            newStatus: rule.to,
            note: changes.note,
            attachments: changes.attachments,
            assignedStaffId: changes.assignedStaffId,
            deadline: changes.deadline,
          },
        ],
        { session }
      );
      return doc;
    });
  } catch (err) {
    await removeImages(images);
    throw err;
  }

  await notifyForTransition(action, updated, actor, changes);
  return withOverdue(updated);
}

// ---------------------------------------------------------------- Thông báo (ngoài transaction)
// Mỗi hành động -> danh sách thông báo { type, to, title, body, managers? }.
// Danh sách `type` ghi trong backend/README.md.
const NOTIFY = {
  reject: (r) => [
    {
      type: 'service_request_rejected',
      to: [r.createdBy],
      title: `Phiếu ${r.requestCode} bị từ chối`,
      body: `Lý do: ${r.rejectReason}`,
    },
  ],
  assign: (r) => [
    {
      type: 'service_request_assigned',
      to: [r.assignedStaffId],
      title: `Bạn được giao phiếu ${r.requestCode}`,
      body: r.title,
    },
    {
      type: 'service_request_accepted',
      to: [r.createdBy],
      title: `Phiếu ${r.requestCode} đã được tiếp nhận`,
      body: 'Phiếu đã được phân công cho nhân viên xử lý',
    },
  ],
  reassign: (r, c) => [
    {
      type: 'service_request_assigned',
      to: [r.assignedStaffId],
      title: `Bạn được giao phiếu ${r.requestCode}`,
      body: r.title,
    },
    {
      type: 'service_request_unassigned',
      to: [c.previousStaffId],
      title: `Phiếu ${r.requestCode} đã chuyển cho người khác`,
      body: r.title,
    },
  ],
  start: (r) => [
    {
      type: 'service_request_started',
      to: [r.createdBy],
      title: `Phiếu ${r.requestCode} đang được xử lý`,
      body: r.title,
    },
  ],
  finish: (r) => [
    {
      type: 'service_request_waiting_confirmation',
      to: [r.createdBy],
      title: `Phiếu ${r.requestCode} đã xử lý xong`,
      body: `Vui lòng nghiệm thu trong ${AUTO_CLOSE_DAYS} ngày`,
    },
  ],
  confirm: (r) => [
    {
      type: 'service_request_closed',
      to: [r.assignedStaffId],
      title: `Phiếu ${r.requestCode} đã được nghiệm thu`,
      body: `Đánh giá ${r.rating}/5`,
    },
  ],
  // Chờ tiếp nhận: chưa ai nhận, không cần báo. Đã phân công: báo nhân viên khỏi đi
  cancel: (r) =>
    r.assignedStaffId
      ? [
          {
            type: 'service_request_cancelled',
            to: [r.assignedStaffId],
            title: `Phiếu ${r.requestCode} đã được cư dân rút lại`,
            body: r.cancelReason ? `Lý do: ${r.cancelReason}` : r.title,
          },
        ]
      : [],
  reopen: (r) => [
    {
      type: 'service_request_reopened',
      to: [r.assignedStaffId],
      managers: true,
      title: `Phiếu ${r.requestCode} bị yêu cầu làm lại`,
      body: r.title,
    },
  ],
};

async function notifyForTransition(action, request, actor, changes = {}) {
  const build = NOTIFY[action];
  if (!build) return;
  for (const m of build(request, changes)) {
    const userIds = [...m.to];
    if (m.managers) userIds.push(...(await activeManagerIds()));
    await notifyUsers({
      // Không tự báo cho chính người vừa thao tác
      userIds: userIds.filter((uid) => !sameId(uid, actor?._id)),
      type: m.type,
      title: m.title,
      body: m.body,
      link: { kind: 'service_request', id: String(request._id) },
    });
  }
}

// ---------------------------------------------------------------- Job: tự đóng sau 7 ngày
/**
 * Đóng phiếu chờ nghiệm thu quá AUTO_CLOSE_DAYS ngày tính từ lần báo xong gần nhất.
 * Mỗi phiếu dùng update có điều kiện để không đè thao tác nghiệm thu đồng thời của cư dân.
 * Trả về số phiếu đã đóng.
 */
async function autoCloseExpired(now = new Date()) {
  const cutoff = new Date(now.getTime() - AUTO_CLOSE_DAYS * 24 * 60 * 60 * 1000);
  const candidates = await ServiceRequest.find({
    status: S.WAITING_CONFIRMATION,
    waitingSince: { $lte: cutoff },
  }).select('_id');

  let closed = 0;
  for (const { _id } of candidates) {
    const doc = await withTransaction(async (session) => {
      const d = await ServiceRequest.findOneAndUpdate(
        { _id, status: S.WAITING_CONFIRMATION, waitingSince: { $lte: cutoff } },
        { $set: { status: S.CLOSED, closedAt: now, autoClosed: true, waitingSince: null } },
        { new: true, session }
      );
      if (!d) return null;
      await RequestHistory.create(
        [
          {
            requestId: _id,
            updatedBy: null,
            action: 'auto_closed',
            previousStatus: S.WAITING_CONFIRMATION,
            newStatus: S.CLOSED,
            note: `Tự đóng sau ${AUTO_CLOSE_DAYS} ngày không nghiệm thu`,
          },
        ],
        { session }
      );
      return d;
    });
    if (!doc) continue;
    closed += 1;
    await notifyUsers({
      userIds: [doc.createdBy, doc.assignedStaffId],
      type: 'service_request_auto_closed',
      title: `Phiếu ${doc.requestCode} đã tự đóng`,
      body: `Quá ${AUTO_CLOSE_DAYS} ngày không nghiệm thu`,
      link: { kind: 'service_request', id: String(doc._id) },
    });
  }
  return closed;
}

module.exports = {
  TRANSITIONS,
  AUTO_CLOSE_DAYS,
  allowedActions,
  computeOverdue,
  withOverdue,
  createRequest,
  listMine,
  listForManager,
  getDetail,
  transition,
  autoCloseExpired,
};
