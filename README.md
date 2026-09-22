# Điều độ 调度 — cont chuối Đại Cát Lâm

Trang web điều độ container chuối: theo dõi cont tại kho, bãi tạm, kiểm dịch, lô/booking và **gợi ý kế hoạch** (đổi rỗng, cắt rỗng + kéo đầy, rút mooc) tự động mỗi giờ. Giao diện song ngữ Việt / 中文, dùng được trên điện thoại.

- Giao diện: **một file `index.html`** (HTML + JS thuần, không cần cài đặt), mở trực tiếp bằng trình duyệt hoặc đưa lên GitHub Pages / Netlify.
- Dữ liệu + đăng nhập + phân quyền: **Supabase** (Postgres). Dự án Supabase: `cgfcbxsyjtdlligpdzbp`.

## Cấu trúc thư mục

| Đường dẫn | Là gì |
|---|---|
| `index.html` | Bản chạy thật (đã nhúng sẵn thư viện supabase-js). **Đây là file mở ra để dùng.** |
| `src/app.src.html` | Mã nguồn giao diện — sửa ở đây, rồi chạy `build.py` để tạo lại `index.html`. |
| `vendor/supabase.js` | Thư viện `@supabase/supabase-js` 2.116.0 (bản UMD). |
| `build.py` | Ghép `src/app.src.html` + `vendor/supabase.js` → `index.html` (và `tests/test.html` nếu có dữ liệu thử). |
| `supabase/migrations/` | Toàn bộ lệnh SQL đã chạy trên Supabase theo thứ tự: bảng, quyền (RLS), view, hàm `tao_goi_y_v3()`, lịch chạy mỗi giờ. |
| `supabase/seed.sql` | Dữ liệu khởi tạo tối thiểu: 7 trạng thái cont, tham số gợi ý, tài khoản quản lý đầu tiên. |
| `tests/` | Kiểm thử tự động bằng Playwright với dữ liệu giả (`mock.js`). |

## Sửa giao diện

1. Sửa `src/app.src.html`.
2. Chạy `python build.py` → được `index.html` mới.
3. (Tuỳ chọn) Kiểm thử: `python tests/run_test.py` — cần `pip install playwright` và file `tests/fixtures.json` (dữ liệu thật, không đưa lên GitHub).

## Cài lại từ đầu trên một dự án Supabase mới

1. Chạy lần lượt các file trong `supabase/migrations/` (SQL Editor của Supabase hoặc `supabase db push`).
2. Chạy `supabase/seed.sql`.
3. Nhập danh mục (kho, nhà xe, khách hàng, hãng tàu, cảng…) và dữ liệu cont/lô.
4. Trong `src/app.src.html` đổi `SUPABASE_URL` và `SUPABASE_KEY` (publishable key) sang dự án mới, rồi chạy `build.py`.
5. Supabase → Authentication → Sign In / Providers → Email: **tắt "Confirm email"** (quyền truy cập đã do bảng `nhan_vien` kiểm soát).

## Phân quyền

Chỉ email có trong bảng `nhan_vien` (đang hoạt động) mới đọc được dữ liệu. Vai trò:

- **Quản lý**: toàn quyền, sửa danh mục và nhân viên, xoá dữ liệu.
- **Điều độ**: sửa cont/lô, chạy và duyệt gợi ý.
- **CSKH**: sửa cont/lô.
- **Nhà xe**, **Chỉ xem**: chỉ đọc.

## Quản lý chặt (hướng ERP)

- **Nhật ký thay đổi** (`nhat_ky`): mọi thêm / sửa / xoá trên lô, cont, danh mục, nhân viên, cấu hình và việc duyệt gợi ý đều được ghi tự động — ai, lúc nào, giá trị cũ → mới. Không ai sửa hay xoá được nhật ký qua web. Xem ở từng lô/cont ("Xem lịch sử thay đổi") hoặc Danh mục → Nhật ký thay đổi (Quản lý).
- **Hủy lô** (`huy_lo`): Quản lý / Điều độ, bắt buộc ghi lý do; lô bị ẩn, đơn chưa chạy chuyển "Hủy", gợi ý liên quan bị bỏ; **khôi phục được** (`khoi_phuc_lo`). Lô đã hủy không nhận đơn mới.
- **Xoá hẳn** (`xoa_lo`, `xoa_cont`): chỉ Quản lý, chỉ khi chưa có cont chạy thực tế (dùng cho nhập nhầm / nhập thử); bản chụp dữ liệu bị xoá vẫn nằm trong nhật ký.
- Lô có **số lượng cont kế hoạch** (tạo sẵn đơn chờ cắt rỗng khi chọn kho) và **thứ tự tự đặt**; danh sách lô sắp xếp được theo nhiều tiêu chí.

## Sao lưu hằng ngày ra Google Drive

