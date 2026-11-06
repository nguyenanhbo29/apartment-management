const app = require('./app');
const env = require('./config/env');
const { connectDb } = require('./config/db');

(async () => {
  try {
    await connectDb();
    console.log('MongoDB connected');
    app.listen(env.port, () => console.log(`API listening on http://localhost:${env.port}/api`));
  } catch (err) {
    console.error('Không kết nối được MongoDB:', err.message);
    process.exit(1);
  }
})();
