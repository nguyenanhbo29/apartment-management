const { AppError, ERROR_CODES } = require('../utils/errors');

// validate({ body: zodSchema, query: zodSchema, params: zodSchema })
// Dữ liệu đã parse nằm ở req.validated.{body|query|params}
const validate = (schemas) => (req, _res, next) => {
  for (const key of ['body', 'query', 'params']) {
    if (!schemas[key]) continue;
    const result = schemas[key].safeParse(req[key]);
    if (!result.success) {
      const details = result.error.issues.map((i) => ({
        field: i.path.join('.'),
        message: i.message,
      }));
      throw new AppError(ERROR_CODES.VALIDATION_ERROR, 'Dữ liệu không hợp lệ', details);
    }
    req.validated = { ...(req.validated || {}), [key]: result.data };
  }
  next();
};

module.exports = { validate };
