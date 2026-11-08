# Kế hoạch Người 2 — Module Vận hành

**Dự án:** Apartment Management (Flutter + Node/Express + MongoDB)
**Phạm vi:** M3, M5, M6, M7, UC-47 và phần hiệu suất của UC-48 (23 UC + nửa UC-48).
**Nguồn:** `Phan_Cong_Cong_Viec.pdf`, `Apartment_Management_Nghiep_Vu_Modules_De_Xuat.docx`, `ERD_Apartment_Building_Management.drawio`, và **code của Người 1 đã merge vào `main`** (M1, M2, M8 — commit `e1c57ed`).
**Cập nhật:** 2026-11-08 — viết lại để bám theo kiến trúc và quy ước Người 1 đã dựng.

Quy ước trong file:

- **[Spec]**: có trong tài liệu nhóm.
- **[Code N1]**: đã có trong code của Người 1, dùng lại, không viết lại.
- **[Đề xuất]**: tài liệu và code chưa có, đây là phương án mặc định. Cần báo nhóm.
- **[Cần N1]**: phải sửa vào file của Người 1 hoặc file dùng chung, báo trước khi làm.

---

## 1. Tóm tắt

**Hiện trạng repo [Code N1]:**

- Backend Express 5 + Mongoose 8 + Zod 4 trong `backend/`, đã có auth JWT, phân quyền theo vai trò/bộ phận, format response, xử lý lỗi, M1 (tài khoản), M2 (căn hộ, cư trú), M8 (bảng tin, thông báo).
- Flutter đã có Riverpod 3, go_router, Dio, secure storage, intl; router có guard theo vai trò; widget chung; trang chủ hiển thị chức năng theo vai trò.
- Model `Vehicle` đã có sẵn (schema dùng chung, partial unique index biển số).

Vì vậy Giai đoạn 0 chỉ còn **bổ sung phần khung mà module vận hành cần** (transaction, upload, sinh mã, giờ Việt Nam, seed).

**Thứ tự làm:**

| # | Giai đoạn | UC | Ước lượng* | Lý do đứng ở vị trí này |
|---|---|---|---|---|
| 0 | Bổ sung khung | — | 1–2 ngày | Transaction, upload, seed nhân viên; khung chính Người 1 đã làm |
| 1 | Nhân viên theo bộ phận | UC-40 | 1 ngày | M5 cần để phân công |
| 2 | Phiếu yêu cầu, phản ánh | UC-27 → 34 | 6 ngày | P0, nhiều vai trò, nhiều logic nhất |
| 3 | Xe và khách | UC-13 → 18 | 3–4 ngày | Người 1 cần xe `approved` để tính phí (UC-20) |
| 4 | Đặt tiện ích | UC-35 → 39 | 5 ngày | Độc lập, có bài toán tranh chấp slot |
| 5 | Nhiệm vụ vận hành | UC-41, 42 | 2–3 ngày | Tái dùng phân công và lịch sử của M5 |
| 6 | Dashboard, báo cáo | UC-47, 48 | 3 ngày | Phải có dữ liệu của các module trên |
| 7 | Tích hợp, dữ liệu demo | — | 3 ngày | Làm chung với Người 1 |

\* Ước lượng cho một người làm toàn thời gian, tổng khoảng 4–5 tuần. Nếu thiếu thời gian, cắt theo mục 11.

**Năm điểm khó nhất:**

1. **Máy trạng thái phiếu** phải chặn được chuyển trạng thái sai và luôn ghi lịch sử (mục 6.2).
2. **Chống đặt vượt sức chứa** khi hai người đặt cùng lúc (mục 8.2).
3. **Transaction cần replica set**, nhưng test hiện tại của Người 1 chạy trên `mongod` standalone (mục 4.4).
4. **Phân quyền theo dữ liệu:** cư dân không được xem hoặc thao tác trên căn hộ của người khác (mục 4.2).
5. **Ranh giới với Người 1:** bộ phận là enum trên `User`, khóa tài khoản và chuyển đi nằm trong code của Người 1 (mục 3).

---

## 2. Vấn đề cần chốt với nhóm

### 2.1. Mâu thuẫn tài liệu và cách đã xử lý

| # | Vấn đề | Hướng xử lý |
|---|---|---|
| 1 | Docx ghi 15 collection, ERD có 19 | Lấy ERD làm chuẩn, nhưng code của Người 1 đã gộp `Residents` vào `ApartmentResidents` và bỏ `Departments` (xem mục 2.2) → cập nhật lại ERD |
| 2 | ERD đặt `plateNumber` là UK | **Đã xử lý [Code N1]:** partial unique index `unique_approved_plate` chỉ áp cho xe `approved` |
| 3 | Spec yêu cầu "từ chối phải có lý do" nhưng luồng phiếu không có `Rejected` | Thêm trạng thái `rejected` [Đề xuất] |
| 4 | Docx dùng VNPay, PDF và ERD dùng PayOS | Thuộc Người 1 |
| 5 | `OperationalTasks.status` chưa có danh sách trạng thái | `assigned → in_progress → completed`, thêm `cancelled` [Đề xuất] |
| 6 | Visitor `expected` quá giờ mà khách không đến | Không thêm trạng thái, API trả cờ tính toán `isOverdue` |
| 7 | Chống đặt vượt sức chứa cần collection chưa có trong ERD | Thêm `AmenitySlots` (mục 8.2) |

### 2.2. Quyết định cần nhóm chốt

| # | Câu hỏi | Mặc định [Đề xuất] |
|---|---|---|
| 1 | Cư dân không nghiệm thu thì tự đóng phiếu sau bao lâu? | 7 ngày, không có đánh giá |
| 2 | Làm đủ 48 UC hay chia P0/P1? | Làm theo ưu tiên, xem mục 11 |
| 3 | Ai được từ chối phiếu? | Chỉ Manager, khi phiếu đang `pending` |
| 4 | Thành viên cùng căn hộ có thấy phiếu của nhau không? | Sửa chữa: có. Phản ánh: chỉ người tạo |
| 5 | Ảnh lưu ở đâu? | Multer lưu `backend/uploads/`, bọc trong `upload.service.js` để sau đổi được |
| 6 | Cư dân hủy đăng ký xe đang chờ duyệt? | Cho `pending → inactive` |
| 7 | Đặt tiện ích trước tối đa bao lâu? | 30 ngày |
| 8 | Có collection `Departments` không? | **✅ Đã chốt 2026-11-08:** giữ enum trên `User.department` (`reception`, `security`, `technical`, `facility`), không tạo collection. UC-40 rút gọn còn "xem nhân viên theo bộ phận + số việc đang mở" |
| 9 | Nhân viên nghỉ việc biểu diễn thế nào? | **✅ Đã chốt 2026-11-08:** dùng `User.status = inactive` (UC-05 của Người 1). Người 1 gọi `assertNoOpenWork` trước khi khóa tài khoản hoặc đổi vai trò staff (mục 3) |
| 10 | Cư dân truy cập dữ liệu căn hộ khác trả 403 hay 404? | **✅ Đã chốt 2026-11-08:** truy cập dữ liệu căn hộ khác trả 403 `FORBIDDEN`, giống Người 1. Riêng truy cập theo id (phiếu, booking, xe) trả 404 `NOT_FOUND` |
| 11 | Tiện ích có sự cố (bảo trì, hỏng) thì lượt đặt đã xác nhận xử lý thế nào? Trước đây chỉ người đặt tự hủy được, "Manager tự xử lý" nhưng không có API | **✅ Đã chốt 2026-11-08:** thêm **"Hủy do sự cố"** (`PATCH /amenity-bookings/:id/cancel-by-staff`) cho Facility và Manager: bắt buộc lý do, không áp dụng hạn hủy, chỉ lượt chưa kết thúc, trả chỗ, báo cư dân. Duyệt / từ chối vẫn **chỉ Facility** |

---

## 3. Điểm giao với Người 1

