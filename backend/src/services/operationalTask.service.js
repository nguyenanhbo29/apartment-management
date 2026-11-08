const OperationalTask = require('../models/OperationalTask');
const RequestHistory = require('../models/RequestHistory');
const { PRIORITY_RANK } = require('../models/ServiceRequest');
const { AppError, ERROR_CODES } = require('../utils/errors');
const { ROLES, TASK_STATUS: T, OPEN_TASK_STATUSES } = require('../utils/constants');
const { assertAssignable } = require('../shared/assignee');
const { createWithCode } = require('../shared/code');
const { withTransaction } = require('../shared/transaction');
const { dayRangeVN } = require('../shared/time');
const { saveImages, removeImages } = require('./upload.service');
const { notifyUsers } = require('./notify.service');

/**
 * M7 — Nhiệm vụ vận hành (UC-41, 42). Xem docs/ke-hoach-nguoi-2.md mục 9.1.
 * Cùng mẫu với phiếu M5: bảng chuyển trạng thái, update có điều kiện + lịch sử trong transaction.
 */

const UPLOAD_FOLDER = 'tasks';
const sameId = (a, b) => a != null && b != null && String(a) === String(b);
const isManager = (u) => u.role === ROLES.MANAGER;
const isAssignee = (u, t) => u.role === ROLES.STAFF && sameId(t.assignedStaffId, u._id);

const TRANSITIONS = Object.freeze({
  reassign: { from: [T.ASSIGNED, T.IN_PROGRESS], to: T.ASSIGNED, can: isManager },
  cancel: { from: [T.ASSIGNED, T.IN_PROGRESS], to: T.CANCELLED, can: isManager },
  start: { from: [T.ASSIGNED], to: T.IN_PROGRESS, can: isAssignee },
  complete: { from: [T.IN_PROGRESS], to: T.COMPLETED, can: isAssignee },
});

const allowedActions = (actor, t) =>
  Object.entries(TRANSITIONS)
    .filter(([, rule]) => rule.from.includes(t.status) && rule.can(actor, t))
    .map(([action]) => action);

const computeOverdue = (t, now = new Date()) =>
  Boolean(t.deadline && OPEN_TASK_STATUSES.includes(t.status) && t.deadline < now);

const withOverdue = (doc) => {
  const o = typeof doc.toJSON === 'function' ? doc.toJSON() : doc;
  return { ...o, isOverdue: computeOverdue(o) };
};

const paged = (page, limit, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit) });
const POPULATE = [
  { path: 'assignedStaffId', select: 'fullName phone department' },
  { path: 'createdBy', select: 'fullName' },
];
const link = (t) => ({ kind: 'task', id: String(t._id) });

/** Manager xem mọi nhiệm vụ; Staff chỉ nhiệm vụ đang giao cho mình. Ngoài phạm vi: 404. */
async function findVisibleOrThrow(actor, id) {
  let scope = null;
  if (isManager(actor)) scope = {};
  else if (actor.role === ROLES.STAFF) scope = { assignedStaffId: actor._id };
  const task = scope && (await OperationalTask.findOne({ _id: id, ...scope }));
  if (!task) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy nhiệm vụ');
  return task;
}

const assertFuture = (deadline, now) => {
  if (!deadline || deadline <= now) {
    throw new AppError(ERROR_CODES.BAD_REQUEST, 'Hạn hoàn thành phải ở tương lai');
  }
};

// ---------------------------------------------------------------- UC-41: tạo + giao
async function create(actor, data) {
  const now = new Date();
  const staff = await assertAssignable(data.staffId, data.department);
  assertFuture(data.deadline, now);
  const { staffId, ...rest } = data;
  const task = await withTransaction(async (session) => {
    const doc = await createWithCode(
      OperationalTask,
      'taskCode',
      'TK-',
      {
        ...rest,
        priorityRank: PRIORITY_RANK[data.priority || 'normal'],
        assignedStaffId: staff._id,
        assignedAt: now,
        createdBy: actor._id,
        status: T.ASSIGNED,
      },
      { session }
    );
    await RequestHistory.create(
      [
        {
          taskId: doc._id,
          updatedBy: actor._id,
          action: 'created',
          newStatus: T.ASSIGNED,
          assignedStaffId: staff._id,
          deadline: data.deadline,
        },
      ],
      { session }
    );
    return doc;
  });

  await notifyUsers({
    userIds: [staff._id],
    type: 'task_assigned',
    title: `Nhiệm vụ mới ${task.taskCode}`,
    body: task.title,
    link: link(task),
  });
  return withOverdue(task);
}

// ---------------------------------------------------------------- UC-41, 42: danh sách / lịch sử
/**
 * Manager: mọi nhiệm vụ, lọc theo nhân viên. Staff: luôn chỉ của mình (bỏ qua staffId truyền lên).
 * from/to (YYYY-MM-DD, giờ VN) lọc theo ngày tạo.
 */
