# Backend – Apartment Management

Node.js + Express + MongoDB (Mongoose).

```bash
cd backend
cp .env.example .env     # chỉnh MONGODB_URI, JWT_SECRET
npm install
npm run seed             # tạo tài khoản Manager đầu tiên
npm run dev              # http://localhost:3000/api/health
npm test                 # dùng DB apartment_management_test
```

## Quy ước chung
- Cấu trúc: `routes -> controllers -> services -> models`.
- Response thành công: `{ success: true, data, meta? }`.
- Response lỗi: `{ success: false, error: { code, message, details? } }` (mã lỗi ở `src/utils/errors.js`).
- Xác thực: header `Authorization: Bearer <jwt>`; phân quyền bằng `authorize(roles, { departments })`.
- Validate input: `validate({ body, query, params })` với Zod, dữ liệu đã parse ở `req.validated`.
- Thông báo: `notifyUsers({ userIds, type, title, body, link })` trong `src/services/notify.service.js`.