- `sao-luu/SaoLuuSupabase.gs`: Google Apps Script chạy mỗi tối (23h–24h giờ VN), gọi hàm `sao_luu_du_lieu` trên Supabase và lưu vào thư mục Drive **"Sao lưu Supabase"**:
  - Google Sheet **"Sao lưu Supabase dd-MM-yyyy"** — mỗi bảng một trang, xem được / tải về Excel.
  - File **"Sao lưu Supabase dd-MM-yyyy.json"** — bản đầy đủ để khôi phục chính xác.
- Hàm `sao_luu_du_lieu(p_ma)` chỉ trả dữ liệu khi đúng mã bí mật (Supabase chỉ lưu mã băm SHA-256). Mã thật **không** nằm trong repo — trong file .gs là `DIEN_MA_SAO_LUU_VAO_DAY`.
- Cài: dán file vào Apps Script, điền mã, Lưu, chọn hàm `caiDat` → Chạy → cho phép quyền. Script lỗi thì Google tự gửi email báo.

## Đợt 3 (20/09/2026 chiều)

- **Danh mục**: nhà xe thêm/xoá (Quản lý, Điều độ, CSKH); kho thêm/xoá (Quản lý, CSKH); đã có dữ liệu thì "ngưng dùng" thay vì xoá. Nhân viên nghỉ: Quản lý xoá hẳn email + tài khoản. Tab **Bãi tạm** (giá điện/giờ, nâng hạ 1 lần, vận chuyển hạ cảng — Quản lý nhập), **Giá cước nhà xe** (theo khu vực × loại lệnh), **Dọn dữ liệu** (lô lên tàu hết, ETD > 90 ngày, đã sao lưu).
- **CLS**: `closing_mail` (mail), `closing_eport` (tự tra ePort SNP mỗi giờ, cập nhật hàng loạt theo tàu + chuyến), `closing` (nhập tay). CLS máy dùng `cls` = mail → ePort → tay.
- **Gợi ý kế hoạch 4 phương án**: Đóng trong ngày · Đổi rỗng kéo đầy · Cắt mooc · Rút mooc; ưu tiên cont kiểm dịch (về bãi trước CLS 72 giờ), sát CLS (48 giờ), CLS trong 5 ngày; nhà xe theo mooc; chi phí ước tính theo bảng giá cước.
- **Màn hình mới**: Hạ cảng (lô đã kiểm dịch, ở bãi, CLS còn ≤ 72 giờ → chép gửi quản lý bãi); Kiểm dịch có kế hoạch KD; Bãi tạm tính chi phí từng cont + phát sinh (PTI, đổi seal, sửa chữa, lưu bãi, lưu cont, khác).
- **Apps Script** `sao-luu/DongBo.gs`: đồng bộ Mã KDTV từ file PQS NEW mỗi giờ + ghi nhận bản sao lưu.

## CLS ePort: Cát Lái + SPITC (20/09/2026 tối)

- Mỗi giờ (phút :20 gửi, :22 xử lý) hoặc khi bấm **Cập nhật CLS ePort**, hàm `eport_gui_yeu_cau()`:
  - tra từng tàu đang chạy trên **ePort Cát Lái** (`eport.saigonnewport.com.vn/ships/Searcher`, siteId `CTL`);
  - gọi **một lần** lịch tàu **SPITC – Hiệp Phước** (`eport.sp-itc.com.vn/7e47d392…/c4f822fe….xc`, gửi `{from_date, to_date}`, không cần đăng nhập).
- `eport_xu_ly_ket_qua()`: tàu nào Cát Lái không có đúng tàu + chuyến thì tìm trong lịch SPITC. So khớp tên tàu và số chuyến sau khi bỏ dấu cách / chấm / gạch (`ST. MARY` = `ST MARY`, `71/N` = `71N`); số chuyến lấy từ phần cuối của cột Tàu (vd. `CNC PADMA 0HBH8N1NC`).
- CLS lấy cột **SP-ITC COT** (`YARD_CLOSE`) — giờ Việt Nam, đã đổi đúng múi giờ. Cột **ICDs COT** (`BTR`) chưa dùng.
- Cột mới `lo.eport_cang` = `CTL` / `SPITC`: giao diện ghi rõ CLS lấy từ cảng nào; màn **Hạ cảng** dùng cảng này khi lô chưa nhập Cảng hạ.
- Ghi chú đỏ khi không tìm được: "Không tìm thấy tàu trên ePort Cát Lái và SPITC" hoặc "Sai số chuyến (SPITC: …)".
- Migration `20260920090117_cls_eport_spitc.sql` là bản thử đầu (đã bỏ); bản đang chạy là `20260920144957_eport_gop_spitc.sql`.

## Quy trình kiểm dịch → kéo → hạ cảng (20/09/2026 tối)

Chặn ngay trong cơ sở dữ liệu (trigger `private.kiem_tra_cont`, `private.cont_sau_kd`, `private.kiem_tra_lo`) nên không thao tác nào — web, gợi ý hay sửa tay — làm "nhảy" sai được:

1. Mỗi lô chỉ **1 cont kiểm dịch**; đánh dấu cont thứ 2 → báo lỗi, phải bỏ cont cũ trước.
2. Tích **"Lô đã kiểm dịch"** chỉ khi cont KD đang *Ở bãi tạm* tại **HLS / PD / HT** (không DCL, không kiểm ở kho) + lô có **Mã KDTV** + người tích là **Điều độ / Quản lý**. Nút tích chỉ hiện ở nhóm "Sẵn sàng kiểm".
3. Bỏ tích: Điều độ / Quản lý, chỉ khi lô chưa có cont ở cảng / lên tàu.
4. Lô **chưa kiểm dịch** (kể cả lô chưa chọn cont KD) → **không cont nào** được *Đã hạ cảng* / *Đã lên tàu*. Không ngoại lệ.
5. Lô đã KD: cont còn ở kho chỉ **hạ thẳng cảng khi CLS còn ≤ 48 giờ** (Cấu hình "Giờ trước closing hạ thẳng cảng"); còn lại phải hạ bãi.
6. Cont KD bị Hủy / bỏ dấu / đổi sang cont khác / bị xoá → lô tự về **chưa kiểm dịch**.
7. "Cho kéo hạ cảng" = "Lô đã kiểm dịch" (tự động). Về bãi bắt buộc chọn bãi. Lùi trạng thái cont chỉ Quản lý / Điều độ.
8. Web báo đỏ lô **sai quy trình** (có cont ở cảng khi lô chưa KD) ở màn Kiểm dịch, danh sách lô và form lô; liệt kê lô chưa chọn cont KD.

**Gợi ý kế hoạch:** mức gấp *Quá CLS → KD gấp (≤ 72h) → Sát CLS (≤ 48h) → CLS gần (5 ngày) → CLS xa*. Đổi rỗng kéo đầy ghép **cont đầy cùng kho trước**, hết mới sang kho khác cùng khu vực; cont gấp không ghép được thành Rút mooc. Lô chưa KD luôn về bãi (cont KD về HLS / PD / HT); lô đã KD về cảng khi CLS ≤ 48 giờ.

**Chế độ thử:** Cấu hình "Chế độ thử: cho xoá dữ liệu đã chạy" = **Bật** → Quản lý xoá hẳn được lô / cont đã chạy (bản chụp vẫn ở Nhật ký). Chạy chính thức thì đổi thành **Tắt**.

## Gợi ý v3 (21/09/2026)

Lịch mỗi giờ (phút :05) và nút **Chạy gợi ý** trên web nay gọi `tao_goi_y_v3()`. Hàm cũ `tao_goi_y()` giữ nguyên để đối chiếu, không còn được gọi ở đâu.

Nghiệp vụ giữ y hệt bản cũ (4 loại lệnh, mooc riêng từng nhà xe, ngưỡng giờ đọc từ `cau_hinh`, nội dung lệnh song ngữ, chi phí ước tính, nơi hạ). Ba thứ thêm mới:

- **Khoá phiên chạy** (`pg_try_advisory_xact_lock`): cron và người bấm tay không còn chạy đè nhau. Phiên thứ hai trả về `-1`, web hiện "Đang có phiên chạy gợi ý khác".
- **ID gợi ý có giây** (`GY` + 14 số + `-` + 2 số) thay vì chỉ tới phút → hết trùng khoá chính khi chạy 2 lần trong cùng một phút.
- **Cột `goi_y.phien`** (từ `goi_y_phien_seq`): biết dòng gợi ý sinh ra ở lần chạy nào.

Thêm hàm `canh_bao_thieu_rong()` — trả về cont đầy mức *CLS gần* nằm ở khu vực **chưa có rỗng nào**, để điều độ chuẩn bị sớm. Không ghi vào `goi_y` (không duyệt được, sẽ làm rác hàng chờ duyệt) — web gọi riêng nếu muốn hiện.

**Kiểm thử:** `tests/kiem_thu_goi_y_v3.sql` (hoặc `SELECT * FROM kiem_thu_goi_y_v3();`) — dựng 6 tình huống tranh rỗng rồi tự huỷ sạch: 4 cont 4 kho cùng mức 0 · 3 cont mức 0 chung 1 rỗng · mức 0/1/2 cùng kho · cùng kho thắng mức gấp hơn · mức 3 không có rỗng · khác nhà xe giữ mooc. 21/09: **19/19 đạt**.

**Kiểm thử:** `tests/kiem_thu_kd.sql` — dán vào SQL Editor của Supabase → Run: tạo lô thử 123T…130T, chạy 43 tình huống (tích / bỏ tích KD, hạ cảng, lùi trạng thái, hủy cont KD, xoá thử, gợi ý kiểu lô 595 / YUEJIA) rồi **tự huỷ toàn bộ**, kết quả hiện trong thông báo. Giao diện: `python tests/run_test.py`.

## Bảo mật

- `SUPABASE_KEY` trong code là **publishable key** — được phép công khai; dữ liệu được bảo vệ bằng Row Level Security.
- **Không** đưa lên GitHub: file dữ liệu thật (`tests/fixtures.json`, file Excel, file xuất dữ liệu), mật khẩu, `service_role` key. `.gitignore` đã chặn sẵn các file thử nghiệm.
- Nên để repo ở chế độ **Private**.
