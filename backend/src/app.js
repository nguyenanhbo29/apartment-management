const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const env = require('./config/env');
const routes = require('./routes');
const { notFoundHandler, errorHandler } = require('./middleware/errorHandler');

const app = express();
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '1mb' }));
if (process.env.NODE_ENV !== 'test') app.use(morgan('dev'));

// Ảnh upload (Người 2). helmet mặc định chặn tải ảnh từ origin khác (Flutter web) nên mở CORP.
app.use(
  '/uploads',
  express.static(env.uploadDir, {
    setHeaders: (res) => res.set('Cross-Origin-Resource-Policy', 'cross-origin'),
  })
);

app.use('/api', routes);
app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
