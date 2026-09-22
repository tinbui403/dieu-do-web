# TIẾN ĐỘ — file bàn giao giữa các phiên làm việc

> **Dành cho Claude (bất kỳ tài khoản / phiên nào):** đọc `README.md` trước để hiểu hệ thống, rồi đọc file này để biết đang dở ở đâu. Xong mỗi mốc thì **cập nhật lại file này** (mục "Đang làm", "Bước kế tiếp", "Nhật ký phiên") trước khi dừng.

Cập nhật lần cuối: **23/09/2026** (giờ VN, phiên GỘP NHÁNH: port Gợi ý v4 vào bản redesign)

## ⚠ ĐỌC TRƯỚC: NHÁNH NÀO LÀ BẢN CHÍNH

**Nhánh chính duy nhất từ nay: `master`** (thư mục máy này). Đã gộp xong, có đủ tính năng của cả 2 tài khoản.

- `only-me/main` (28 commit, tài khoản chính) — **đã đối chiếu từng dòng**: mọi tính năng (nút Cập nhật mã KDTV màn Lô, Quên mật khẩu, Gợi ý v3 khoá phiên, toàn bộ migration) `master` đều đã có. 136 dòng khác nhau toàn là CSS tím / menu cũ / form đăng ký cũ mà redesign đã thay hoặc cố ý bỏ. Lịch sử 2 nhánh **khác gốc** (không có commit chung) nên KHÔNG `git merge` được — đừng thử.
- `origin/main` (repo public `dieu-do-web`) chỉ có `README.md` + `index.html`; commit `d129951` "Gợi ý v4" chỉ sửa `index.html` → **đã port tay** vào `src/app.src.html` của `master` (xem dưới).
- ⇒ **Tài khoản nào cũng làm tiếp trên `master`**, không commit vào `main` nữa.

## Đang làm

**✅ GỘP XONG + TEST 40/40: bản `master` = redesign + sửa Cảng hạ + tạo tài khoản + Gợi ý v4.**

### Phiên gộp nhánh (23/09) — port Gợi ý v4

- **Phát hiện**: DB đã chạy v4 từ trước — cron `goi-y-ke-hoach-moi-gio` (phút 5 mỗi giờ) gọi `tao_goi_y_v4()`, trong khi giao diện `master` vẫn gọi v3 và **không hiểu "phương án"** → khi 2 cont đầy tranh 1 rỗng, bản cũ cho duyệt cả 2 cùng dùng 1 rỗng, không tự chuyển cont kia sang rút mooc. Port v4 sửa đúng lỗi này.
- **Đã port vào `src/app.src.html`** (cả `vGoiY` lẫn `vWorkflowHub`): nhãn ★ Phương án; nút "Chọn cont này"; khung vàng "1 trong N phương án dùng chung 1 rỗng"; `approveGy()` gọi `duyet_phuong_an(p_id, p_nha_xe)` cho phương án (gợi ý thường vẫn update như cũ); nút Chạy gợi ý gọi `tao_goi_y_v4`.
- **Thêm migration** `supabase/migrations/20260922120000_goi_y_v4_phuong_an.sql`: định nghĩa `tao_goi_y_v4()`, `duyet_phuong_an()`, cột `goi_y.la_phuong_an`, `goi_y.nhom_gy`, cron v4 — **đọc thẳng từ DB thật** (SQL Editor, truy vấn chỉ đọc), SHA-256 phần định nghĩa hàm khớp 100% với DB. Chỉ để repo đủ mã nguồn, **không cần chạy lại** (DB đã có).
- **Sửa thêm giao diện**: nút ✕ tab Cảng hạ/Cảng đến bị rớt dòng (khai thiếu cột lưới); nút "Tạo tài khoản" bị tràn chữ.
- **Test tự động 40/40** (Playwright + `tests/mock.js`, dữ liệu 5 lô thật 626/625B/625A/624/623B từ Excel 22/09, 625A+625B dựng thành 1 nhóm phương án): 5 lô nạp đủ; Cảng hạ đúng cho cả admin lẫn CSKH; thêm/sửa/xoá Cảng hạ + Cảng đến ghi đúng bảng; tạo tài khoản + đặt lại mật khẩu gọi đúng Edge Function; Gợi ý v4 hiện phương án, chọn 625A → gọi `duyet_phuong_an` với nhà xe HLS (theo mooc) → 625B chuyển rút mooc; nút Chạy gợi ý gọi v4; trang đăng nhập không còn tự đăng ký. (Mục duy nhất báo "lỗi" là font Google do bộ test cố ý chặn offline.)
- Ghi chú bảo mật nhỏ (không gấp): 2 hàm v4 có EXECUTE cho `anon`, và điều kiện chặn quyền bỏ qua khi `auth.uid()` null (để cron chạy). Hiện an toàn vì hàm chạy quyền người gọi → RLS bảng `goi_y` chặn anon. Muốn chặt hơn: `revoke execute on function public.tao_goi_y_v4(), public.duyet_phuong_an(text,text) from public, anon;`.

