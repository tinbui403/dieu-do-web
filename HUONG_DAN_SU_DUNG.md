# HƯỚNG DẪN SỬ DỤNG — Zadam Điều Độ

> Hệ thống quản lý điều phối container xuất khẩu (Zadam / Đại Cát Lâm).
> Tài liệu này dành cho **người dùng cuối** (team). Đọc theo vai trò của mình ở Phần 6.

Cập nhật: 27/09/2026

---

## 1. Dự án này là gì?

Zadam Điều Độ là web quản lý toàn bộ vòng đời một **container hàng xuất**: từ lúc khách đặt hàng → xin booking hãng tàu → xếp lô → gọi cont rỗng → đóng hàng ở kho → kéo về bãi/cảng → kiểm dịch, thanh lý → lên tàu.

Mục tiêu: mọi người (Quản lý, Điều độ, CSKH, Nhà xe) nhìn **cùng một bảng dữ liệu thời gian thực**, biết chính xác cont nào đang ở bước nào, lô nào sắp tới hạn cắt máng (closing), booking nào thiếu/thừa cont — và có **trợ lý AI** để hỏi nhanh + thao tác bằng lời.

**Ba khái niệm cốt lõi:**

- **Booking** = chỗ đặt trên tàu do hãng cấp (số booking, hãng tàu, tên tàu, cảng đến, ETD, ETA, số cont được cấp). Một booking có thể dùng cho **nhiều lô**.
- **Lô** = một đơn hàng của **một khách**, gắn vào một booking. Lô mang thông tin cắt máng (closing), kiểm dịch, thanh lý.
- **Container (cont)** = từng thùng cont cụ thể, chạy qua **6 bước trạng thái** (xem Phần 5). "Đơn hàng mới" khi chưa xếp kế hoạch chính là một cont ở bước 1 "Đơn chờ lên".

**Luồng chuẩn:** Đơn hàng mới → tìm/tạo booking → tạo lô → gán cont vào lô → gọi rỗng, đóng hàng → kéo về bãi/cảng → kiểm dịch/thanh lý → lên tàu.

---

## 2. Đăng nhập

Mở web (địa chỉ team dùng chung) → đăng nhập bằng email + mật khẩu do **Quản lý** cấp. Góc dưới trái hiện tên + vai trò của bạn, có nút **Đổi mật khẩu** và **Đăng xuất**.

Giao diện hỗ trợ **Tiếng Việt / 中文 / VI+中** (đổi ở góc dưới trái), tự động sáng/tối theo máy.

---

## 3. Các vai trò & quyền

| Việc | Quản lý | Điều độ | CSKH | Nhà xe | Chỉ xem |
|---|:---:|:---:|:---:|:---:|:---:|
| Xem toàn bộ dữ liệu | ✅ | ✅ | ✅ | Phần của mình | ✅ |
| Tạo/sửa đơn, booking, lô, cont | ✅ | ✅ | ✅ | — | — |
| Xếp lô, chạy gợi ý điều phối, duyệt gợi ý | ✅ | ✅ | — | — | — |
| Kiểm dịch, đổi mã lô, bãi tạm, giá cước | ✅ | ✅ | — | — | — |
| Quản lý Kho | ✅ | — | ✅ | — | — |
| Quản lý Danh mục (khách, cảng, hãng, nhà xe…) | ✅ | ✅ | ✅ | — | — |
| Quản lý Nhân viên, phân quyền | ✅ | — | — | — | — |
| Xoá lô / booking (kể cả hàng loạt) | ✅ | — | — | — | — |
| Bật/tắt quyền AI cho từng người | ✅ | — | — | — | — |
| Dùng AI hỏi đáp | tuỳ QL bật | tuỳ QL bật | tuỳ QL bật | — | — |
| Dùng AI thao tác (ghi dữ liệu) | tuỳ QL bật | tuỳ QL bật | — | — | — |

Ghi chú: **Nhà xe** là tài khoản gắn với một nhà xe cụ thể, chủ yếu để theo dõi phần cont của mình. **Chỉ xem** chỉ đọc, không sửa được gì.

---

## 4. Các màn hình chính

