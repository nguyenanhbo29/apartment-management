# Backend – Apartment Management

Node.js + Express + MongoDB (Mongoose).

```bash
cd backend
cp .env.example .env     # chỉnh MONGODB_URI, JWT_SECRET
npm install
npm run seed             # tạo tài khoản Manager đầu tiên
npm run dev              # http://localhost:3000/api/health
npm test                 # tự bật MongoDB replica set tạm trong RAM (mongodb-memory-server)
```

Test không cần cài MongoDB: `tests/globalSetup.js` bật một replica set tạm (hỗ trợ transaction)
cho cả bộ test rồi tắt khi xong. Lần chạy đầu tải binary `mongod` (~100 MB) vào cache.
Muốn chạy trên Mongo thật thì đặt `MONGODB_TEST_URI` (Mongo đó phải là replica set nếu test có transaction).

## Quy ước chung
- Cấu trúc: `routes -> controllers -> services -> models`.
- Response thành công: `{ success: true, data, meta? }`.
- Response lỗi: `{ success: false, error: { code, message, details? } }` (mã lỗi ở `src/utils/errors.js`).
- Xác thực: header `Authorization: Bearer <jwt>`; phân quyền bằng `authorize(roles, { departments })`.
- Validate input: `validate({ body, query, params })` với Zod, dữ liệu đã parse ở `req.validated`.
- Thông báo: `notifyUsers({ userIds, type, title, body, link })` trong `src/services/notify.service.js`.
- Đổi/đặt lại mật khẩu tăng `tokenVersion` -> mọi JWT cũ bị vô hiệu.

## API M1 – Authentication & User
| Method | Path | Quyền | UC |
|---|---|---|---|
| POST | `/api/auth/login` | công khai | UC-01 |
| POST | `/api/auth/logout` | đã đăng nhập | UC-01 |
| POST | `/api/auth/forgot-password` | công khai | UC-02 |
| POST | `/api/auth/reset-password` | công khai | UC-02 |
| POST | `/api/auth/change-password` | đã đăng nhập | UC-01/03 |
| GET, PATCH | `/api/users/me` | đã đăng nhập | UC-03 |
| POST, GET | `/api/users` | manager | UC-04 |
| GET, PATCH | `/api/users/:id` | manager | UC-04 |
| PATCH | `/api/users/:id/status` | manager | UC-04 |
| PATCH | `/api/users/:id/role` | manager | UC-05 |
| POST | `/api/users/:id/reset-password` | manager | UC-04 |

## API M2 – Apartment & Resident
"Viewers" = Manager, Accountant, Staff bộ phận Lễ tân (reception).

| Method | Path | Quyền | UC |
|---|---|---|---|
| GET | `/api/apartments` | viewers | UC-06 |
| POST | `/api/apartments` | manager | UC-06 |
| GET | `/api/apartments/mine` | resident | UC-07 |
| GET | `/api/apartments/:id` | viewers, cư dân của căn | UC-07 |
| PATCH, DELETE | `/api/apartments/:id` | manager (chỉ xóa căn chưa có hồ sơ) | UC-06 |
| GET | `/api/apartments/:id/residents?status=active,pending` | viewers, cư dân của căn* | UC-12 |
| POST | `/api/apartments/:id/residents` | manager | UC-08 |
| POST | `/api/apartments/:id/registrations` | chủ hộ của căn | UC-09 |
| GET | `/api/residents?q=&status=` | viewers | UC-08 |
| GET | `/api/residents/:id` | viewers | UC-08 |
| PATCH | `/api/residents/:id` | manager | UC-08 |
| PATCH | `/api/residents/:id/payer` | manager | UC-08 |
| GET | `/api/residents/registrations?status=pending` | manager | UC-10 |
| PATCH | `/api/residents/:id/approve` | manager | UC-10 |
| PATCH | `/api/residents/:id/reject` | manager (bắt buộc `reason`) | UC-10 |
| PATCH | `/api/residents/:id/move-out` | manager | UC-11 |

\* Thành viên chỉ xem người đang ở (không thấy CCCD); chủ hộ xem thêm đơn chờ duyệt/bị từ chối.

Quy tắc: một chủ hộ active/căn (unique index); một người nộp phí/căn, mặc định là chủ hộ;
trạng thái căn tự cập nhật (occupied/vacant); chuyển đi = `ended`, không xóa hồ sơ/tài khoản.

## API M8 – Communication & Notifications
| Method | Path | Quyền | UC |
|---|---|---|---|
| POST | `/api/announcements` | manager | UC-43 |
| GET | `/api/announcements?includeInactive=` | mọi vai trò (lọc theo đối tượng) | UC-44 |
| GET | `/api/announcements/:id` | người thuộc đối tượng nhận, manager | UC-44 |
| PATCH | `/api/announcements/:id/pin` | manager | UC-43 |
| PATCH | `/api/announcements/:id/remove` | manager | UC-43 |
| GET | `/api/notifications?unreadOnly=` | của chính mình | UC-46 |
| GET | `/api/notifications/unread-count` | của chính mình | UC-45 |
| PATCH | `/api/notifications/:id/read` | của chính mình | UC-46 |
| PATCH | `/api/notifications/read-all` | của chính mình | UC-46 |

Đối tượng bảng tin: `{type:'all'}`, `{type:'roles', roles:[...]}`, `{type:'floors', floors:[...]}`,
`{type:'apartments', apartmentIds:[...]}`. Tầng/căn hộ chỉ gửi cư dân đang ở (status active).
Đăng tin sinh notification `type: 'announcement'` cho từng người nhận (trừ người đăng).
Tin đã đăng không sửa nội dung; chỉ ghim/bỏ ghim (tin ghim gần nhất lên đầu) hoặc gỡ.

Loại notification các module đang dùng (`link.kind` để app mở đúng màn hình):
| type | link.kind | Người nhận |
|---|---|---|
| `resident_registration_submitted` | `resident_registration` | Manager |
| `resident_registration_approved` | `apartment` | Chủ hộ khai báo |
| `resident_registration_rejected` | `apartment` | Chủ hộ khai báo |
| `announcement` | `announcement` | Đối tượng của tin |

`MAIL_MODE=console` (mặc định): OTP in ra console và trả trong `data.devOtp` để demo.
`MAIL_MODE=smtp`: gửi email thật, cần `SMTP_USER` + `SMTP_PASS` (Gmail App Password).