| Điểm giao | Người 1 cung cấp [Code N1] | Người 2 cung cấp | Ghi chú |
|---|---|---|---|
| Xác thực | `authenticate`, `authorize`, `signToken` trong `middleware/auth.js` | — | `authenticate` đọc user từ DB mỗi request, khóa tài khoản có hiệu lực ngay |
| Tài khoản nhân viên (UC-04/05 vs UC-40) | `POST /users`, `PATCH /users/:id/status`, `PATCH /users/:id/role`, `userService.listUsers` | `GET /staff` (kèm số việc đang mở), `assertNoOpenWork(userId)` | **Không viết API tạo/khóa user thứ hai** |
| Cư trú | `ApartmentResident` (có `userId` trực tiếp), `apartmentService.findMembership`, `assertCanView` | `shared/residency.js` bọc lại | Không có model `Resident` riêng |
| Thông báo (UC-45) | `notifyUsers` thật (`services/notify.service.js`) | Gọi tại mọi sự kiện, bổ sung bảng `type` trong README | Không cần stub |
| Phí xe (UC-20) | Tính phí xe | `vehicleService.getBillableVehicles(apartmentId)` | Chỉ xe `approved` |
| Chuyển đi (UC-11) | **[Cần N1]** gọi hook trong `residentService.moveOut` | `operationsHooks.onResidentMovedOut(apartmentId, userId)` | Hiện `moveOut` chưa gọi hook nào |
| Khóa nhân viên | **[Cần N1]** gọi trong `userService.updateStatus`, `updateRole` | `operationsHooks.assertNoOpenWork(userId)` | Ném 409 nếu còn phiếu/nhiệm vụ đang mở |

**Interface `notifyUsers` [Code N1]** — dùng đúng chữ ký này:

```js
const { notifyUsers } = require('./notify.service');

await notifyUsers({
  userIds: [request.createdBy],                 // tự loại trùng, bỏ giá trị rỗng
  type: 'service_request_assigned',             // snake_case, chữ thường
  title: 'Phiếu SR-7KQ2M đã được phân công',
  body: 'Nhân viên Nguyễn Văn A sẽ xử lý trước 10/11',
  link: { kind: 'service_request', id: String(request._id) },
});
```

- Hàm không ném lỗi ra ngoài (chỉ log), nên gọi **sau khi** transaction commit là đủ an toàn.
- Mỗi `type` mới phải thêm vào bảng "Loại notification" trong `backend/README.md` để Flutter mở đúng màn hình theo `link.kind`. Hiện màn thông báo của Người 1 chưa điều hướng theo `link.kind` → khi có module của Người 2 thì thống nhất bảng `kind → route` (đề xuất đặt ở `lib/features/communication/presentation/notification_links.dart`).

**`link.kind` Người 2 dùng [Đề xuất]:** `service_request`, `task`, `vehicle`, `visitor`, `amenity_booking`.

**`onResidentMovedOut(apartmentId, userId)` [Đề xuất]:** gọi sau `rec.save()` trong `moveOut`, chỉ khi hồ sơ có `userId`.

- Nếu căn hộ không còn ai `active` (dùng `apartmentService.recomputeStatus` hoặc `ApartmentResident.exists`):
  - Xe `approved`/`pending` → `inactive`.
  - Khách `expected` → `cancelled`.
  - Booking tương lai → `cancelled` và trả slot.
  - Phiếu đang mở giữ nguyên để Manager xử lý.
- Nếu căn hộ còn người ở: chỉ hủy booking và lịch khách **do chính người đó tạo**.
- Lỗi trong hook chỉ log, không làm hỏng thao tác chuyển đi.

---

## 4. Kiến trúc và quy ước (theo Người 1)

### 4.1. Cấu trúc thư mục

Người 1 dùng **cấu trúc phẳng theo lớp**, không chia `modules/`. Người 2 theo đúng cấu trúc này:

```text
backend/src/
  config/          db.js, env.js                                  [Code N1]
  middleware/      auth.js, validate.js, errorHandler.js          [Code N1]
                   upload.js                                      [mới]
  models/          User, Apartment, ApartmentResident, Vehicle,
                   Notification, Announcement                     [Code N1]
                   ServiceRequest, RequestHistory, Visitor, Amenity,
                   AmenitySlot, AmenityBooking, OperationalTask   [mới]
  validators/      common.js (objectId, pagination, idParams)     [Code N1]
                   serviceRequest, vehicle, visitor, amenity, task, report .validators.js  [mới]
  controllers/     <tên>.controller.js                            [mới]
  services/        notify.service.js                              [Code N1]
                   serviceRequest, vehicle, visitor, amenity, task, staff, report .service.js,
                   upload.service.js, operationsHooks.js          [mới]
  routes/          index.js (đăng ký tập trung)                   [Code N1, thêm dòng]
                   serviceRequest, vehicle, visitor, amenity, amenityBooking, task, staff, dashboard .routes.js  [mới]
  shared/          residency.js, assignee.js, code.js, time.js, transaction.js  [mới]
  jobs/            autoCloseRequests.js, completeBookings.js      [mới]
  scripts/seed.js                                                 [Code N1, mở rộng]
backend/tests/     helpers.js (setupDb, createUser, bearer)       [Code N1]

lib/
  core/            network/api_client.dart, router/app_router.dart,
                   widgets/common.dart, widgets/paged_list_view.dart,
                   utils/formatters.dart, utils/validators.dart   [Code N1]
  features/<tên>/
    application/   <tên>_providers.dart   (Riverpod)
    data/          models.dart, <tên>_repository.dart
    presentation/  *_page.dart, widgets.dart
```

Feature Flutter mới: `service_requests`, `vehicles`, `visitors`, `amenities`, `tasks`, `staff`, `dashboard`.

**Luồng một API [Code N1]:** `routes → authenticate → authorize → validate → controller → service → model`.

- Controller đọc `req.validated.{body|query|params}` (không đọc `req.body` trực tiếp), trả bằng `ok(res, data, meta)` / `created(res, data)` từ `utils/response.js`.
- Service chứa nghiệp vụ, không đụng `req`/`res`, ném `AppError`.
- Express 5 tự bắt lỗi của handler async, không cần `try/catch` hay `asyncHandler`.

**Luồng một màn hình Flutter [Code N1]:** `Page → Provider (application/) → Repository (data/) → ApiClient`.

### 4.2. Ba lớp phân quyền

| Lớp | Câu hỏi | Công cụ |
|---|---|---|
| 1. Vai trò | Có phải Manager không? | `authorize([ROLES.MANAGER])` [Code N1] |
| 2. Bộ phận | Có phải Staff bộ phận Security không? | `authorize([ROLES.STAFF], { departments: [DEPARTMENTS.SECURITY] })` [Code N1] |
| 3. Dữ liệu | Đúng căn hộ hoặc đúng người phụ trách? | Kiểm tra trong service |

Lưu ý `authorize` với `departments` **chỉ lọc Staff**: role khác nằm trong `roles` thì vẫn qua. Ví dụ Security + Manager: `authorize([ROLES.STAFF, ROLES.MANAGER], { departments: [DEPARTMENTS.SECURITY] })`.

```js
// shared/residency.js — không bao giờ tin apartmentId client gửi lên mà không kiểm tra
const apartmentService = require('../services/apartment.service');
const { AppError, ERROR_CODES } = require('../utils/errors');

async function assertActiveResident(userId, apartmentId) {
  const membership = await apartmentService.findMembership(userId, apartmentId);
  if (!membership) {
    throw new AppError(ERROR_CODES.NOT_APARTMENT_RESIDENT, 'Bạn không cư trú tại căn hộ này');
  }
  return membership; // có relation, isPayer nếu cần
}

// Các căn hộ user đang ở — dùng cho các API "của tôi"
const myApartmentIds = (userId) =>
  ApartmentResident.find({ userId, status: RESIDENT_STATUS.ACTIVE }).distinct('apartmentId');
```

