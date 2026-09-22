# TIẾN ĐỘ — file bàn giao giữa các phiên làm việc

> **Dành cho Claude (bất kỳ tài khoản / phiên nào):** đọc `README.md` trước để hiểu hệ thống, rồi đọc file này để biết đang dở ở đâu. Xong mỗi mốc thì **cập nhật lại file này** (mục "Đang làm", "Bước kế tiếp", "Nhật ký phiên") trước khi dừng.

Cập nhật lần cuối: **22/09/2026** (giờ VN)

## Đang làm

**ĐÃ CHỐT Phase 1→4 vào bản thật — `index.html` đã build lại và tự chứa, chạy được.**
- `src/app.src.html` = bản mới (Glassmorphism Blue + Workflow Hub + KD inline + Container Board).
- `src/kiem_dich_wizard.js` = bản wizard INLINE (đã thay bản drawer cũ).
- `build.py` = nâng cấp: nhúng cả supabase LẪN `kiem_dich_wizard.js` vào `index.html` (index.html giờ tự chứa, không phụ thuộc file ngoài).
- `index.html` = đã build từ bộ trên, test V8 không lỗi cú pháp, `KD_WIZARD`/`vBoard`/`vWorkflowHub`/`vKD` đều nạp OK.
- ⏳ **Chưa git push** — cần đẩy lên GitHub (tinbui403@gmail.com) từ máy local.

## Bước kế tiếp

1. **Mở `index.html`** (double-click hoặc qua server) → đăng nhập Supabase như thường để kiểm tra bản mới trên dữ liệu thật.
2. **Đẩy lên GitHub** (chạy trên máy local):
   ```
   cd "E:\kiểm dịch\Claude outputs\điều độ"
   git add -A
   git commit -m "UI redesign: Glassmorphism Blue + Workflow Hub + KD inline + Container Board"
   git push origin master
   ```
3. (Tuỳ chọn) Dọn các file nháp không còn cần: `src/app.src.PHASE1/2/3/4.html`, `src/kiem_dich_wizard.PHASE3.js`, `prototype_glassmorphism.html`, `XEM_THU_PHASE4.html` — nội dung đã gộp vào bản thật. (Chưa xoá vì chưa được yêu cầu.)
4. (Tuỳ chọn) Phase 5 — polish responsive + quét nốt vài màu tím còn sót trong biểu đồ **Tổng quan** (`vTong`: area/donut/heatmap/bar).

## Việc còn treo (chưa ai yêu cầu làm, chỉ ghi để nhớ)

- Biểu đồ màn **Tổng quan** (`vTong`) vẫn còn vài hex màu tím hardcode (area/donut track/heatmap/bar). Status pill / clChip / TYPES / MUC đã đổi blue.
- `canh_bao_thieu_rong()` có trong DB nhưng web chưa gọi.
- Hàm cũ `tao_goi_y()` giữ để đối chiếu, không còn được gọi. Chưa quyết định xoá.
- Cấu hình "Chế độ thử: cho xoá dữ liệu đã chạy": khi chạy chính thức phải đổi thành **Tắt**.

## Đã xong gần đây

- **22/09 (Account 2 · redesign)** — **CHỐT Phase 1→4 vào bản thật**: gộp PHASE4 → `src/app.src.html`; wizard inline → `src/kiem_dich_wizard.js`; nâng cấp `build.py` (nhúng cả supabase + wizard); build lại `index.html` (tự chứa, test V8 OK).
- **22/09 (Account 2)** — **Phase 4 Container Board**: gộp Tại kho + Bãi thành 1 tab **Container** (filter TT; TT4 giữ bảng chi phí bãi). Hạ cảng giữ riêng. Tách `taiKhoBody`/`baiBody`, thêm `vBoard`, state `S.boardSeg`.
- **22/09 (Account 2)** — **SỬA 2 lỗi cú pháp chí mạng** trong `vWorkflowHub` (phiên trước) khiến PHASE1/2/3 trắng màn hình + thêm icon/nhãn `workflow`. Đổi màu status (`ST`/`clChip`/`MUC`/`TYPES`) tím → blue.
- **22/09 (Account 2)** — **Phase 3 KD inline** (drawer → form inline 3 bước). **Phase 2 Glassmorphism Blue** (CSS). **Phase 1 Workflow Hub** (`vWorkflowHub`).
- **22/09** — KD Wizard 3-step bản drawer (đã bị thay bằng bản inline).
- **21/09** — Gợi ý v3 (`tao_goi_y_v3`, `canh_bao_thieu_rong`), test 19/19.
- **20/09** — Quy trình KD→kéo→hạ cảng chặn bằng trigger; CLS ePort gộp Cát Lái + SPITC.

## Quy ước — đừng làm sai

- **Không sửa trực tiếp `index.html`.** Sửa `src/app.src.html` (và `src/kiem_dich_wizard.js` nếu cần) rồi chạy `python build.py`.
- `build.py` giờ nhúng cả supabase + wizard vào index.html → **index.html tự chứa** (mở ở đâu cũng chạy, không cần file js ngoài).
- Thay đổi DB = **thêm file migration mới** trong `supabase/migrations/`, không sửa migration cũ.
- Sửa hàm gợi ý / quy tắc KD xong phải chạy lại `tests/kiem_thu_goi_y_v3.sql` và `tests/kiem_thu_kd.sql`.
- Không đưa lên GitHub: dữ liệu thật, Excel, mật khẩu, mã sao lưu, token KDTV, `service_role` key.
- **Sau khi sửa `<script>` inline, phải test tải app** (lỗi cú pháp làm trắng màn hình mà không báo gì rõ).

## Nhật ký phiên

| Ngày | Tài khoản / phiên | Đã làm |
|---|---|---|
| 22/09/2026 | Cowork (Account 2 · redesign) | **CHỐT Phase 1→4 vào bản thật**: app.src.html + kiem_dich_wizard.js (inline) + build.py (nhúng wizard) + rebuild index.html (tự chứa, test V8 OK). Cập nhật TIEN_DO. Chưa git push. |
| 22/09/2026 | Cowork (Account 2 · redesign) | Phase 4 Container Board + sửa 2 lỗi cú pháp vWorkflowHub (PHASE1/2/3 trắng màn hình) + đổi màu status→blue. Test headless OK. |
| 22/09/2026 | Cowork (Account 2 · redesign) | Phase 3 KD inline, Phase 2 Glassmorphism Blue + prototype, Phase 1 Workflow Hub. |
| 22/09/2026 | Cowork | KD Wizard drawer, rebuild index.html, commit `5e19aff`. |
| 21/09/2026 | Cowork | Đọc lại dự án, tạo `TIEN_DO.md`. |