- **Tổng quan** — bảng điều khiển: số liệu nhanh, lô sắp tới hạn cắt máng, cảnh báo.
- **Điều phối** — nơi máy **gợi ý** ghép cont rỗng ↔ cont đầy, chọn nhà xe. Bấm **"Chạy lại gợi ý"** để tính lại. Điều độ **duyệt** gợi ý để áp dụng.
- **Lô / Booking** — hai tab: danh sách **Lô** và danh sách **Booking**. Tạo/sửa booking (kể cả **đọc PDF booking bằng AI**), tạo lô, xem closing, kiểm dịch, thanh lý. Quản lý có nút **xoá booking/lô đã chọn** và **xoá toàn bộ**.
- **Container** — tất cả cont, lọc theo trạng thái (Đơn chờ lên / Đang đóng hàng / Đầy chờ kéo / Ở bãi tạm…), theo kho, khách, cảng, lô. Có nút **"Tạo đơn hàng"**. Mở một cont để xem/sửa chi tiết và **chuyển bước**.
- **Kiểm dịch** — theo dõi cont cần kiểm dịch, đã/chưa kiểm dịch.
- **Hạ cảng** — cont đã/đang hạ về cảng.
- **Lô có sự cố** — các lô đang gặp vấn đề cần xử lý.
- **Tìm cont** — tra nhanh theo số cont / seal / lô / mã đơn / kho / khách.
- **Danh mục** — khách hàng, kho, cảng đến, cảng hạ, hãng tàu, bãi tạm, nhà xe, nhân viên, cấu hình.

Ô **Tìm** ở góc trên phải (Tìm cont, seal, lô, mã đơn…) dùng được ở mọi màn.

---

## 5. Trạng thái container (6 bước)

| Bước | Tên | Ý nghĩa |
|:---:|---|---|
| 1 | **Đơn chờ lên** | Đơn hàng mới / chờ gọi cont rỗng. Chưa cần có số cont. |
| 2 | **Đang đóng hàng** | Cont đã về kho, đang đóng hàng. |
| 3 | **Đầy chờ kéo** | Đóng xong, chờ xe kéo đi. |
| 4 | **Ở bãi tạm** | Đã kéo về bãi tạm (vd HLS = Hoàng Liên Sơn). |
| 5 | **Đã hạ cảng** | Đã hạ container xuống cảng. |
| 6 | **Đã lên tàu** | Hoàn tất. |
| 9 | **Hủy / đổi cont** | Cont bị huỷ hoặc đổi sang cont khác (giữ lịch sử). |

Mở một cont → bấm nút **"Chuyển bước tiếp →"** để đẩy sang bước sau. Một số bước cần đủ điều kiện mới cho chuyển (hệ thống sẽ báo nếu còn thiếu).

Phân biệt quan trọng: **Kho** = nơi đóng hàng (vd kho chị Kiều) ≠ **Bãi tạm** = nơi hạ cont tạm (vd HLS) ≠ **Cảng đến** = cảng nước ngoài.

---

## 6. Hướng dẫn theo vai trò

### 6.1. CSKH (chăm sóc khách hàng)
Việc chính: **nhận đơn hàng của khách và tạo đơn trong hệ thống**.
1. Vào **Container** → **"Tạo đơn hàng"**.
2. Có thể dán nguyên tin nhắn khách (Zalo/WeChat) vào ô **"Lọc từ tin nhắn khách"** → bấm **"Lọc & điền vào form"** để máy tự điền mã đơn, khách, kho, số lượng, cảng/ngày tàu yêu cầu. Kiểm tra rồi **Lưu**.
3. Đơn tạo ra là cont **"Đơn chờ lên"** — điền sẵn **Yêu cầu tàu** (cảng đến / ngày tàu / hãng tàu khách muốn) để Điều độ tìm booking phù hợp.
4. CSKH cũng quản lý **Kho** và **Danh mục**. Không xếp lô, không đổi mã lô (việc của Điều độ).

### 6.2. Điều độ (ĐĐ)
Việc chính: **biến đơn hàng thành kế hoạch chạy**.
1. Vào **Container → Đơn chờ lên** → mở đơn → xem **Yêu cầu tàu** (cảng/ngày tàu) → bấm **"Tìm booking"** để ghép vào booking phù hợp, hoặc tạo lô mới.
2. Vào **Lô/Booking** để tạo/sửa booking (có thể **đọc PDF booking bằng AI**, xem Phần 7), điền closing, kiểm dịch.
3. Vào **Điều phối** → **"Chạy lại gợi ý"** để máy đề xuất ghép rỗng–đầy + nhà xe → **duyệt** gợi ý tốt.
4. Theo dõi lô **sắp tới hạn cắt máng (closing)** ở Tổng quan / danh sách Lô để không trễ tàu.
5. Cập nhật trạng thái cont qua các bước, gán nhà xe, kiểm dịch, thanh lý.

### 6.3. Quản lý (QL)
Làm được **tất cả** của ĐĐ và CSKH, cộng thêm:
- **Nhân viên**: tạo tài khoản, đặt vai trò, đổi mật khẩu người khác (Danh mục → Nhân viên).
- **Phân quyền AI**: bật/tắt cho từng người quyền **💬 hỏi đáp** và **🤖 thao tác** (xem Phần 7).
- **Xoá dữ liệu**: xoá booking/lô đã chọn, hoặc **xoá toàn bộ** để nạp lại (nút bấm 2 lần chống lỡ tay). Dùng cẩn thận — xoá là vĩnh viễn.
- **Dọn nhật ký cũ** (tab Dọn dữ liệu): xoá log thay đổi cũ hơn 30 ngày.