Một cư dân có thể ở nhiều căn → API tạo (phiếu, xe, khách, booking) **bắt buộc** gửi `apartmentId` và luôn qua `assertActiveResident`.

### 4.3. Mẫu cập nhật trạng thái an toàn

Mọi thao tác đổi trạng thái dùng **điều kiện trạng thái ngay trong câu update**:

```js
const updated = await Visitor.findOneAndUpdate(
  { _id: id, status: VISITOR_STATUS.EXPECTED },
  { $set: { status: VISITOR_STATUS.CHECKED_IN, checkInTime: new Date(), checkedInBy: actor._id } },
  { new: true },
);
if (!updated) throw new AppError(ERROR_CODES.VISITOR_INVALID_STATE, 'Lịch hẹn đã thay đổi trạng thái');
```

(Code M2 của Người 1 đang đọc rồi `save()` — chấp nhận được cho nghiệp vụ của họ, nhưng module vận hành có tranh chấp thật nên không làm theo kiểu đó.)

### 4.4. Transaction và môi trường

Phiếu + lịch sử, booking + slot cần **MongoDB transaction**, yêu cầu replica set.

**Hiện trạng [Code N1]:** `tests/setup.js` trỏ `mongodb://127.0.0.1:27017/apartment_management_test` (standalone), `tests/helpers.js` có `setupDb/teardownDb`. Máy Người 2 chưa có `mongod`.

**Phương án [Đề xuất] [Cần N1]:**

- **Test:** thêm devDependency `mongodb-memory-server`, sửa `tests/helpers.js`: nếu không có `MONGODB_TEST_URI` thì khởi `MongoMemoryReplSet` (1 node) và `connectDb(replSet.getUri())`. Test hiện có của Người 1 vẫn chạy như cũ, không cần cài Mongo.
- **Dev và demo:** MongoDB Atlas M0 (là replica set sẵn). Connection string chia sẻ qua kênh riêng, chỉ để trong `.env`.
- Helper dùng chung:

```js
// shared/transaction.js
async function withTransaction(fn) {
  const session = await mongoose.startSession();
  try {
    let result;
    await session.withTransaction(async () => { result = await fn(session); });
    return result;
  } finally {
    await session.endSession();
  }
}
```

### 4.5. Quy ước chung [Code N1]

```jsonc
// Thành công (utils/response.js)
{ "success": true, "data": {}, "meta": { "page": 1, "limit": 20, "total": 57, "totalPages": 3 } }
// Lỗi (middleware/errorHandler.js)
{ "success": false, "error": { "code": "SLOT_FULL", "message": "Khung giờ đã đầy", "details": [] } }
```

| HTTP | Khi nào |
|---|---|
| 400 | `VALIDATION_ERROR` (Zod, có `details`), `BAD_REQUEST` |
| 401 | Chưa đăng nhập, token hết hạn hoặc đã bị vô hiệu do đổi mật khẩu |
| 403 | `FORBIDDEN`, `ACCOUNT_INACTIVE`, cư dân truy cập căn hộ khác |
| 404 | Không tồn tại, hoặc tài nguyên theo id không thuộc phạm vi người xem |
| 409 | Sai trạng thái, trùng, hết chỗ. Lỗi `E11000` không bắt riêng sẽ thành `CONFLICT` chung |

**Mã lỗi:** `AppError` nhận **object** `{ status, code }` trong `ERROR_CODES` (`utils/errors.js`), không nhận số. Người 2 thêm mã riêng vào chính object này **[Cần N1]** (chỉ thêm dòng, không sửa dòng cũ):

```js
// utils/errors.js — phần Người 2 thêm
NOT_APARTMENT_RESIDENT: { status: 403, code: 'NOT_APARTMENT_RESIDENT' },
ASSIGNEE_INVALID:       { status: 409, code: 'ASSIGNEE_INVALID' },
HAS_OPEN_WORK:          { status: 409, code: 'HAS_OPEN_WORK' },
INVALID_STATE:          { status: 409, code: 'INVALID_STATE' },   // dùng chung cho mọi máy trạng thái
VEHICLE_PLATE_DUPLICATE:{ status: 409, code: 'VEHICLE_PLATE_DUPLICATE' },
VISITOR_OUT_OF_WINDOW:  { status: 409, code: 'VISITOR_OUT_OF_WINDOW' },
SLOT_FULL:              { status: 409, code: 'SLOT_FULL' },
BOOKING_DUPLICATE:      { status: 409, code: 'BOOKING_DUPLICATE' },
CANCEL_DEADLINE_PASSED: { status: 409, code: 'CANCEL_DEADLINE_PASSED' },
```

Phía Flutter, `ApiException` đã có `code`, `message`, `statusCode`, `details` → so `e.code == 'SLOT_FULL'` để xử lý riêng.

**Enum [Code N1]:** **chữ thường**, khai báo tập trung trong `utils/constants.js` bằng `Object.freeze`. Nhiều từ dùng snake_case: `in_progress`, `waiting_confirmation`, `checked_in`. Flutter có enum tương ứng với `parse()` và `label` tiếng Việt (giống `UserRole`, `Department` trong `app_user.dart`).

**API [Code N1]:** danh từ số nhiều; tạo bằng `POST`; **hành động đổi trạng thái dùng `PATCH /:id/<hành-động>`** (giống `PATCH /residents/:id/approve`). Danh sách dùng `pagination` từ `validators/common.js` (`page`, `limit ≤ 100`).

**Thời gian [Đề xuất]:** DB lưu UTC, logic theo `Asia/Ho_Chi_Minh`. Thêm `luxon`, gom vào `shared/time.js` (`startOfDayVN(dateStr)`, `nowVN()`). Đừng dùng `new Date('2026-11-06')` rồi so ngày, sẽ lệch 7 tiếng. Flutter đã có `apiDate()` trong `formatters.dart` để gửi `yyyy-MM-dd`.

**Mã tự sinh [Đề xuất]:** `shared/code.js` — tiền tố + 6 ký tự từ `crypto.randomInt` (Người 1 cũng dùng `crypto` cho OTP), gặp `E11000` thì sinh lại. Tiền tố: `SR-` (phiếu), `TK-` (nhiệm vụ), `VS-` (mã hẹn khách).

---

## 5. Giai đoạn 0–1: Bổ sung khung và nhân viên

### Giai đoạn 0 — bổ sung khung

**Đã có [Code N1], không làm lại:**

- [x] Express, kết nối Mongo, `.env.example`, `backend/.gitignore`
- [x] `AppError`, `errorHandler`, `ok/created`, `validate` (Zod)
- [x] `authenticate`, `authorize` (vai trò + bộ phận)
- [x] Model `User`, `Apartment`, `ApartmentResident`, `Vehicle`, `Notification`
- [x] `notifyUsers` thật
- [x] Flutter: Riverpod, go_router, Dio, secure storage, intl; `ApiClient` + `ApiException`; theme; router guard theo vai trò; `ErrorView`, `LoadingButton`, `InfoRow`, `confirmDialog`, `showSnack`, `PagedListView`

**Người 2 bổ sung:**

Backend:

- [x] `mongodb-memory-server` qua `tests/globalSetup.js` + `globalTeardown.js` (không phải sửa `helpers.js`)
- [x] `shared/transaction.js`, `shared/code.js`, `shared/time.js` (+ `luxon`), `shared/residency.js`, `shared/assignee.js`, `shared/optionalModel.js`
- [x] Mã lỗi mới trong `utils/errors.js`, enum mới trong `utils/constants.js`
- [x] `multer` + `middleware/upload.js` (`uploadImages(field, max)`) + `services/upload.service.js` (`saveImages`, `removeImages`, kiểm tra chữ ký file); `/uploads` trong `app.js`; `UPLOAD_DIR` trong `env.js`; `uploads/` trong `.gitignore`
- [x] Mở rộng `scripts/seed.js`: Manager, Kế toán, Staff 4 bộ phận (Technical 2 người), 4 cư dân, 5 căn hộ, 6 hồ sơ cư trú; chạy lại không trùng. Tiện ích thêm ở Giai đoạn 4
- [x] Hook `onResidentMovedOut` trong `residentService.moveOut`, `assertNoOpenWork` trong `userService.updateStatus/updateRole`