async function list(actor, { page, limit, status, department, staffId, overdue, from, to }) {
  const filter = {};
  if (actor.role === ROLES.STAFF) filter.assignedStaffId = actor._id;
  else if (staffId) filter.assignedStaffId = staffId;
  if (status) filter.status = status;
  if (department) filter.department = department;
  if (overdue) {
    filter.status = { $in: [...OPEN_TASK_STATUSES] };
    filter.deadline = { $lt: new Date() };
  }
  if (from || to) {
    const start = from && dayRangeVN(from);
    const end = to && dayRangeVN(to);
    if ((from && !start) || (to && !end)) {
      throw new AppError(ERROR_CODES.BAD_REQUEST, 'Ngày không hợp lệ (YYYY-MM-DD)');
    }
    filter.createdAt = { ...(start && { $gte: start.start }), ...(end && { $lt: end.end }) };
  }
  const [items, total] = await Promise.all([
    OperationalTask.find(filter)
      .populate(POPULATE)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    OperationalTask.countDocuments(filter),
  ]);
  return { items: items.map(withOverdue), meta: paged(page, limit, total) };
}

async function getDetail(actor, id) {
  const task = await findVisibleOrThrow(actor, id);
  const actions = allowedActions(actor, task);
  await task.populate(POPULATE);
  const timeline = await RequestHistory.find({ taskId: task._id })
    .populate('updatedBy', 'fullName role')
    .populate('assignedStaffId', 'fullName')
    .sort({ createdAt: 1 });
  return { ...withOverdue(task), timeline, allowedActions: actions };
}

// ---------------------------------------------------------------- Đổi trạng thái
async function buildChanges(action, task, input, now) {
  switch (action) {
    case 'reassign': {
      const staff = await assertAssignable(input.staffId, input.department);
      if (sameId(staff._id, task.assignedStaffId)) {
        throw new AppError(ERROR_CODES.BAD_REQUEST, 'Nhân viên mới phải khác nhân viên hiện tại');
      }
      const deadline = input.deadline || task.deadline;
      assertFuture(deadline, now);
      return {
        set: {
          department: input.department,
          assignedStaffId: staff._id,
          assignedAt: now,
          deadline,
          startedAt: null,
        },
        note: input.note,
        assignedStaffId: staff._id,
        deadline,
        previousStaffId: task.assignedStaffId,
      };
    }
    case 'cancel':
      return { set: { cancelReason: input.reason, cancelledAt: now }, note: input.reason };
    case 'start':
      return { set: { startedAt: now } };
    case 'complete':
      return {
        set: { completedAt: now, completionNote: input.note, resultImages: input.images },
        note: input.note,
        attachments: input.images,
      };
    default:
      throw new Error(`Hành động không hỗ trợ: ${action}`);
  }
}

async function transition(actor, id, action, input = {}, files = []) {
  const rule = TRANSITIONS[action];
  const task = await findVisibleOrThrow(actor, id);
  if (!rule.can(actor, task)) {
    throw new AppError(ERROR_CODES.FORBIDDEN, 'Bạn không có quyền thao tác nhiệm vụ này');
  }
  if (!rule.from.includes(task.status)) {
    throw new AppError(ERROR_CODES.INVALID_STATE, 'Nhiệm vụ đã thay đổi trạng thái, vui lòng tải lại');
  }

  const now = new Date();
  const images = action === 'complete' ? await saveImages(files, UPLOAD_FOLDER) : [];
  let updated;
  let changes;
  try {
    changes = await buildChanges(action, task, { ...input, images }, now);
    updated = await withTransaction(async (session) => {
      const doc = await OperationalTask.findOneAndUpdate(
        { _id: task._id, status: { $in: rule.from } },
        { $set: { status: rule.to, ...changes.set } },
        { new: true, session }
      );
      if (!doc) {
        throw new AppError(ERROR_CODES.INVALID_STATE, 'Nhiệm vụ đã thay đổi trạng thái, vui lòng tải lại');
      }
      await RequestHistory.create(
        [
          {
            taskId: doc._id,
            updatedBy: actor._id,
            action,
            previousStatus: task.status,
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

  await notifyForTransition(action, updated, changes);
  return withOverdue(updated);
}

async function notifyForTransition(action, t, changes) {
  const send = (userIds, type, title, body = t.title) =>
    notifyUsers({ userIds, type, title, body, link: link(t) });
  if (action === 'reassign') {
    await send([t.assignedStaffId], 'task_assigned', `Nhiệm vụ mới ${t.taskCode}`);
    await send([changes.previousStaffId], 'task_unassigned', `Nhiệm vụ ${t.taskCode} đã chuyển cho người khác`);
  } else if (action === 'cancel') {
    await send([t.assignedStaffId], 'task_cancelled', `Nhiệm vụ ${t.taskCode} đã hủy`, `Lý do: ${t.cancelReason}`);
  } else if (action === 'complete') {
    await send([t.createdBy], 'task_completed', `Nhiệm vụ ${t.taskCode} đã hoàn thành`);
  }
}

module.exports = {
  TRANSITIONS,
  allowedActions,
  computeOverdue,
  withOverdue,
  create,
  list,
  getDetail,
  transition,
};