### Trước đó (22–23/09): sửa Cảng hạ + tài khoản

> Edge Function `quan-ly-nhan-vien` đã deploy qua Supabase Dashboard (Via Editor), URL `https://cgfcbxsyjtdlligpdzbp.supabase.co/functions/v1/quan-ly-nhan-vien`. **Đã TẮT "Verify JWT with legacy secret"** (function tự kiểm tra token + vai trò Quản lý trong code; dự án dùng khóa mới `sb_publishable_` nên bật gateway-verify sẽ chặn nhầm token). Hi đã test trong app: tạo tài khoản + đặt lại mật khẩu chạy OK. Đã commit `987e679` và push lên `only-me/master`.

### 1. Lỗi đã sửa (an toàn, không cần deploy gì thêm — đã ghi thẳng vào `src/app.src.html` + build lại `index.html`)

- **Bug gốc**: `vDanhMuc()` không có nhánh `else if (S.dmTab === 'cangha')` → mọi lượt bấm tab "Cảng hạ" rơi vào nhánh `else` cuối cùng, mà nhánh đó chính là bảng **Nhân viên** (email/vai trò/nhà xe…) → Cảng hạ hiện y hệt bảng phân quyền admin. Với tài khoản CSKH thì bảng rỗng vì `S.nhanvien` chỉ được nạp `if (isAdmin())`, không phải do phân quyền chặn đúng — do vậy nhìn như "trống" chứ không phải "an toàn". Đã thêm nhánh `cangha` riêng, hiển thị đúng danh sách cảng hạ (`cang_ha`: tên + ghi chú), và đổi guard đầu hàm thành kiểm tra tab hợp lệ chung (`tabs.map(t=>t[0]).indexOf(S.dmTab) === -1 → về 'nhaxe'`) thay vì chỉ chặn `nv/nk/don`.
- **Bug đi kèm phát hiện thêm**: form "Cảng đến" (cangden) và giờ cả "Cảng hạ" trước đây **không hề lưu được** — `data-form="cangden"` không nằm trong danh sách được submit (`document.addEventListener('submit', …)`), và trong `saveDm()` bảng `cang_den`/`cang_ha` cũng không có trong map `tbl/pk`. Nút xoá (✕) của Cảng đến trước đây gọi nhầm RPC `xoa_nha_xe`. Đã sửa cả 3 chỗ: thêm `cangden`,`cangha` vào whitelist submit, thêm vào map `tbl/pk` trong `saveDm()`, và sửa `dm-del` để xoá đúng bảng `cang_den`/`cang_ha` bằng `delete().eq(pk,key)` thay vì gọi nhầm RPC nhà xe.
- **RLS không đổi** — bảng `cang_ha` đã có policy chuẩn từ trước (đọc: mọi role; ghi: Quản lý/Điều độ/CSKH; xoá: Quản lý) nên không cần migration mới.

### 2. Bỏ tự đăng ký mật khẩu, chuyển sang Quản lý tạo tài khoản trong app (đã hỏi Hi, chọn phương án B: Edge Function)

