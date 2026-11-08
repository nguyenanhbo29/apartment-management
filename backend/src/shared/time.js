const { DateTime } = require('luxon');

/**
 * DB lưu UTC, nghiệp vụ (ngày, khung giờ, hạn hủy) tính theo giờ Việt Nam.
 * Không dùng new Date('2026-11-06') để so ngày: sẽ lệch 7 tiếng.
 */
const TZ = 'Asia/Ho_Chi_Minh';

const nowVN = () => DateTime.now().setZone(TZ);
const toVN = (date) => DateTime.fromJSDate(date).setZone(TZ);

/** 'YYYY-MM-DD' theo giờ VN -> DateTime đầu ngày. Sai định dạng trả null. */
function parseDateVN(dateStr) {
  const dt = DateTime.fromISO(dateStr, { zone: TZ });
  return dt.isValid ? dt.startOf('day') : null;
}

/** Khoảng [start, end) của một ngày VN dưới dạng Date, dùng trong query Mongo. */
function dayRangeVN(dateStr) {
  const start = dateStr ? parseDateVN(dateStr) : nowVN().startOf('day');
  if (!start) return null;
  return { start: start.toJSDate(), end: start.plus({ days: 1 }).toJSDate() };
}

/** Ghép ngày VN với giờ 'HH:mm' -> Date. Ví dụ ('2026-11-10', '06:30'). */
function combineVN(dateStr, hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  const day = parseDateVN(dateStr);
  return day ? day.set({ hour: h, minute: m }).toJSDate() : null;
}

/** 'YYYY-MM-DD' (giờ VN) của một Date. */
const dateKeyVN = (date) => toVN(date).toISODate();

const isSameDayVN = (a, b) => dateKeyVN(a) === dateKeyVN(b);

/** 'HH:mm' -> số phút từ 0h. */
function minutesOf(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

module.exports = {
  TZ,
  nowVN,
  toVN,
  parseDateVN,
  dayRangeVN,
  combineVN,
  dateKeyVN,
  isSameDayVN,
  minutesOf,
};