Flutter:

- [x] Thêm `image_picker` (`fl_chart` để giai đoạn 6)
- [x] `UploadFile` + extension `ApiClient.multipart(...)` ở `core/network/multipart.dart` (file riêng, không sửa `api_client.dart`)
- [x] `StatusChip` + `StatusTone` ở `core/widgets/status_chip.dart`
- [ ] Thêm `link.kind` của module vận hành vào `routeForNotification` (`communication_providers.dart`, Người 1 đã có sẵn hàm) — làm khi có màn hình tương ứng

**Xong khi:** `npm test` chạy được không cần cài Mongo; test transaction mẫu pass; seed đăng nhập được đủ vai trò trên app.

### Giai đoạn 1 — UC-40 (bản rút gọn theo enum bộ phận)

**Nghiệp vụ:** Manager xem nhân viên theo bộ phận và tải việc. Thêm/sửa/khóa nhân viên **dùng API của Người 1** (`POST /users`, `PATCH /users/:id/status|role`).

| API | Quyền | Logic chính |
|---|---|---|
| `GET /staff?department=&status=` | Manager | Lọc `role = staff`; kèm `openRequests`, `openTasks` (aggregate) để cân tải |
| `GET /staff/departments` | Đã đăng nhập | Trả `DEPARTMENTS` + nhãn + số nhân viên `active`; dữ liệu tĩnh, không CRUD |

**Hàm dùng chung cho UC-30 và UC-41:**

```js
// shared/assignee.js
async function assertAssignable(staffId, department) {
  const staff = await User.findOne({
    _id: staffId, role: ROLES.STAFF, status: USER_STATUS.ACTIVE, department,
  });
  if (!staff) throw new AppError(ERROR_CODES.ASSIGNEE_INVALID, 'Nhân viên không hợp lệ cho bộ phận này');
  return staff;
}

// services/operationsHooks.js — Người 1 gọi trong userService.updateStatus/updateRole
async function assertNoOpenWork(userId) {
  const [r, t] = await Promise.all([
    ServiceRequest.exists({ assignedStaffId: userId, status: { $in: OPEN_REQUEST_STATUSES } }),
    OperationalTask.exists({ assignedStaffId: userId, status: { $in: OPEN_TASK_STATUSES } }),
  ]);
  if (r || t) throw new AppError(ERROR_CODES.HAS_OPEN_WORK, 'Nhân viên còn việc đang mở, hãy chuyển người trước');
}
```

**Flutter:** màn "Nhân viên" (tab theo bộ phận, số việc đang mở), bấm vào mở `UserDetailPage` sẵn có của Người 1.

**Trạng thái (2026-11-08):** ✅ Xong Giai đoạn 0 và 1.
- Backend: `services/staff.service.js`, `routes/staff.routes.js`; `staffService.listStaff` đếm việc qua `optionalModel`, tự có số khi M5/M7 tạo model.
- Flutter: `features/staff/` (`StaffListPage`, `StaffTile`, `WorkloadChip` dùng lại ở màn phân công M5/M7), route `/staff` (Manager), mục "Nhân viên" ở trang chủ.
- Test: backend 93/93, Flutter 23/23, `flutter analyze` sạch.

---

## 6. Giai đoạn 2: M5 — Phiếu yêu cầu và phản ánh (UC-27 → 34)

### 6.1. Nghiệp vụ

Cư dân gửi phiếu → Manager giao đúng bộ phận và người → Staff xử lý → cư dân nghiệm thu hoặc yêu cầu làm lại. UC-27 và UC-28 dùng chung một collection, khác ở `requestType` (`repair`/`complaint`), nên chỉ viết **một** service và **một** form có tham số.

### 6.2. Máy trạng thái

```js
// utils/constants.js
const REQUEST_STATUS = Object.freeze({
  PENDING: 'pending', REJECTED: 'rejected', ASSIGNED: 'assigned', IN_PROGRESS: 'in_progress',
  WAITING_CONFIRMATION: 'waiting_confirmation', REOPENED: 'reopened', CLOSED: 'closed',
});
```

| Từ | Sang | Hành động | Ai làm | Bắt buộc |
|---|---|---|---|---|
| — | `pending` | Tạo | Cư dân của căn hộ | Tiêu đề, mô tả, danh mục |
| `pending` | `rejected` | Từ chối | Manager | Lý do |
| `pending` | `assigned` | Phân công | Manager | Bộ phận, nhân viên, deadline |
| `assigned`, `in_progress` | `assigned` | Chuyển người | Manager | Lý do, người mới |
| `assigned` | `in_progress` | Bắt đầu | Nhân viên được giao | — |
| `in_progress` | `waiting_confirmation` | Báo xong | Nhân viên được giao | Ghi chú, ảnh tùy chọn |
| `waiting_confirmation` | `closed` | Nghiệm thu | Người tạo | Điểm 1–5, nhận xét tùy chọn |
| `waiting_confirmation` | `reopened` | Yêu cầu làm lại | Người tạo | Lý do |
| `waiting_confirmation` | `closed` | Tự đóng | Hệ thống (job) | Sau 7 ngày |
| `reopened` | `in_progress` | Làm lại | Nhân viên được giao | — |
| `reopened` | `assigned` | Giao người khác | Manager | Người mới |

`rejected` và `closed` là trạng thái cuối.

### 6.3. Luồng code chính

```js
// services/serviceRequest.service.js
const S = REQUEST_STATUS;
const isManager  = (u) => u.role === ROLES.MANAGER;
const isAssignee = (u, r) => String(r.assignedStaffId) === String(u._id);
const isCreator  = (u, r) => String(r.createdBy) === String(u._id);

const TRANSITIONS = {
  reject:   { from: [S.PENDING], to: S.REJECTED, can: isManager },
  assign:   { from: [S.PENDING, S.REOPENED], to: S.ASSIGNED, can: isManager },
  reassign: { from: [S.ASSIGNED, S.IN_PROGRESS], to: S.ASSIGNED, can: isManager },
  start:    { from: [S.ASSIGNED, S.REOPENED], to: S.IN_PROGRESS, can: isAssignee },
  finish:   { from: [S.IN_PROGRESS], to: S.WAITING_CONFIRMATION, can: isAssignee },
  confirm:  { from: [S.WAITING_CONFIRMATION], to: S.CLOSED, can: isCreator },
  reopen:   { from: [S.WAITING_CONFIRMATION], to: S.REOPENED, can: isCreator },
};

async function transition(requestId, action, actor, input = {}) {
  const rule = TRANSITIONS[action];
  const request = await ServiceRequest.findById(requestId);
  if (!request) throw new AppError(ERROR_CODES.NOT_FOUND, 'Không tìm thấy phiếu');
  if (!rule.can(actor, request)) throw new AppError(ERROR_CODES.FORBIDDEN, 'Bạn không có quyền thao tác phiếu này');

  const changes = await buildChanges(action, request, input); // assertAssignable, rating, lý do...

  const updated = await withTransaction(async (session) => {
    const doc = await ServiceRequest.findOneAndUpdate(
      { _id: requestId, status: { $in: rule.from } },
      { $set: { status: rule.to, ...changes } },
      { new: true, session },
    );
    if (!doc) throw new AppError(ERROR_CODES.INVALID_STATE, 'Phiếu đã thay đổi, vui lòng tải lại');
    await RequestHistory.create([{
      requestId, updatedBy: actor._id, action,
      previousStatus: request.status, newStatus: rule.to,
      note: input.note, attachments: input.attachments,
    }], { session });
    return doc;
  });

  await notifyForTransition(action, updated, actor); // ngoài transaction, notifyUsers không ném lỗi
  return updated;
}
```