- Trang đăng nhập **bỏ hẳn nút/tab "Tạo tài khoản" + `sb.auth.signUp`**. Giờ chỉ còn Đăng nhập + Quên mật khẩu (reset qua email, giữ nguyên — đây là tự-đặt-lại-mật-khẩu-đã-biết-email chứ không phải tự đăng ký).
- Tab **Nhân viên** (chỉ Quản lý thấy) giờ có:
  - Dòng dưới cùng **"Tạo tài khoản"**: nhập email + mật khẩu tạm + họ tên + vai trò + ngôn ngữ + nhà xe → 1 lần bấm là vừa tạo tài khoản đăng nhập (Supabase Auth) vừa gán quyền (bảng `nhan_vien`).
  - Mỗi nhân viên đã có: thêm dòng nhỏ **"Đặt lại mật khẩu"** để Quản lý set mật khẩu mới bất cứ lúc nào (không cần nhân viên tự bấm quên mật khẩu qua email nữa nếu không muốn).
- Cơ chế: 2 form mới gọi Edge Function `quan-ly-nhan-vien` (file `supabase/functions/quan-ly-nhan-vien/index.ts`, **MỚI TẠO, CHƯA DEPLOY**) — hàm này giữ `service_role` key ở phía server (Supabase), kiểm tra người gọi đúng là `vai_tro = 'Quản lý'` rồi mới được tạo user / đổi mật khẩu người khác. Khoá `service_role` **không** nằm trong `app.src.html` hay bất kỳ file client nào — đúng nguyên tắc bảo mật ghi trong `README.md`.
- **Không đổi dữ liệu vai trò hiện có** (Hi yêu cầu giữ nguyên) — tính năng áp dụng cho bất kỳ ai đang có `vai_tro = 'Quản lý'` trong bảng `nhan_vien` (hiện là tinbui403@gmail.com), không hardcode theo email.

## Edge Function `quan-ly-nhan-vien` — ✅ ĐÃ DEPLOY (23/09)

Đã deploy qua Dashboard → Edge Functions → Via Editor, tên `quan-ly-nhan-vien`, **tắt** "Verify JWT with legacy secret". Nếu sửa code function: sửa `supabase/functions/quan-ly-nhan-vien/index.ts` rồi dán lại vào Dashboard (tab Code) hoặc `supabase functions deploy quan-ly-nhan-vien` nếu có CLI.

## Dữ liệu test

Bộ test dùng 5 lô gần nhất trong file Excel vận hành ngày 22/09 (file `.xlsx` nằm ở thư mục dự án, bị `.gitignore` chặn). **Không chép số booking / số cont / tên khách vào file này** — repo có bản public. Muốn test lại: đọc Excel, dựng `tests/fixtures.json` (cũng bị gitignore) rồi chạy bộ test Playwright.

## Bước kế tiếp

1. Hi mở `index.html` bản mới, bấm thử **Điều phối → Gợi ý**: khi có 2+ cont đầy tranh 1 rỗng sẽ thấy nhãn ★ Phương án, chọn 1 cont → các cont còn lại tự thành Rút mooc.
2. **Push** commit gộp lên GitHub — chạy trên terminal Windows (VM Cowork không có đăng nhập GitHub): `git push only-me master` (+ `git push origin master` nếu muốn cập nhật bản public `dieu-do-web`).
3. (Tuỳ chọn) Đổi default branch của `only-me` sang `master` (Settings → General → Default branch) để mở repo thấy đúng bản chính; nhánh `main` giữ làm lưu trữ, không commit thêm.
4. (Tuỳ chọn) Siết quyền 2 hàm v4 (revoke anon — xem ghi chú bảo mật ở trên).
5. (Tuỳ chọn, còn treo từ trước) Phase 5 polish biểu đồ Tổng quan còn vài màu tím; dọn các file nháp PHASE*/prototype/XEM_THU.

## Quy ước — đừng làm sai

- **Không sửa trực tiếp `index.html`.** Sửa `src/app.src.html` (và `src/kiem_dich_wizard.js` nếu cần) rồi chạy `python build.py`.
- `build.py` nhúng cả supabase + wizard vào index.html → **index.html tự chứa** (mở ở đâu cũng chạy, không cần file js ngoài).
- Thay đổi DB = **thêm file migration mới** trong `supabase/migrations/`, không sửa migration cũ.
- **`service_role` key KHÔNG được đưa vào bất kỳ file client nào** (app.src.html, index.html) — chỉ đặt trong Edge Function (Supabase tự cấp qua biến môi trường, không cần lưu ở đâu khác).
- Sửa hàm gợi ý / quy tắc KD xong phải chạy lại `tests/kiem_thu_goi_y_v3.sql` và `tests/kiem_thu_kd.sql`.
- Không đưa lên GitHub: dữ liệu thật, Excel, mật khẩu, mã sao lưu, token KDTV, `service_role` key.
- **Sau khi sửa `<script>` inline, phải test tải app** (lỗi cú pháp làm trắng màn hình mà không báo gì rõ) — phiên này đã `node --check` phần JS trích ra, không lỗi cú pháp.

