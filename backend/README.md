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
| `service_request_created` | `service_request` | Manager |
| `service_request_rejected` | `service_request` | Người tạo phiếu |
| `service_request_accepted` | `service_request` | Người tạo phiếu (khi được phân công) |
| `service_request_assigned` | `service_request` | Nhân viên được giao |
| `service_request_unassigned` | `service_request` | Nhân viên cũ (khi chuyển người) |
| `service_request_started` | `service_request` | Người tạo phiếu |
| `service_request_waiting_confirmation` | `service_request` | Người tạo phiếu |
| `service_request_closed` | `service_request` | Nhân viên được giao |
| `service_request_reopened` | `service_request` | Nhân viên được giao, Manager |
| `service_request_auto_closed` | `service_request` | Người tạo phiếu, nhân viên được giao |
| `vehicle_submitted` | `vehicle` | Bảo vệ |
| `vehicle_approved` / `vehicle_rejected` | `vehicle` | Người đăng ký xe |
| `vehicle_deactivated` | `vehicle` | Người đăng ký xe (khi Manager ngừng xe) |
| `visitor_checked_in` / `visitor_checked_out` | `visitor` | Cư dân tạo lịch hẹn |
| `booking_submitted` | `amenity_booking` | Nhân viên Facility (tiện ích cần duyệt) |
| `booking_confirmed` / `booking_rejected` | `amenity_booking` | Người đặt (kể cả hết hạn duyệt) |
| `booking_cancelled_by_staff` | `amenity_booking` | Người đặt (ban quản lý hủy do sự cố) |
| `task_assigned` / `task_unassigned` / `task_cancelled` | `task` | Nhân viên được giao (mới / cũ) |
| `task_completed` | `task` | Manager tạo nhiệm vụ |

## API vận hành (Người 2)

Cần MongoDB **replica set** (transaction): test tự có; chạy app dùng Atlas hoặc Mongo local bật replica set.
Ảnh upload: multipart, trường `images`, tối đa 5 ảnh, 5 MB/ảnh, JPEG/PNG; phục vụ tại `/uploads/...`.

| Method | Path | Quyền | UC |
|---|---|---|---|
| GET | `/api/staff?department=&status=&q=` | manager (kèm `openRequests`, `openTasks`) | UC-40 |
| GET | `/api/staff/departments` | mọi vai trò | UC-40 |
| POST | `/api/service-requests` (multipart) | resident đang ở căn `apartmentId` | UC-27, 28 |
| GET | `/api/service-requests/mine?status=&type=` | resident | UC-29 |
| GET | `/api/service-requests?status=&priority=&type=&department=&overdue=` | manager (mặc định `pending`, `status=all`) | UC-30 |
| GET | `/api/service-requests/:id` | theo phạm vi*, kèm `timeline`, `allowedActions` | UC-29 |
| PATCH | `/api/service-requests/:id/reject` | manager (`reason`) | UC-30 |
| PATCH | `/api/service-requests/:id/assign` | manager (`department`, `staffId`, `deadline`, `priority?`, `note?`) | UC-30 |
| PATCH | `/api/service-requests/:id/reassign` | manager (`department`, `staffId`, `deadline?`, `note`) | UC-30 |
| PATCH | `/api/service-requests/:id/start` | nhân viên được giao | UC-32 |
| PATCH | `/api/service-requests/:id/finish` (multipart) | nhân viên được giao (`note`, ảnh) | UC-33 |
| PATCH | `/api/service-requests/:id/confirm` | người tạo (`rating` 1–5, `feedback?`) | UC-34 |
| PATCH | `/api/service-requests/:id/reopen` | người tạo (`reason`) | UC-34 |
| GET | `/api/me/assignments?tab=active\|overdue\|done` | staff — phiếu + nhiệm vụ, mỗi mục có `kind: 'request'\|'task'` | UC-31 |
| POST | `/api/tasks` | manager (`title`, `category?`, `location?`, `priority?`, `department`, `staffId`, `deadline`) | UC-41 |
| GET | `/api/tasks?status=&department=&staffId=&overdue=&from=&to=` | manager (tất cả) / staff (luôn chỉ của mình) | UC-41, 42 |
| GET | `/api/tasks/:id` | manager, nhân viên được giao; kèm `timeline`, `allowedActions` | UC-42 |
| PATCH | `/api/tasks/:id/reassign` | manager (`department`, `staffId`, `deadline?`, `note`) | UC-41 |
| PATCH | `/api/tasks/:id/cancel` | manager (`reason`) | UC-41 |
| PATCH | `/api/tasks/:id/start` | nhân viên được giao | UC-31 |
| PATCH | `/api/tasks/:id/complete` (multipart) | nhân viên được giao (`note?`, ảnh) | UC-31 |

