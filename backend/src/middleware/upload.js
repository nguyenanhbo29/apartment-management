const multer = require('multer');
const { AppError, ERROR_CODES } = require('../utils/errors');

const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5 MB/ảnh
const ALLOWED_MIME = ['image/jpeg', 'image/png'];

// Giữ file trong RAM; upload.service kiểm tra chữ ký file thật rồi mới ghi đĩa
const multerImages = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_SIZE },
  fileFilter: (_req, file, cb) => cb(null, ALLOWED_MIME.includes(file.mimetype)),
});

const MULTER_MESSAGES = {
  LIMIT_FILE_SIZE: 'Mỗi ảnh tối đa 5 MB',
  LIMIT_FILE_COUNT: 'Vượt quá số ảnh cho phép',
  LIMIT_UNEXPECTED_FILE: 'Vượt quá số ảnh cho phép hoặc sai tên trường ảnh',
};

/**
 * Nhận tối đa `max` ảnh JPEG/PNG ở trường `field` (multipart/form-data).
 * File nằm ở req.files (buffer), các trường text ở req.body (đều là chuỗi,
 * validator dùng z.coerce cho số/ngày). File sai định dạng bị bỏ qua ở bước này
 * và bị từ chối ở upload.service khi kiểm tra chữ ký.
 *   router.post('/', resident, uploadImages('images', 5), validate({ body }), ctrl.create)
 */
const uploadImages = (field, max) => (req, res, next) => {
  multerImages.array(field, max)(req, res, (err) => {
    if (!err) return next();
    if (err instanceof multer.MulterError) {
      return next(new AppError(ERROR_CODES.INVALID_FILE, MULTER_MESSAGES[err.code] || err.message));
    }
    return next(err);
  });
};

module.exports = { uploadImages, MAX_FILE_SIZE, ALLOWED_MIME };
