const ServiceRequest = require('../models/ServiceRequest');
const OperationalTask = require('../models/OperationalTask');
const requestService = require('./serviceRequest.service');
const taskService = require('./operationalTask.service');
const {
  REQUEST_STATUS: S,
  TASK_STATUS: T,
  OPEN_REQUEST_STATUSES,
  OPEN_TASK_STATUSES,
} = require('../utils/constants');

/**
 * UC-31: Việc của tôi (Staff) = phiếu M5 + nhiệm vụ M7 trong một danh sách,
 * mỗi mục có `kind: 'request' | 'task'`. Xem kế hoạch mục 9.1 "Gộp UC-31".
 */

const TABS = {
  active: () => ({
    request: { status: { $in: [...OPEN_REQUEST_STATUSES] } },
    task: { status: { $in: [...OPEN_TASK_STATUSES] } },
  }),
  overdue: () => {
    const late = { deadline: { $lt: new Date() } };
    return {
      request: { status: { $in: [...OPEN_REQUEST_STATUSES] }, ...late },
      task: { status: { $in: [...OPEN_TASK_STATUSES] }, ...late },
    };
  },
  done: () => ({
    request: { status: { $in: [S.WAITING_CONFIRMATION, S.CLOSED] } },
    task: { status: T.COMPLETED },
  }),
};

// Đang làm / quá hạn: hạn gần nhất lên trước, cùng hạn thì ưu tiên cao trước. Đã xong: mới nhất trước.
function compare(tab) {
  if (tab === 'done') return (a, b) => b.doc.updatedAt - a.doc.updatedAt;
  const time = (d) => (d.deadline ? d.deadline.getTime() : Number.MAX_SAFE_INTEGER);
  return (a, b) => time(a.doc) - time(b.doc) || a.doc.priorityRank - b.doc.priorityRank;
}

async function listAssignments(actor, { page, limit, tab }) {
  const filters = TABS[tab]();
  const mine = { assignedStaffId: actor._id };
  // Lấy đủ page*limit mục đầu của mỗi loại rồi trộn: đúng thứ tự cho mọi trang
  const take = page * limit;
  const sort = tab === 'done' ? { updatedAt: -1 } : { deadline: 1, priorityRank: 1 };
  const [requests, tasks, requestTotal, taskTotal] = await Promise.all([
    ServiceRequest.find({ ...mine, ...filters.request })
      .populate('apartmentId', 'code floor')
      .sort(sort)
      .limit(take),
    OperationalTask.find({ ...mine, ...filters.task }).sort(sort).limit(take),
    ServiceRequest.countDocuments({ ...mine, ...filters.request }),
    OperationalTask.countDocuments({ ...mine, ...filters.task }),
  ]);

  const merged = [
    ...requests.map((doc) => ({ doc, kind: 'request', toItem: requestService.withOverdue })),
    ...tasks.map((doc) => ({ doc, kind: 'task', toItem: taskService.withOverdue })),
  ].sort(compare(tab));

  const items = merged
    .slice((page - 1) * limit, page * limit)
    .map(({ doc, kind, toItem }) => ({ kind, ...toItem(doc) }));
  const total = requestTotal + taskTotal;
  return { items, meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
}

module.exports = { listAssignments };
