const mongoose = require('mongoose');
const { connectDb } = require('../config/db');
const User = require('../models/User');
const Apartment = require('../models/Apartment');
const ApartmentResident = require('../models/ApartmentResident');
const apartmentService = require('../services/apartment.service');
const Amenity = require('../models/Amenity');

/**
 * Dữ liệu demo. Chạy lại nhiều lần không tạo trùng (tìm theo email / mã căn hộ).
 *   npm run seed
 * Manager: SEED_MANAGER_EMAIL / SEED_MANAGER_PASSWORD (mặc định manager@apartment.local / Manager@123)
 * Tài khoản khác: mật khẩu chung SEED_DEMO_PASSWORD (mặc định Demo@123)
 */
const DEMO_PASSWORD = process.env.SEED_DEMO_PASSWORD || 'Demo@123';

const USERS = [
  {
    email: process.env.SEED_MANAGER_EMAIL || 'manager@apartment.local',
    password: process.env.SEED_MANAGER_PASSWORD || 'Manager@123',
    fullName: 'Quản lý hệ thống',
    role: 'manager',
  },
  { email: 'accountant@apartment.local', fullName: 'Kế toán Trần Thu', role: 'accountant' },
  // Staff: mỗi bộ phận ít nhất 1 người; Technical 2 người để demo chuyển người xử lý
  { email: 'reception@apartment.local', fullName: 'Lễ tân Lê Mai', role: 'staff', department: 'reception' },
  { email: 'security@apartment.local', fullName: 'Bảo vệ Phạm Hùng', role: 'staff', department: 'security' },
  { email: 'technical@apartment.local', fullName: 'Kỹ thuật Ngô Nam', role: 'staff', department: 'technical' },
  { email: 'technical2@apartment.local', fullName: 'Kỹ thuật Đỗ Long', role: 'staff', department: 'technical' },
  { email: 'facility@apartment.local', fullName: 'Tiện ích Vũ Lan', role: 'staff', department: 'facility' },
  // Cư dân
  { email: 'resident1@apartment.local', fullName: 'Nguyễn Văn An', role: 'resident', phone: '0901000001' },
  { email: 'resident2@apartment.local', fullName: 'Nguyễn Thị Bình', role: 'resident', phone: '0901000002' },
  { email: 'resident3@apartment.local', fullName: 'Trần Minh Châu', role: 'resident', phone: '0901000003' },
  { email: 'resident4@apartment.local', fullName: 'Lê Quốc Dũng', role: 'resident', phone: '0901000004' },
];

const APARTMENTS = [
  { code: 'A-101', floor: 1, area: 72, bedrooms: 2 },
  { code: 'A-102', floor: 1, area: 65, bedrooms: 2 },
  { code: 'A-201', floor: 2, area: 85, bedrooms: 3 },
  { code: 'A-202', floor: 2, area: 55, bedrooms: 1 },
  { code: 'B-301', floor: 3, area: 100, bedrooms: 3 }, // để trống
];

// email = null: người cư trú không có tài khoản (trẻ em, người già)
const RESIDENCES = [
  { apt: 'A-101', email: 'resident1@apartment.local', relation: 'owner', isPayer: true },
  { apt: 'A-101', email: 'resident2@apartment.local', relation: 'member' },
  { apt: 'A-101', email: null, fullName: 'Nguyễn Gia Huy', relation: 'member', dateOfBirth: '2016-05-20' },
  { apt: 'A-201', email: 'resident3@apartment.local', relation: 'owner', isPayer: true },
  { apt: 'A-202', email: 'resident4@apartment.local', relation: 'tenant', isPayer: true },
  { apt: 'A-102', email: null, fullName: 'Hoàng Văn Em', relation: 'owner', isPayer: true },
];

async function seedUsers() {
  const byEmail = {};
  for (const { password = DEMO_PASSWORD, ...data } of USERS) {
    let user = await User.findOne({ email: data.email });
    if (!user) {
      user = await User.create({ ...data, passwordHash: await User.hashPassword(password) });
      console.log(`+ ${data.role.padEnd(10)} ${data.email} / ${password}`);
    }
    byEmail[data.email] = user;
  }
  return byEmail;
}

async function seedApartments() {
  const byCode = {};
  for (const data of APARTMENTS) {
    byCode[data.code] =
      (await Apartment.findOne({ buildingId: 'main', code: data.code })) ||
      (await Apartment.create(data));
  }
  return byCode;
}

async function seedResidences(users, apartments) {
  for (const r of RESIDENCES) {
    const apartment = apartments[r.apt];
    const user = r.email ? users[r.email] : null;
    const fullName = user ? user.fullName : r.fullName;
    const exists = await ApartmentResident.exists({
      apartmentId: apartment._id,
      status: 'active',
      ...(user ? { userId: user._id } : { fullName }),
    });
    if (exists) continue;
    await ApartmentResident.create({
      apartmentId: apartment._id,
      userId: user?._id,
      fullName,
      phone: user?.phone,
      dateOfBirth: r.dateOfBirth,
      relation: r.relation,
      isPayer: Boolean(r.isPayer),
      status: 'active',
      source: 'manager',
      moveInDate: new Date('2025-01-01'),
    });
    console.log(`+ cư trú     ${r.apt} ${fullName} (${r.relation})`);
  }
  await Promise.all(Object.values(apartments).map((a) => apartmentService.recomputeStatus(a._id)));
}

// M6: tiện ích mẫu (tìm theo tên)
const AMENITIES = [
  {
    name: 'Hồ bơi',
    location: 'Tầng 5, khối A',
    openTime: '06:00',
    closeTime: '21:00',
    slotDuration: 60,
    capacity: 20,
    rules: 'Mặc đồ bơi, tắm tráng trước khi xuống hồ. Trẻ em dưới 12 tuổi phải có người lớn đi kèm.',
  },
  {
    name: 'Phòng gym',
    location: 'Tầng 3, khối A',
    openTime: '05:00',
    closeTime: '22:00',
    slotDuration: 60,
    capacity: 15,
    rules: 'Mang khăn và giày thể thao. Lau dụng cụ sau khi dùng.',
  },
  {
    name: 'Khu BBQ',
    location: 'Sân thượng khối B',
    openTime: '16:00',
    closeTime: '22:00',
    slotDuration: 120,
    capacity: 1,
    requiresApproval: true,
    cancelDeadlineHours: 24,
    rules: 'Mỗi lượt một căn hộ. Dọn dẹp sau khi dùng, không gây ồn sau 22:00.',
  },
  {
    name: 'Phòng sinh hoạt cộng đồng',
    location: 'Tầng 1, khối B',
    openTime: '08:00',
    closeTime: '21:00',
    slotDuration: 120,
    capacity: 1,
    requiresApproval: true,
    cancelDeadlineHours: 12,
  },
];

async function seedAmenities(manager) {
  for (const data of AMENITIES) {
    if (await Amenity.exists({ name: data.name })) continue;
    await Amenity.create({ ...data, createdBy: manager?._id });
    console.log(`+ tiện ích   ${data.name}`);
  }
}

(async () => {
  await connectDb();
  const users = await seedUsers();
  const apartments = await seedApartments();
  await seedResidences(users, apartments);
  await seedAmenities(Object.values(users).find((u) => u.role === 'manager'));
  console.log('Seed xong.');
  await mongoose.disconnect();
})().catch(async (err) => {
  console.error('Seed lỗi:', err);
  await mongoose.disconnect();
  process.exit(1);
});
