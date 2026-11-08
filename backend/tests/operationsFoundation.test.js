const fs = require('fs');
const path = require('path');
const express = require('express');
const mongoose = require('mongoose');
const request = require('supertest');
const env = require('../src/config/env');
const { generateCode, createWithCode, CODE_ALPHABET } = require('../src/shared/code');
const { dayRangeVN, combineVN, dateKeyVN, isSameDayVN, minutesOf } = require('../src/shared/time');
const { withTransaction } = require('../src/shared/transaction');
const { uploadImages } = require('../src/middleware/upload');
const { saveImages } = require('../src/services/upload.service');
const { errorHandler } = require('../src/middleware/errorHandler');
const { setupDb, teardownDb } = require('./helpers');

beforeAll(setupDb);
afterAll(teardownDb);

describe('shared/code', () => {
  test('đúng tiền tố, 6 ký tự trong bảng chữ cái, không có ký tự dễ nhầm', () => {
    for (let i = 0; i < 200; i += 1) {
      const code = generateCode('SR-');
      expect(code).toMatch(/^SR-[A-Z2-9]{6}$/);
      [...code.slice(3)].forEach((ch) => expect(CODE_ALPHABET).toContain(ch));
      expect(code.slice(3)).not.toMatch(/[01OIL]/);
    }
  });

  test('createWithCode sinh lại khi trùng mã', async () => {
    const Probe = mongoose.model(
      'CodeProbe',
      new mongoose.Schema({ code: { type: String, unique: true }, n: Number })
    );
    await Probe.init();
    const spy = jest.spyOn(require('crypto'), 'randomInt').mockReturnValue(0); // luôn ra 'AAAAAA'
    await createWithCode(Probe, 'code', 'X-', { n: 1 });
    // Lần 2: 2 lần đầu trùng 'X-AAAAAA', lần 3 đổi sang ký tự khác
    let calls = 0;
    spy.mockImplementation(() => (calls++ < 12 ? 0 : 1));
    const doc = await createWithCode(Probe, 'code', 'X-', { n: 2 });
    spy.mockRestore();
    expect(doc.code).not.toBe('X-AAAAAA');
    expect(await Probe.countDocuments()).toBe(2);
  });
});

describe('shared/time (giờ Việt Nam)', () => {
  test('ngày VN bắt đầu lúc 17:00 UTC hôm trước', () => {
    const { start, end } = dayRangeVN('2026-11-10');
    expect(start.toISOString()).toBe('2026-11-09T17:00:00.000Z');
    expect(end.toISOString()).toBe('2026-11-10T17:00:00.000Z');
  });

  test('ghép ngày + giờ theo VN; 23:30 VN vẫn là cùng ngày VN dù UTC đã khác ngày', () => {
    expect(combineVN('2026-11-10', '06:30').toISOString()).toBe('2026-11-09T23:30:00.000Z');
    const lateNight = combineVN('2026-11-10', '23:30');
    expect(dateKeyVN(lateNight)).toBe('2026-11-10');
    expect(isSameDayVN(lateNight, combineVN('2026-11-10', '00:10'))).toBe(true);
  });

  test('sai định dạng trả null; minutesOf', () => {
    expect(dayRangeVN('10/11/2026')).toBeNull();
    expect(minutesOf('06:30')).toBe(390);
  });
});

describe('shared/transaction', () => {
  test('lỗi thì rollback, thành công thì trả kết quả', async () => {
    const col = mongoose.connection.db.collection('tx_shared');
    await expect(
      withTransaction(async (session) => {
        await col.insertOne({ a: 1 }, { session });
        throw new Error('boom');
      })
    ).rejects.toThrow('boom');
    expect(await col.countDocuments()).toBe(0);

    const out = await withTransaction(async (session) => {
      await col.insertOne({ a: 2 }, { session });
      return 'ok';
    });
    expect(out).toBe('ok');
    expect(await col.countDocuments()).toBe(1);
  });
});

describe('upload ảnh', () => {
  const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
  const JPG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
  const FAKE = Buffer.from('<?php echo 1; ?>');

  const app = express();
  app.post('/up', uploadImages('images', 2), async (req, res) => {
    res.json({ urls: await saveImages(req.files, 'test-uploads') });
  });
  app.use(errorHandler);

  test('lưu JPEG/PNG với tên ngẫu nhiên, trả đường dẫn /uploads', async () => {
    const res = await request(app)
      .post('/up')
      .attach('images', PNG, { filename: 'a.png', contentType: 'image/png' })
      .attach('images', JPG, { filename: 'mat-khau.jpg', contentType: 'image/jpeg' });
    expect(res.status).toBe(200);
    expect(res.body.urls).toHaveLength(2);
    res.body.urls.forEach((u) => {
      expect(u).toMatch(/^\/uploads\/test-uploads\/[0-9a-f-]{36}\.(png|jpg)$/);
      expect(u).not.toContain('mat-khau');
      expect(fs.existsSync(path.join(env.uploadDir, u.replace('/uploads/', '')))).toBe(true);
    });
  });

  test('khai mimetype ảnh nhưng nội dung không phải ảnh: từ chối', async () => {
    const res = await request(app)
      .post('/up')
      .attach('images', FAKE, { filename: 'x.png', contentType: 'image/png' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_FILE');
  });

  test('vượt số ảnh cho phép: 400 INVALID_FILE', async () => {
    const res = await request(app)
      .post('/up')
      .attach('images', PNG, { filename: '1.png', contentType: 'image/png' })
      .attach('images', PNG, { filename: '2.png', contentType: 'image/png' })
      .attach('images', PNG, { filename: '3.png', contentType: 'image/png' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_FILE');
  });
});
