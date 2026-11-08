const app = require('./app');
const env = require('./config/env');
const { connectDb } = require('./config/db');

(async () => {
  try {
    await connectDb();
    console.log('MongoDB connected');
    // Job nền của module vận hành (Người 2)
    require('./jobs').startJobs();
    app.listen(env.port, () => console.log(`API listening on http://localhost:${env.port}/api`));
  } catch (err) {
    console.error('Không kết nối được MongoDB:', err.message);
    process.exit(1);
  }
})();