## Việc còn treo (chưa ai yêu cầu làm, chỉ ghi để nhớ)

- Biểu đồ màn **Tổng quan** (`vTong`) vẫn còn vài hex màu tím hardcode (area/donut track/heatmap/bar). Status pill / clChip / TYPES / MUC đã đổi blue.
- `canh_bao_thieu_rong()` có trong DB nhưng web chưa gọi.
- Hàm cũ `tao_goi_y()` giữ để đối chiếu, không còn được gọi. Chưa quyết định xoá.
- Cấu hình "Chế độ thử: cho xoá dữ liệu đã chạy": khi chạy chính thức phải đổi thành **Tắt**.
- File nháp `src/app.src.PHASE1-4.html`, `kiem_dich_wizard.PHASE3.js`, `prototype_glassmorphism.html`, `XEM_THU_PHASE4.html` — nội dung đã gộp vào bản thật, có thể xoá khi được yêu cầu.

## Nhật ký phiên

| Ngày | Tài khoản / phiên | Đã làm |
|---|---|---|
| 23/09/2026 | Cowork (phiên gộp nhánh) | Đối chiếu `only-me/main` ↔ `master`: main nằm trọn trong master (khác gốc, không merge được). Port tay Gợi ý v4 (`d129951`) vào redesign (vGoiY + vWorkflowHub + approveGy + runGoiY). Kiểm tra DB bằng SQL chỉ đọc: `tao_goi_y_v4`, `duyet_phuong_an`, cột `la_phuong_an`/`nhom_gy` đã có; cron đã chạy v4. Thêm migration `20260922120000_goi_y_v4_phuong_an.sql` (SHA khớp DB). Sửa lưới cột Cảng hạ/Cảng đến + nút Tạo tài khoản. Test Playwright 40/40 với 5 lô thật. Commit `a796eba`, Hi đã push `only-me/master` 23/09. |
| 22/09/2026 | Cowork (phiên sửa Cảng hạ + tài khoản) | Sửa bug Cảng hạ hiện nhầm bảng Nhân viên (thiếu nhánh `cangha` trong `vDanhMuc`); sửa luôn bug Cảng đến/Cảng hạ không submit/lưu/xoá được đúng bảng. Bỏ tự đăng ký (`sb.auth.signUp`) khỏi trang đăng nhập. Thêm tab Nhân viên: Quản lý tạo tài khoản (email+mật khẩu+vai trò) và đặt lại mật khẩu cho nhân viên đã có, gọi Edge Function mới `quan-ly-nhan-vien` (đã deploy 23/09). Đọc Excel dữ liệu thật 22/09 lấy 5 lô gần nhất làm ví dụ test. Build lại `index.html`, `node --check` JS OK. Commit `987e679`, đã push `only-me/master`. |
| 22/09/2026 | Cowork (Account 2 · redesign) | **CHỐT Phase 1→4 vào bản thật**: app.src.html + kiem_dich_wizard.js (inline) + build.py (nhúng wizard) + rebuild index.html (tự chứa, test V8 OK). Cập nhật TIEN_DO. Đã push (`ed7d351`). |
| 22/09/2026 | Cowork (Account 2 · redesign) | Phase 4 Container Board + sửa 2 lỗi cú pháp vWorkflowHub (PHASE1/2/3 trắng màn hình) + đổi màu status→blue. Test headless OK. |
| 22/09/2026 | Cowork (Account 2 · redesign) | Phase 3 KD inline, Phase 2 Glassmorphism Blue + prototype, Phase 1 Workflow Hub. |
| 22/09/2026 | Cowork | KD Wizard drawer, rebuild index.html, commit `5e19aff`. |
| 21/09/2026 | Cowork | Đọc lại dự án, tạo `TIEN_DO.md`. |
