const mongoose = require('mongoose');
const { connectDb } = require('../src/config/db');
const User = require('../src/models/User');
const { signToken } = require('../src/middleware/auth');

async function setupDb() {
  await connectDb();
  await mongoose.connection.dropDatabase();
  await Promise.all(Object.values(mongoose.models).map((m) => m.init()));
}

async function teardownDb() {
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
}

let seq = 0;
async function createUser(overrides = {}) {
  seq += 1;
  const { password = 'Passw0rd!', ...rest } = overrides;
  const user = await User.create({
    email: `user${seq}@test.local`,
    fullName: `User ${seq}`,
    role: 'resident',
    passwordHash: await User.hashPassword(password),
    ...rest,
  });
  return { user, token: signToken(user), password };
}

const bearer = (token) => ({ Authorization: `Bearer ${token}` });

module.exports = { setupDb, teardownDb, createUser, bearer };