### 6.4. API và quy tắc từng UC

Đăng ký trong `routes/index.js`: `router.use('/service-requests', require('./serviceRequest.routes'))`.

| UC | API | Quyền (`authorize`) | Logic cần nhớ |
|---|---|---|---|
| 27, 28 | `POST /service-requests` (multipart) | `resident` | `assertActiveResident`; tối đa 5 ảnh, 5 MB/ảnh, JPEG/PNG; sinh `requestCode`; lịch sử `created`; báo Manager (`service_request_created`) |
| 29 | `GET /service-requests/mine?status=&type=` | `resident` | Theo `myApartmentIds`; quy tắc xem theo mục 2.2 #4 |
| 29 | `GET /service-requests/:id` | Mọi vai trò, kiểm tra trong service | Không đúng phạm vi trả 404; kèm timeline |
| 30 | `GET /service-requests?status=&priority=&department=` | `manager` | Mặc định `pending`, sắp theo ưu tiên rồi thời gian |
| 30 | `PATCH /service-requests/:id/assign` | `manager` | `assertAssignable`; deadline ở tương lai; có thể chỉnh `priority` |
| 30 | `PATCH /:id/reassign`, `PATCH /:id/reject` | `manager` | Bắt buộc lý do |
| 31 | `GET /me/assignments` | `staff` | Chỉ `assignedStaffId = tôi`; trả cờ `isOverdue` (gộp nhiệm vụ, mục 9.1) |
| 32, 33 | `PATCH /:id/start`, `PATCH /:id/finish` (multipart) | `staff` + `isAssignee` | Mọi cập nhật có lịch sử; `finish` nhận ảnh sau xử lý, ghi `waitingSince` |
| 34 | `PATCH /:id/confirm`, `PATCH /:id/reopen` | `resident` + `isCreator` | `rating` 1–5; ghi `closedAt`; reopen bắt buộc lý do |

**Model `ServiceRequest` [Đề xuất]:** `requestCode` (unique), `requestType`, `category`, `title`, `description`, `priority` (`low|normal|high|urgent`), `apartmentId`, `createdBy` (User), `department` (enum `DEPARTMENTS`), `assignedStaffId`, `deadline`, `status`, `images[]`, `resultImages[]`, `rejectReason`, `waitingSince`, `firstFinishedAt`, `closedAt`, `rating`, `feedback`, timestamps. Tên trường lý do từ chối theo Người 1: **`rejectReason`**.

**Chi tiết dễ sót:**

- Khi trả timeline cho cư dân, **lọc bỏ** ghi chú nội bộ (`assign`, `reassign`) bằng danh sách action được phép.
- `RequestHistory` có cả `requestId` và `taskId`: validate đúng một trong hai có giá trị.
- `updatedBy` cho phép rỗng để job tự đóng ghi lịch sử với action `auto_closed`.
- Ảnh lưu tên ngẫu nhiên, kiểm tra chữ ký file thật, không chỉ tin `mimetype`.
- `isOverdue` là giá trị tính toán, không lưu DB.
- `toJSON` xóa `__v` giống các model của Người 1.

**Job tự đóng** (mỗi giờ, `setInterval` khởi trong `server.js`, không chạy khi `NODE_ENV=test`): phiếu `waiting_confirmation` có `waitingSince` quá 7 ngày; mỗi phiếu dùng `findOneAndUpdate` có điều kiện trạng thái.

### 6.5. Index

```js
serviceRequestSchema.index({ apartmentId: 1, createdAt: -1 });
serviceRequestSchema.index({ assignedStaffId: 1, status: 1 });
serviceRequestSchema.index({ status: 1, priority: 1, createdAt: 1 });
requestHistorySchema.index({ requestId: 1, createdAt: 1 });
```

### 6.6. Màn hình Flutter (`lib/features/service_requests/`)

| Vai trò | Màn hình |
|---|---|
| Resident | Phiếu của tôi (`PagedListView`); Tạo phiếu (chọn căn hộ nếu ở nhiều căn, loại, ảnh, ưu tiên); Chi tiết + timeline; Nghiệm thu hoặc Yêu cầu làm lại |
| Manager | Hàng chờ phiếu; Phân công (bộ phận → nhân viên kèm số việc → deadline); Từ chối |
| Staff | Việc của tôi (tab đang làm/quá hạn/đã xong); Chi tiết + nút theo trạng thái; Báo xong kèm ảnh |

Đăng ký: thêm `_Feature(...)` vào `home_page.dart` và luật vào `_routeRules` trong `app_router.dart` (mỗi module một khối, có comment `// M5`). Khi nhận `INVALID_STATE`, tải lại chi tiết và `showSnack('Phiếu đã thay đổi')`.

### 6.7. Thứ tự làm trong M5

1. Model + bảng `TRANSITIONS` + test bảng chuyển trạng thái.
2. Tạo phiếu + upload → màn Tạo phiếu, Phiếu của tôi.
3. Hàng chờ + phân công → màn Manager.
4. Việc của tôi + start/finish → màn Staff.
5. Nghiệm thu, làm lại → màn cư dân.
6. Timeline, thông báo, job tự đóng.

**Xong khi:** chạy trọn luồng 3 vai trò trên app, kể cả nhánh làm lại và từ chối.

**Trạng thái (2026-11-08):** ✅ Code + test xong; **chưa chạy thử trên app thật** (cần Mongo replica set: Atlas hoặc Mongo local bật replica set).
- Backend: `models/ServiceRequest.js` (thêm `priorityRank` để sắp hàng chờ, `reopenCount`, `autoClosed`), `models/RequestHistory.js`, `services/serviceRequest.service.js` (bảng `TRANSITIONS`, `allowedActions` trả cho app), `routes/serviceRequest.routes.js`, `routes/me.routes.js` (`GET /me/assignments`), `jobs/index.js` (tự đóng mỗi giờ, khởi trong `server.js`).
- Thêm danh mục `REQUEST_CATEGORY` (điện, nước, internet, thang máy, vệ sinh, tiếng ồn, an ninh, thái độ phục vụ, khác).
- Flutter: `features/service_requests/` — Phiếu của tôi, Tạo phiếu (chọn ảnh), Chi tiết + timeline + nút theo `allowedActions`, Hàng chờ (Manager), Phân công / Chuyển người (chọn nhân viên theo tải việc), Việc của tôi (Staff). Thông báo `service_request` mở chi tiết phiếu.
- Mục trang chủ của module vận hành đặt **cuối danh sách** để không đổi vị trí mục của Người 1.
- Test: backend 122/122 (M5: 29 test — luồng đủ, bảng máy trạng thái 7×7, tranh chấp, phạm vi xem, timeline, job), Flutter 29/29.

---

## 7. Giai đoạn 3: M3 — Xe và khách (UC-13 → 18)

### 7.1. Xe

**Model đã có [Code N1]** (`models/Vehicle.js`, schema dùng chung):

| Trường | Ghi chú |
|---|---|
| `apartmentId`, `ownerId` (User) | Bắt buộc |
| `type` | `motorbike` \| `car` (`VEHICLE_TYPE`) |
| `plateNumber` | `uppercase`, `trim` — **chưa bỏ dấu `.`, `-`, khoảng trắng** |
| `brand`, `color` | |
| `status` | `pending` \| `approved` \| `rejected` \| `inactive` (`VEHICLE_STATUS`) |
| `rejectReason`, `reviewedBy`, `reviewedAt` | Dùng `reviewedAt` thay cho `approvedAt` |
| Index | `unique_approved_plate`: unique `plateNumber` khi `status = approved` |

**Người 2 bổ sung [Cần N1]:** `imageUrl` (ảnh xe/cà vẹt), `deactivatedAt`. Không đổi tên trường cũ.

