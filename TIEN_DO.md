# TIẾN ĐỘ — file bàn giao giữa các phiên làm việc

> **Dành cho Claude (bất kỳ tài khoản / phiên nào):** đọc `README.md` trước để hiểu hệ thống, rồi đọc file này để biết đang dở ở đâu. Xong mỗi mốc thì **cập nhật lại file này** (mục "Đang làm", "Bước kế tiếp", "Nhật ký phiên") trước khi dừng.

Cập nhật lần cuối: **22/09/2026** (giờ VN)

## Đang làm

**Chưa có việc đang làm.**

## Bước kế tiếp

1. Mở trình duyệt, chọn 1 lô có cont tại HLS/PD/HT và nhấn "Kiểm dịch Wizard" để test luồng 3 bước.
2. Nếu có lỗi hiển thị → debug trong console. Nếu lưu bị từ chối DB → kiểm tra RLS/trigger.
3. Push lên GitHub: `git push origin master` (chạy trên máy local, không phải từ Cowork).

## Việc còn treo (chưa ai yêu cầu làm, chỉ ghi để nhớ)

- `canh_bao_thieu_rong()` đã có trong DB nhưng **web chưa gọi** — README ghi "web gọi riêng nếu muốn hiện".
- Hàm cũ `tao_goi_y()` còn giữ để đối chiếu, không còn được gọi ở đâu. Chưa quyết định xoá.
- Cấu hình "Chế độ thử: cho xoá dữ liệu đã chạy": khi chạy chính thức phải đổi thành **Tắt**.

## Đã xong gần đây

- **22/09** — Hoàn thành KD Wizard 3-step: viết lại `kiem_dich_wizard.js` (~175 dòng, thay thế stub cũ), thêm 6 ACT handlers vào `app.src.html`, rebuild `index.html`. Commit `5e19aff`.
- **22/09** — Hoàn thành tích hợp UI Wizard vào `src/app.src.html`, build thành công `index.html`.
- **22/09** — Phân tích quy trình xác thực/phân quyền: Xác nhận người dùng mới cần được Admin thêm vào bảng `nhan_vien` thì mới truy cập được dữ liệu (cơ chế RLS).
- **21/09** — Gợi ý v3: `tao_goi_y_v3()` (khoá phiên, ID có giây, cột `phien`), `canh_bao_thieu_rong()`, `kiem_thu_goi_y_v3()` đạt 19/19; cron phút :05 và nút "Chạy gợi ý" đã chuyển sang v3 (web xử lý kết quả `-1` = đang có phiên khác). `index.html` đã build lại khớp `src/app.src.html`.
- **20/09 tối** — Quy trình kiểm dịch → kéo → hạ cảng chặn bằng trigger; CLS ePort gộp Cát Lái + SPITC.
- **20/09 chiều** — Đợt 3: danh mục, bãi tạm, giá cước, dọn dữ liệu, gợi ý 4 phương án, màn Hạ cảng, đồng bộ Mã KDTV.

## Quy ước — đừng làm sai

- **Không sửa trực tiếp `index.html`.** Sửa `src/app.src.html` rồi chạy `python build.py`.
- Thay đổi DB = **thêm file migration mới** trong `supabase/migrations/` (đặt tên `YYYYMMDDHHMMSS_mo_ta.sql`), không sửa migration cũ đã chạy.
- Sửa hàm gợi ý / quy tắc KD xong phải chạy lại `tests/kiem_thu_goi_y_v3.sql` và `tests/kiem_thu_kd.sql`.
- Không đưa lên GitHub: dữ liệu thật, file Excel, mật khẩu, mã sao lưu, token KDTV, `service_role` key.

## Nhật ký phiên

| Ngày | Tài khoản / phiên | Đã làm |
|---|---|---|
| 22/09/2026 | Cowork | Hoàn thiện KD Wizard: viết lại `kiem_dich_wizard.js` (3 bước đầy đủ), thêm 6 ACT handlers vào `app.src.html`, rebuild `index.html`, commit `5e19aff`. Cần push lên GitHub thủ công. |
| 22/09/2026 | Cowork | Phân tích cơ chế RLS, xác nhận người dùng cần vào bảng `nhan_vien`. Sửa lỗi Realtime subscription, cập nhật UI thông báo cho người dùng mới, build lại `index.html`. Cập nhật `TIEN_DO.md`. |
| 22/09/2026 | Cowork | Phân tích cơ chế RLS, xác nhận người dùng cần vào bảng `nhan_vien`. Lên kế hoạch thêm thông báo lỗi thân thiện. Cập nhật `TIEN_DO.md`. |
| 21/09/2026 | Cowork (phiên đọc lại dự án) | Đọc lại toàn bộ thư mục, xác định đang dở ở bước GitHub, tạo file `TIEN_DO.md` này. Chưa sửa code, chưa commit. |
