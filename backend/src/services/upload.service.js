const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');
const env = require('../config/env');
const { AppError, ERROR_CODES } = require('../utils/errors');

/**
 * Lưu ảnh ra thư mục env.uploadDir, trả về đường dẫn công khai '/uploads/<folder>/<tên>'.
 * Bọc riêng để sau này đổi sang cloud (S3, Cloudinary) chỉ phải sửa file này.
 */

// Chữ ký (magic bytes) thật của file, không tin mimetype client gửi
const SIGNATURES = [
  { ext: 'jpg', bytes: [0xff, 0xd8, 0xff] },
  { ext: 'png', bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] },
];

function detectImageExt(buffer) {
  const sig = SIGNATURES.find((s) => s.bytes.every((b, i) => buffer[i] === b));
  return sig ? sig.ext : null;
}

/**
 * Kiểm tra toàn bộ rồi mới ghi, để không để lại file rác khi một ảnh sai.
 * folder: 'service-requests', 'vehicles'... (chỉ chữ thường, số, gạch ngang).
 */
async function saveImages(files = [], folder) {
  if (!/^[a-z0-9-]+$/.test(folder)) throw new Error(`Thư mục upload không hợp lệ: ${folder}`);
  const prepared = files.map((f) => {
    const ext = detectImageExt(f.buffer);
    if (!ext) throw new AppError(ERROR_CODES.INVALID_FILE, 'Chỉ chấp nhận ảnh JPEG hoặc PNG');
    // Tên ngẫu nhiên, không dùng tên file gốc
    return { name: `${crypto.randomUUID()}.${ext}`, buffer: f.buffer };
  });
  if (!prepared.length) return [];

  const dir = path.join(env.uploadDir, folder);
  await fs.mkdir(dir, { recursive: true });
  await Promise.all(prepared.map((p) => fs.writeFile(path.join(dir, p.name), p.buffer)));
  return prepared.map((p) => `/uploads/${folder}/${p.name}`);
}

/** Xóa ảnh đã lưu (dùng khi nghiệp vụ sau đó thất bại). Lỗi chỉ ghi log. */
async function removeImages(urls = []) {
  await Promise.all(
    urls.map(async (url) => {
      const rel = url.replace(/^\/uploads\//, '');
      const file = path.resolve(env.uploadDir, rel);
      if (!file.startsWith(path.resolve(env.uploadDir))) return;
      await fs.unlink(file).catch((err) => console.error('[removeImages]', err.message));
    })
  );
}

module.exports = { saveImages, removeImages, detectImageExt };