### 6.4. Nhà xe
Tài khoản gắn với một nhà xe — theo dõi các cont được giao cho mình, biết cần kéo cont nào, đi kho nào. Không sửa dữ liệu điều phối.

### 6.5. Chỉ xem
Chỉ đọc — dùng cho người cần nắm thông tin nhưng không thao tác.

---

## 7. Trợ lý AI

Hệ thống có **chatbot AI** (nút 🤖 nổi góc màn) và tính năng **đọc PDF booking**. AI hiểu tiếng Việt lẫn nghiệp vụ (cắt máng = CLS = cut-off = closing…).

### 7.1. Hai mức quyền AI (do Quản lý bật)
- **💬 Hỏi đáp**: AI tra cứu và trả lời (không thay đổi dữ liệu).
- **🤖 Thao tác**: AI được **ghi dữ liệu** (tạo đơn, tạo booking…). Chỉ cấp cho Quản lý / Điều độ.

Quản lý bật/tắt tại **Danh mục → Nhân viên**, mỗi người có 2 công tắc 💬 và 🤖. Không có quyền hỏi đáp thì nút 🤖 sẽ ẩn.

### 7.2. AI hỏi đáp làm được gì
Cứ hỏi tự nhiên, ví dụ:
- "Có lô nào quá hạn cắt máng chưa?" → AI liệt kê kèm số giờ trễ.
- "Kho chị Kiều còn cont nào Đầy chờ kéo?" / "Cont ở bãi HLS chưa kiểm dịch?"
- "Booking nào đang thiếu cont?" / "Cont nào gấp cần kéo?"
- "Đơn HX 09197 yêu cầu tàu ngày nào?" → AI trả cảng/ngày tàu yêu cầu của đơn.
- "Gợi ý booking cho đơn đi Thượng Hải ngày 02/10."

AI **luôn kèm số liệu cụ thể**, không trả lời chung chung kiểu "yên tâm". Nếu không có công cụ phù hợp, AI **nói thật và hỏi lại** chứ không bịa.

### 7.3. AI thao tác (ghi dữ liệu) — có xác nhận
Người có quyền 🤖 có thể ra lệnh, ví dụ:
- "Tạo đơn hàng cho khách HENG XING, kho chị Kiều, 2 cont, đi SHA ngày 02/10."
- "Thêm booking này…", "Tạo lô…", "Thêm 3 cont vào lô 614A", "Đổi trạng thái cont ABCU1234567 sang Đầy chờ kéo", "Điều xe Khánh Linh kéo các cont…".

**Quan trọng:** trước khi ghi, AI luôn hiện **BẢNG XÁC NHẬN** tóm tắt những gì sắp lưu. Bạn phải bấm **"Đồng ý lưu"** thì mới ghi thật; bấm **"Huỷ"** thì không có gì thay đổi. Hãy đọc kỹ bảng này trước khi đồng ý.

### 7.4. Đọc PDF booking bằng AI
Trong form **Booking mới** (Lô/Booking → Thêm booking) có mục **"Đọc PDF booking bằng AI"**:
1. Bấm **Chọn tệp** → chọn file booking confirmation (PDF, ≤ 8 MB).
2. AI trích **số booking / hãng / tàu / chuyến / cảng / ETD / ETA / số cont / ghi chú** và **điền sẵn vào form**.
3. **Bạn kiểm tra lại** rồi bấm **Lưu**. File PDF **không được lưu lại** trên hệ thống.

Lưu ý: tốc độ đọc PDF **lúc nhanh lúc chậm** (phụ thuộc dịch vụ AI). Nếu chậm cứ chờ; nếu báo lỗi thì thử lại.

---

## 8. Mẹo & lưu ý

- **Cập nhật thời gian thực**: dữ liệu tự làm mới, nhiều người thao tác cùng lúc đều thấy như nhau.
- **Cắt máng (closing)**: ưu tiên xử lý lô gần tới hạn trước để không trễ tàu. Hệ thống tô màu cảnh báo.
- **Kho ≠ Bãi tạm ≠ Cảng đến** — đừng nhầm khi lọc/hỏi AI.
- **Xoá dữ liệu** (chỉ QL): không hoàn tác được. Chỉ xoá khi chắc chắn (vd làm trống để nạp lại đầu kỳ).
- **Nạp dữ liệu từ Excel**: có công cụ riêng cho người kỹ thuật (`tools/nap_excel.py`) — xem file hướng dẫn kỹ thuật hoặc hỏi người phụ trách.
- Gặp lỗi hoặc AI trả sai: báo lại để được chỉnh; AI đang được cải thiện liên tục.
