const mongoose = require('mongoose');
const { connectDb } = require('../config/db');
const User = require('../models/User');

(async () => {
  await connectDb();
  const email = process.env.SEED_MANAGER_EMAIL || 'manager@apartment.local';
  const password = process.env.SEED_MANAGER_PASSWORD || 'Manager@123';
  const existing = await User.findOne({ email });
  if (existing) {
    console.log(`Manager đã tồn tại: ${email}`);
  } else {
    await User.create({
      email,
      passwordHash: await User.hashPassword(password),
      fullName: 'Quản lý hệ thống',
      role: 'manager',
    });
    console.log(`Đã tạo Manager: ${email} / ${password}`);
  }
  await mongoose.disconnect();
})();