**Trạng thái:** `pending → approved / rejected`, `approved → inactive`, `pending → inactive` (cư dân tự hủy).

**Chuẩn hóa biển số** trong service trước khi kiểm tra, lưu và tìm kiếm — nếu không `30A-123.45` và `30a12345` thành hai xe:

```js
const normalizePlate = (raw) => raw.toUpperCase().replace(/[\s.\-]/g, '');
const PLATE_REGEX = /^[0-9]{2}[A-Z]{1,2}[0-9]{4,6}$/;
```

| UC | API | Quyền | Logic |
|---|---|---|---|
| 13 | `POST /vehicles` (multipart) | `resident` | `assertActiveResident`; chuẩn hóa; đã có xe `approved` cùng biển thì `VEHICLE_PLATE_DUPLICATE`; nhiều hồ sơ `pending` trùng vẫn được, duyệt trước thắng |
| 14 | `PATCH /vehicles/:id/approve` | `staff` + `security` | Điều kiện `pending`; ghi `reviewedBy`, `reviewedAt`; bắt `E11000` → `VEHICLE_PLATE_DUPLICATE`; báo cư dân (`vehicle_approved`) |
| 14 | `PATCH /vehicles/:id/reject` | `staff` + `security` | Bắt buộc `rejectReason` (`vehicle_rejected`) |
| 15 | `GET /vehicles/mine` | `resident` | Theo `myApartmentIds` |
| 15 | `GET /vehicles?status=&plate=&apartmentId=` | `staff` + `security`, `manager`, `accountant` | Tìm biển số phải chuẩn hóa trước |
| — | `PATCH /vehicles/:id/deactivate` | Resident (xe của căn mình), `manager` | Có hiệu lực kỳ phí sau |
| — | `vehicleService.getBillableVehicles(apartmentId)` | Nội bộ cho UC-20 | Chỉ xe `approved` |

**Flutter (`lib/features/vehicles/`):** Resident (Xe của tôi, Đăng ký xe kèm ảnh); Security (Xe chờ duyệt, Tra cứu biển số, Duyệt/Từ chối).

### 7.2. Khách

```js
const VISITOR_STATUS = Object.freeze({
  EXPECTED: 'expected', CHECKED_IN: 'checked_in', CHECKED_OUT: 'checked_out', CANCELLED: 'cancelled',
});
```

**Trạng thái:** `expected → checked_in → checked_out`, `expected → cancelled`.

| UC | API | Quyền | Logic |
|---|---|---|---|
| 16 | `POST /visitors` | `resident` | `assertActiveResident`; `timeFrom < timeTo`; không ở quá khứ; `numberOfPeople ≥ 1`; sinh `appointmentCode` |
| 16 | `GET /visitors/mine`, `PATCH /visitors/:id/cancel` | `resident` | Chỉ hủy khi `expected` |
| 17 | `GET /visitors?date=&code=&phone=&status=` | `staff` + `security`/`reception` | Mặc định hôm nay (giờ VN), trả `isOverdue` |
| 17 | `PATCH /visitors/:id/check-in` | `staff` + `security` | Điều kiện `expected`; đúng ngày; cho đến sớm 30 phút; ngoài khung → `VISITOR_OUT_OF_WINDOW`; báo cư dân (`visitor_checked_in`) |
| 18 | `PATCH /visitors/:id/check-out` | `staff` + `security` | Điều kiện `checked_in`; ghi `checkOutTime`, `checkedOutBy` |

Index: `{ visitDate: 1, status: 1 }`, `{ apartmentId: 1, visitDate: -1 }`; `appointmentCode` unique.

**Flutter (`lib/features/visitors/`):** Resident (Khách của tôi, Đăng ký khách, hiển thị mã hẹn); Security (Khách hôm nay, tìm theo mã/SĐT, nút Check-in/Check-out to, ít bước).

**Không làm** (theo spec): camera nhận diện biển số, barrier, OCR CCCD.

**Xong khi:** chặn được trùng biển số kể cả khi nhập khác định dạng; check-in hai lần chỉ thành công một lần; Người 1 lấy được danh sách xe tính phí.

**Trạng thái (2026-11-08):** ✅ Code + test xong; chưa chạy thử trên app thật.
- Backend: `services/vehicle.service.js` (biển số lưu dạng chuẩn hóa, bắt E11000 khi duyệt → `VEHICLE_PLATE_DUPLICATE`, `getBillableVehicles` cho Người 1), `models/Visitor.js`, `services/visitor.service.js` (giờ VN qua `shared/time`, cho đến sớm 30 phút), routes `/vehicles`, `/visitors`. Chi tiết xe / lịch hẹn trả `allowedActions`.
- Thêm trường `imageUrl` vào `Vehicle` (schema dùng chung, chỉ thêm).
- Phân quyền chốt thêm: Manager **không** duyệt xe (chỉ Bảo vệ), nhưng được ngừng xe; Kế toán xem danh sách xe (đối soát phí); Lễ tân + Manager xem khách tại cổng nhưng chỉ Bảo vệ check-in/out.
- Flutter: `features/vehicles/` (Xe của tôi, Đăng ký xe, Quản lý xe + tra biển số, Chi tiết + Duyệt/Từ chối/Ngừng), `features/visitors/` (Khách của tôi, Đăng ký khách → hiện mã hẹn, Khách tại cổng với nút Check-in/Check-out ngay trên dòng, Chi tiết). Chuyển `ImagePickerField`, `NetworkImageStrip`, `reasonDialog` sang `core/widgets/media_widgets.dart` để dùng chung.
- Test: backend 147/147 (M3: 25 test — trùng biển khác định dạng, duyệt đồng thời, xe inactive đăng ký lại, check-in đồng thời, khung giờ, hook chuyển đi), Flutter 35/35.

---

## 8. Giai đoạn 4: M6 — Đặt tiện ích (UC-35 → 39)

### 8.1. Nghiệp vụ

```js
const BOOKING_STATUS = Object.freeze({
  PENDING: 'pending', CONFIRMED: 'confirmed', REJECTED: 'rejected',
  CANCELLED: 'cancelled', COMPLETED: 'completed',
});
```

**Trạng thái:** `pending → confirmed / rejected / cancelled`, `confirmed → cancelled / completed`.

- `requiresApproval = true`: booking vào `pending`, chờ Staff bộ phận `facility`.
- `requiresApproval = false`: vào thẳng `confirmed`.
- `pending` cũng **giữ chỗ**.

**Cách sinh slot:** từ `openTime`, `closeTime`, `slotDuration`. Ví dụ 06:00–10:00, 60 phút → 4 slot. Mỗi booking đúng một slot. Không hỗ trợ mở qua nửa đêm.

**Điều kiện đặt:**

1. Tiện ích đang hoạt động.
2. Người đặt đang cư trú tại căn hộ (`assertActiveResident`).
3. `startTime` khớp slot hợp lệ, ở tương lai, trong vòng 30 ngày (giờ VN).
4. `numberOfParticipants` từ 1 đến `capacity`.
5. Căn hộ chưa có booking đang hoạt động ở cùng slot.
6. Còn đủ chỗ.

### 8.2. Chống đặt vượt sức chứa

**Vì sao đếm rồi ghi là sai:** hai request cùng đếm thấy còn 2 chỗ, cùng ghi 2 người, thành 4/2. Transaction một mình không giải quyết được vì hai transaction không ghi vào cùng document.

**Giải pháp:** collection `AmenitySlots`, mỗi slot một document, tăng số đã dùng bằng update có điều kiện:

```js
// Unique index: { amenityId: 1, slotStart: 1 }

// Bước 1, ngoài transaction: đảm bảo document slot tồn tại
async function ensureSlot(amenityId, slotStart) {
  try {
    await AmenitySlot.updateOne({ amenityId, slotStart }, { $setOnInsert: { used: 0 } }, { upsert: true });
  } catch (err) {
    if (err.code !== 11000) throw err; // request khác vừa tạo: không sao
  }
}

// Bước 2, trong transaction: chỉ tăng khi còn đủ chỗ
async function reserveSlot({ amenity, slotStart, people }, session) {
  const slot = await AmenitySlot.findOneAndUpdate(
    { amenityId: amenity._id, slotStart, used: { $lte: amenity.capacity - people } },
    { $inc: { used: people } },
    { new: true, session },
  );
  if (!slot) throw new AppError(ERROR_CODES.SLOT_FULL, 'Khung giờ đã đầy');
}

async function bookAmenity(actor, input) {
  // ...kiểm tra 5 điều kiện đầu ở mục 8.1
  await ensureSlot(amenity._id, slotStart);
  try {
    return await withTransaction(async (session) => {
      await reserveSlot({ amenity, slotStart, people }, session);
      const [booking] = await AmenityBooking.create([{
        amenityId: amenity._id, apartmentId, bookedBy: actor._id,
        bookingDate, startTime: slotStart, endTime: slotEnd,
        numberOfParticipants: people,
        status: amenity.requiresApproval ? BOOKING_STATUS.PENDING : BOOKING_STATUS.CONFIRMED,
      }], { session });
      return booking;
    });
  } catch (err) {
    if (err.code === 11000) throw new AppError(ERROR_CODES.BOOKING_DUPLICATE, 'Căn hộ đã đặt khung giờ này');
    throw err;
  }
}
```

Phải bắt `E11000` thành `BOOKING_DUPLICATE` trong service; nếu để lọt, `errorHandler` của Người 1 sẽ trả `CONFLICT` chung với message `Giá trị "apartmentId" đã tồn tại`, khó hiểu với người dùng.

Mọi thao tác **hủy, từ chối** trong cùng một transaction: đổi trạng thái có điều kiện, rồi `$inc: { used: -people }`.

Điều kiện 5 dùng partial unique index:

```js
bookingSchema.index(
  { apartmentId: 1, amenityId: 1, startTime: 1 },
  { unique: true, partialFilterExpression: { status: { $in: ['pending', 'confirmed'] } } },
);
```

### 8.3. API

| UC | API | Quyền | Logic |
|---|---|---|---|
| 35 | `GET/POST/PATCH /amenities`, `PATCH /amenities/:id/deactivate` | `manager` (mọi vai trò xem tiện ích đang mở) | `openTime < closeTime`; `slotDuration > 0`; `capacity ≥ 1` |
| 36 | `GET /amenities/:id/slots?date=YYYY-MM-DD` | Đã đăng nhập | Sinh slot + ghép `used`; trả `{start, end, remaining, available}` |
| 37 | `POST /amenity-bookings` | `resident` | Theo mục 8.2; báo Facility nếu cần duyệt (`booking_submitted`) |
| — | `GET /amenity-bookings/mine` | `resident` | Lịch sử đặt |
| 38 | `GET /amenity-bookings?status=pending` | `staff` + `facility`, `manager` | Hàng chờ |
| 38 | `PATCH /amenity-bookings/:id/approve` | `staff` + `facility` | Điều kiện `pending`; ghi `reviewedBy`; báo cư dân |
| 38 | `PATCH /amenity-bookings/:id/reject` | `staff` + `facility` | Bắt buộc `rejectReason`; trả slot; báo cư dân |
| 39 | `PATCH /amenity-bookings/:id/cancel` | Người đặt | Từ `pending`/`confirmed`; quá hạn → `CANCEL_DEADLINE_PASSED`; trả slot |

**Khi Manager sửa tiện ích:** chỉ áp dụng cho booking mới. Vô hiệu hóa chỉ chặn đặt mới. Giảm `capacity` thì `remaining = max(0, capacity - used)`.

**Job:** mỗi giờ chuyển `confirmed` đã qua `endTime` sang `completed` (không trả slot); `pending` quá giờ → `rejected` với lý do "Hết hạn duyệt".

**Flutter (`lib/features/amenities/`):** Resident (Danh sách tiện ích, Chi tiết + nội quy, chọn ngày + lưới slot, Xác nhận đặt, Booking của tôi, Hủy kèm cảnh báo hạn hủy); Facility (Hàng chờ duyệt); Manager (Quản lý tiện ích). Nhận `SLOT_FULL` thì tải lại lưới slot ngay.

**Thứ tự làm:** model + hàm sinh slot + test → UC-35 → UC-36 → UC-37 + test tranh chấp → UC-38, 39 → job.

**Xong khi:** bắn đồng thời nhiều request vào slot cuối không bao giờ vượt `capacity`; hủy/từ chối trả slot đúng; hạn hủy tính đúng giờ Việt Nam.

**Trạng thái (2026-11-08):** ✅ Code + test xong; chưa chạy thử trên app thật.
- Backend: `models/Amenity.js`, `AmenitySlot.js`, `AmenityBooking.js`; `services/amenity.service.js` (sinh slot theo giờ VN), `services/amenityBooking.service.js` (giữ chỗ theo mục 8.2, đổi trạng thái + trả chỗ trong cùng transaction); routes `/amenities`, `/amenity-bookings`; job hoàn thành / hết hạn duyệt trong `jobs/index.js`; hook chuyển đi hủy booking tương lai và trả chỗ (thay `TODO(M6)`); seed 4 tiện ích mẫu.
- Booking **chụp lại `cancelDeadlineHours` lúc đặt** để Manager sửa tiện ích không ảnh hưởng booking cũ.
- Chỉ nhân viên Facility duyệt / từ chối; Manager xem hàng chờ. Chỉ **người đặt** hủy được (thành viên cùng căn xem được nhưng không hủy).
- Flutter: `features/amenities/` — Tiện ích (danh sách, Manager thêm / sửa / tạm ngưng), Chi tiết + chọn ngày (14 ngày tới hoặc lịch 30 ngày) + lưới slot + đặt, Lịch đặt của tôi, Duyệt đặt tiện ích, Chi tiết lượt đặt (Duyệt / Từ chối / Hủy kèm hạn hủy).
- Test: backend 165/165 (M6: 18 test — 8 căn tranh slot còn 3 chỗ → đúng 3 thành công, nhóm nhiều người tranh chỗ cuối, rollback khi đặt trùng, trả chỗ khi hủy / từ chối, quá hạn hủy, chụp quy định, job, hook), Flutter 39/39.

---

## 9. Giai đoạn 5–6: M7 và M9

### 9.1. Nhiệm vụ vận hành (UC-41, 42)

Nhiệm vụ do Manager tự tạo, không có cư dân nghiệm thu.

**Trạng thái:** `assigned → in_progress → completed`, `assigned/in_progress → cancelled`. Tái dùng `assertAssignable` (theo `department` enum) và `RequestHistory` (điền `taskId`).

| UC | API | Quyền | Logic |
|---|---|---|---|
| 41 | `POST /tasks` | `manager` | Sinh `taskCode`; một người chịu trách nhiệm chính; báo nhân viên (`task_assigned`) |
| 41 | `PATCH /tasks/:id/reassign` | `manager` | Bắt buộc lý do; lưu lịch sử; báo cả người cũ và mới |
| 41 | `PATCH /tasks/:id/cancel` | `manager` | Bắt buộc lý do |
| 31 | `PATCH /tasks/:id/start`, `/complete` | `staff` + người được giao | Điều kiện trạng thái; ghi `completedAt` |
| 42 | `GET /tasks/history?staffId=&status=&overdue=&from=&to=` | Manager: tất cả. Staff: chỉ của mình | Staff truyền `staffId` khác thì bỏ qua |
| 42 | `GET /tasks/:id/history` | Theo dữ liệu | Timeline |

**Gộp UC-31:** `GET /me/assignments` trả cả phiếu và nhiệm vụ, thêm `kind: 'request' | 'task'`. Staff chỉ cần một màn "Việc của tôi".

