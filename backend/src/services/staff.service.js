const User = require('../models/User');
const { optionalModel } = require('../shared/optionalModel');
const {
  ROLES,
  DEPARTMENTS,
  USER_STATUS,
  OPEN_REQUEST_STATUSES,
  OPEN_TASK_STATUSES,
} = require('../utils/constants');

/**
 * UC-40 (bản rút gọn, đã chốt 2026-11-08): bộ phận là enum trên User.department,
 * không có collection Departments. Thêm/sửa/khóa nhân viên dùng API /users của Người 1.
 */

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Đếm việc đang mở theo nhân viên: Map(staffId -> số lượng). Model chưa có thì rỗng. */
async function countOpenBy(modelName, statuses, staffIds) {
  const Model = optionalModel(modelName);
  if (!Model || !staffIds.length) return new Map();
  const rows = await Model.aggregate([
    { $match: { assignedStaffId: { $in: staffIds }, status: { $in: [...statuses] } } },
    { $group: { _id: '$assignedStaffId', count: { $sum: 1 } } },
  ]);
  return new Map(rows.map((r) => [String(r._id), r.count]));
}

/** Danh sách Staff kèm số phiếu và nhiệm vụ đang mở để Manager cân tải khi phân công. */
async function listStaff({ page, limit, department, status, q }) {
  const filter = { role: ROLES.STAFF };
  if (department) filter.department = department;
  if (status) filter.status = status;
  if (q) {
    const rx = new RegExp(escapeRegex(q), 'i');
    filter.$or = [{ fullName: rx }, { email: rx }, { phone: rx }];
  }
  const [users, total] = await Promise.all([
    User.find(filter)
      .sort({ department: 1, fullName: 1 })
      .skip((page - 1) * limit)
      .limit(limit),
    User.countDocuments(filter),
  ]);

  const ids = users.map((u) => u._id);
  const [requests, tasks] = await Promise.all([
    countOpenBy('ServiceRequest', OPEN_REQUEST_STATUSES, ids),
    countOpenBy('OperationalTask', OPEN_TASK_STATUSES, ids),
  ]);
  const items = users.map((u) => {
    const openRequests = requests.get(String(u._id)) || 0;
    const openTasks = tasks.get(String(u._id)) || 0;
    return { ...u.toJSON(), openRequests, openTasks, openWork: openRequests + openTasks };
  });
  return { items, meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
}

/** Các bộ phận (cố định) kèm số nhân viên đang hoạt động / tổng. */
async function listDepartments() {
  const rows = await User.aggregate([
    { $match: { role: ROLES.STAFF } },
    {
      $group: {
        _id: '$department',
        total: { $sum: 1 },
        active: { $sum: { $cond: [{ $eq: ['$status', USER_STATUS.ACTIVE] }, 1, 0] } },
      },
    },
  ]);
  const byCode = new Map(rows.map((r) => [r._id, r]));
  return Object.values(DEPARTMENTS).map((code) => ({
    code,
    activeStaff: byCode.get(code)?.active ?? 0,
    totalStaff: byCode.get(code)?.total ?? 0,
  }));
}

module.exports = { listStaff, listDepartments };
