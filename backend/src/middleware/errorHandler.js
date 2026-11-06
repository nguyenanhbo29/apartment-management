const { ERROR_CODES } = require('../utils/errors');

function notFoundHandler(req, res) {
  res.status(404).json({
    success: false,
    error: {
      code: ERROR_CODES.NOT_FOUND.code,
      message: `Không tìm thấy ${req.method} ${req.originalUrl}`,
    },
  });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, _req, res, _next) {
  if (err.isAppError) {
    return res.status(err.status).json({
      success: false,
      error: { code: err.code, message: err.message, ...(err.details && { details: err.details }) },
    });
  }
  if (err.code === 11000) {
    const field = Object.keys(err.keyPattern || {})[0] || 'field';
    return res.status(409).json({
      success: false,
      error: { code: ERROR_CODES.CONFLICT.code, message: `Giá trị "${field}" đã tồn tại` },
    });
  }
  if (err.name === 'CastError') {
    return res.status(400).json({
      success: false,
      error: { code: ERROR_CODES.BAD_REQUEST.code, message: 'ID không hợp lệ' },
    });
  }
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({
      success: false,
      error: { code: ERROR_CODES.BAD_REQUEST.code, message: 'JSON không hợp lệ' },
    });
  }
  console.error(err);
  res.status(500).json({
    success: false,
    error: { code: ERROR_CODES.INTERNAL.code, message: 'Lỗi hệ thống' },
  });
}

module.exports = { notFoundHandler, errorHandler };