**Flutter (`lib/features/tasks/`):** Manager (Danh sách có lọc, Tạo/Giao, Chuyển người); Staff (bổ sung vào Việc của tôi, Lịch sử việc).

### 9.2. Dashboard vận hành (UC-47)

`GET /dashboard/operations?from=&to=` — `manager`.

| Chỉ số | Cách tính |
|---|---|
| Căn hộ có người ở | Đếm `Apartment.status = occupied` trên tổng (Người 1 đã tự cập nhật qua `recomputeStatus`) |
| Phiếu theo trạng thái | `$group` theo `status`, lọc `createdAt` |
| Phiếu quá hạn | `deadline < now`, chưa xong |
| Lượt đặt tiện ích | `$group` theo tiện ích và trạng thái |
| Nhiệm vụ đang mở, quá hạn | Như phiếu |
| Xe và khách chờ xử lý | Xe `pending`, khách `expected` hôm nay |

Bấm vào một số mở màn danh sách với đúng bộ lọc → các API danh sách phải hỗ trợ cùng tham số.

### 9.3. Báo cáo hiệu suất (UC-48, phần của bạn)

`GET /reports/staff-performance?from=&to=&department=` — `manager`.

| Chỉ số | Định nghĩa |
|---|---|
| Số việc được giao | Sự kiện giao trong khoảng, gồm phiếu và nhiệm vụ |
| Số việc hoàn thành | Phiếu: `firstFinishedAt`. Nhiệm vụ: `completedAt` |
| Tỷ lệ đúng hạn | Hoàn thành trước deadline / tổng hoàn thành |
| Thời gian xử lý trung bình | Từ lúc giao tới lúc hoàn thành |
| Điểm đánh giá trung bình | `rating` của phiếu `closed` |
| Số lần bị mở lại | Đếm lịch sử action `reopen` |

**Hai bẫy:** tính đúng hạn theo **lúc nhân viên báo xong**, không theo `closedAt`; không có dữ liệu trả `null` (app hiển thị "—", dùng mặc định `empty = '—'` giống `formatDate` của Người 1).

**Flutter (`lib/features/dashboard/`):** thêm `fl_chart`. Thống nhất widget thẻ chỉ số và biểu đồ với Người 1 vì họ làm báo cáo tài chính — đề xuất đặt widget chung ở `lib/core/widgets/charts.dart`.

---

## 10. Kiểm thử và demo

### 10.1. Test bắt buộc (Jest + Supertest, theo mẫu `tests/*.test.js` của Người 1)

Dùng `setupDb`, `createUser`, `bearer` từ `tests/helpers.js`. Mỗi file một module: `serviceRequests.test.js`, `vehicles.test.js`, `visitors.test.js`, `amenities.test.js`, `tasks.test.js`, `reports.test.js`.

| Nhóm | Test case |
|---|---|
| Máy trạng thái | Mọi cặp hành động/trạng thái sai trả 409 `INVALID_STATE`, đúng thì có lịch sử |
| Tranh chấp | N request vào slot còn 1 chỗ → đúng 1 thành công; check-in đồng thời → 1; duyệt đồng thời 2 xe trùng biển → 1 |
| Phân quyền | Cư dân A không xem/sửa được dữ liệu căn B; Staff không cập nhật phiếu người khác; Security không duyệt được booking; Staff truyền `staffId` khác không xem được |
| Biển số | `30A-123.45` trùng `30a12345`; xe `inactive` đăng ký lại được |
| Slot | Hủy, từ chối trả đúng số chỗ; đúng và quá hạn hủy; ngày theo giờ VN |
| Báo cáo | Seed cố định cho số khớp tính tay; không có dữ liệu trả `null` |
| Hook với Người 1 | `moveOut` cư dân cuối cùng → xe `inactive`, khách `cancelled`, booking trả slot; khóa staff còn việc → 409 `HAS_OPEN_WORK` |

Flutter: widget test theo mẫu `test/helpers/fake_api.dart` của Người 1, cho form Tạo phiếu, Đăng ký xe và hiển thị nút theo trạng thái.

### 10.2. Kịch bản demo

1. **Sửa chữa:** Cư dân gửi phiếu kèm ảnh → Manager giao Technical → Staff xử lý, báo xong → cư dân yêu cầu làm lại → Staff xử lý lại → nghiệm thu 5 sao → xem timeline.
2. **Xe:** Cư dân đăng ký xe → Security duyệt → hồ sơ thứ hai trùng biển bị chặn → xe xuất hiện trong bảng phí của Người 1.
3. **Khách:** Cư dân tạo lịch → Security tìm theo mã, check-in → cư dân nhận thông báo (chuông của Người 1) → check-out.
4. **Tiện ích:** Hai cư dân tranh slot cuối → một người bị báo đầy → người kia hủy → slot trống lại.
5. **Quản lý:** Manager giao nhiệm vụ, chuyển người → mở dashboard → bấm số quá hạn → xem báo cáo hiệu suất.

### 10.3. Tiêu chí hoàn thành một UC

- [ ] API có validate Zod, đủ 3 lớp quyền, trả đúng mã lỗi trong `ERROR_CODES`
- [ ] Đổi trạng thái có điều kiện và có lịch sử (nếu áp dụng)
- [ ] Gửi thông báo đúng người, `type` đã ghi vào README
- [ ] Màn hình có loading, lỗi (`ErrorView`), rỗng
- [ ] Có test cho logic chính và trường hợp sai quyền
- [ ] Đã chạy thử trên app bằng đúng vai trò đó

---

## 11. Nếu thiếu thời gian

| Mức | Nội dung |
|---|---|
| **Bắt buộc** | M5 đầy đủ (P0), UC-40 bản rút gọn |
| **Nên có** | M3, M6 (P1) |
| **Có thể rút gọn** | UC-41/42 chỉ tạo, giao, hoàn thành. Dashboard chỉ thẻ số |
| **Cắt đầu tiên** | Job tự đóng (dùng nút thủ công), job dọn `pending`, ảnh sau xử lý, báo cáo theo bộ phận |

**Không cắt:** phân quyền theo dữ liệu, điều kiện trạng thái, lịch sử phiếu, chống vượt sức chứa.

---

## 12. Git và phối hợp

- Làm trên nhánh `Viet`, mỗi đầu ngày cập nhật từ `main`.
- **File dùng chung dễ conflict** — chỉ **thêm dòng**, không sửa/xếp lại dòng của Người 1, và báo trước:
  - `backend/src/routes/index.js` (thêm khối `// M3`, `// M5`, `// M6`, `// M7`, `// M9`)
  - `backend/src/utils/constants.js`, `backend/src/utils/errors.js`
  - `backend/src/app.js` (static `/uploads`), `backend/src/server.js` (khởi job)
  - `backend/src/scripts/seed.js`, `backend/tests/helpers.js`
  - `lib/core/router/app_router.dart`, `lib/features/home/home_page.dart`, `lib/core/network/api_client.dart`
- Đổi schema dùng chung (`Vehicle`, `User`) thì báo Người 1 và cập nhật ERD.
- Không commit `.env`, `node_modules`, `uploads/`.
- Commit nhỏ theo UC, ví dụ `feat(service-request): UC-30 assign request`.

### Việc làm ngay

1. [x] Chốt quyết định 2.2 #8–#10.
   [ ] Báo Người 1 các mục **[Cần N1]**: hai hook `onResidentMovedOut`, `assertNoOpenWork` và các file dùng chung sẽ thêm dòng.
2. [ ] Thêm `mongodb-memory-server`, chạy được `npm test` hiện có của Người 1 trên máy mình.
3. [ ] Tạo MongoDB Atlas M0 cho dev/demo, chia sẻ connection string qua kênh riêng.
4. [ ] Cập nhật ERD: bỏ `Departments`/`Residents` theo code, thêm `rejected`, `waitingSince`, `AmenitySlots`.
5. [ ] Làm Giai đoạn 0 (phần bổ sung) rồi UC-40.