| POST | `/api/vehicles` (multipart, ảnh tùy chọn) | resident đang ở căn `apartmentId` | UC-13 |
| GET | `/api/vehicles/mine?status=` | resident (xe các căn mình ở) | UC-15 |
| GET | `/api/vehicles?status=&plate=&type=&apartmentId=` | staff security, manager, accountant | UC-15 |
| GET | `/api/vehicles/:id` | như trên + cư dân cùng căn, kèm `allowedActions` | UC-15 |
| PATCH | `/api/vehicles/:id/approve` | staff security | UC-14 |
| PATCH | `/api/vehicles/:id/reject` | staff security (`reason`) | UC-14 |
| PATCH | `/api/vehicles/:id/deactivate` | resident (xe căn mình), manager | — |
| POST | `/api/visitors` | resident (`visitDate` YYYY-MM-DD, `timeFrom`/`timeTo` HH:mm giờ VN) | UC-16 |
| GET | `/api/visitors/mine?status=` | resident | UC-16 |
| PATCH | `/api/visitors/:id/cancel` | resident (lịch `expected` của căn mình) | UC-16 |
| GET | `/api/visitors?date=&code=&phone=&status=` | staff security/reception, manager (mặc định hôm nay) | UC-17 |
| GET | `/api/visitors/:id` | như trên + cư dân cùng căn, kèm `allowedActions` | UC-17 |
| PATCH | `/api/visitors/:id/check-in` | staff security (trong khung giờ, cho sớm 30 phút) | UC-17 |
| PATCH | `/api/visitors/:id/check-out` | staff security | UC-18 |

| GET | `/api/amenities?includeInactive=` | mọi vai trò (tạm ngưng chỉ manager thấy) | UC-35 |
| POST / PATCH | `/api/amenities`, `/api/amenities/:id` | manager | UC-35 |
| PATCH | `/api/amenities/:id/deactivate`, `/activate` | manager (chỉ chặn đặt mới) | UC-35 |
| GET | `/api/amenities/:id/slots?date=YYYY-MM-DD` | mọi vai trò → `[{start,end,used,remaining,available}]` | UC-36 |
| POST | `/api/amenity-bookings` | resident (`amenityId`, `apartmentId`, `date`, `startTime` HH:mm, `numberOfParticipants`) | UC-37 |
| GET | `/api/amenity-bookings/mine?status=` | resident (lượt đặt của các căn mình ở) | UC-37 |
| GET | `/api/amenity-bookings?status=&amenityId=` | staff facility, manager (mặc định `pending`) | UC-38 |
| GET | `/api/amenity-bookings/:id` | như trên + cư dân cùng căn, kèm `allowedActions`, `cancelDeadline` | UC-38 |
| PATCH | `/api/amenity-bookings/:id/approve` | staff facility | UC-38 |
| PATCH | `/api/amenity-bookings/:id/reject` | staff facility (`reason`, trả chỗ) | UC-38 |
| PATCH | `/api/amenity-bookings/:id/cancel` | người đặt, trước hạn hủy (trả chỗ) | UC-39 |
| PATCH | `/api/amenity-bookings/:id/cancel-by-staff` | staff facility, manager (`reason`; không áp dụng hạn hủy; lượt chưa kết thúc; trả chỗ) | — |

| GET | `/api/dashboard/operations?from=&to=` | manager | UC-47 |
| GET | `/api/reports/staff-performance?from=&to=&department=` | manager | UC-48 |

Dashboard / báo cáo: `from`, `to` là ngày giờ VN (YYYY-MM-DD, gồm cả ngày `to`), mặc định 30 ngày gần nhất,
tối đa 366 ngày. Dashboard: `byStatus`, `open`, `overdue` của phiếu / nhiệm vụ là số **hiện tại** (khớp danh
sách khi bấm xem); `createdInRange` và lượt đặt tiện ích tính trong khoảng. Báo cáo hiệu suất: hoàn thành
phiếu tính **lần báo xong đầu tiên**, đúng hạn tính theo lúc nhân viên báo xong (không theo lúc nghiệm thu);
chỉ số không có dữ liệu trả `null` (không phải 0).

Đặt tiện ích: giữ chỗ bằng collection `amenityslots` (update có điều kiện trong transaction) nên không
vượt sức chứa khi nhiều người đặt cùng lúc → 409 `SLOT_FULL`; một căn một lượt/slot → 409
`BOOKING_DUPLICATE`; quá hạn hủy → 409 `CANCEL_DEADLINE_PASSED`. Booking `pending` cũng giữ chỗ.
Job mỗi giờ: `confirmed` đã dùng xong → `completed`; `pending` quá giờ → `rejected` (hết hạn duyệt).

Biển số lưu dạng chuẩn hóa (`30A-123.45` → `30A12345`); không có 2 xe `approved` trùng biển
(partial unique index), trùng trả 409 `VEHICLE_PLATE_DUPLICATE`. Cho Người 1 tính phí xe (UC-20):
`require('./services/vehicle.service').getBillableVehicles(apartmentId)` → xe `approved` của căn.
Khách ngoài khung giờ: 409 `VISITOR_OUT_OF_WINDOW`; quá giờ chưa đến: cờ `isOverdue`.

\* Manager: mọi phiếu. Staff: phiếu đang giao cho mình. Resident: phiếu mình tạo + phiếu sửa chữa của
căn mình đang ở. Ngoài phạm vi trả 404. Sai trạng thái trả 409 `INVALID_STATE`.
Luồng: `pending → assigned → in_progress → waiting_confirmation → closed`; nhánh `rejected`,
`reopened`; job mỗi giờ tự đóng phiếu chờ nghiệm thu quá 7 ngày.

`MAIL_MODE=console` (mặc định): OTP in ra console và trả trong `data.devOtp` để demo.
`MAIL_MODE=smtp`: gửi email thật, cần `SMTP_USER` + `SMTP_PASS` (Gmail App Password).
