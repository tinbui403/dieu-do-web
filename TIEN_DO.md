# TIẾN ĐỘ — file bàn giao giữa các phiên làm việc

> **Dành cho Claude (bất kỳ tài khoản / phiên nào):** đọc `README.md` trước để hiểu hệ thống, rồi đọc file này để biết đang dở ở đâu. Xong mỗi mốc thì **cập nhật lại file này** (mục "Đang làm", "Bước kế tiếp", "Nhật ký phiên") trước khi dừng.

Cập nhật lần cuối: **24/09/2026 ~02:00** (giờ VN, phiên NẠP EXCEL HÔM NAY — tài khoản phụ; giao diện kính 3D làm trước đó cùng đêm)

## 🚀 ĐẨY GITHUB 24/09 — ĐÃ COMMIT, CHỜ PUSH TRÊN MÁY

Đã commit toàn bộ code mới (giao diện 3D + 4 lỗi team + lô sự cố + lọc tin nhắn + duyệt gán nhà xe + tools/nap_excel.py + 4 migration) vào **master** và tạo sẵn nhánh **ban-public** (bản cho repo public). Đã quét sạch dữ liệu thật (mã đơn/số cont/tên khách) khỏi mọi file được git theo dõi; file test có cont thật (`tests/test_*.py`), `tools/*.local.json`, `Claude outputs/` đã cho vào `.gitignore`.

**Máy ảo Cowork KHÔNG đăng nhập GitHub được** → phải push trên **terminal Windows** (mở tại thư mục dự án), 2 lệnh:
```
git push only-me master
git push origin ban-public:master
```
Lệnh 2 xong → GitHub Pages build lại (vài phút) → team dùng bản mới. (Đừng `git push origin master` — theo quy ước dùng ban-public.)

## ⚠ ĐỌC TRƯỚC: NHÁNH NÀO LÀ BẢN CHÍNH

**Nhánh chính duy nhất từ nay: `master`** (thư mục máy này). Đã gộp xong, có đủ tính năng của cả 2 tài khoản.

- `only-me/main` (28 commit, tài khoản chính) — **đã đối chiếu từng dòng**: mọi tính năng (nút Cập nhật mã KDTV màn Lô, Quên mật khẩu, Gợi ý v3 khoá phiên, toàn bộ migration) `master` đều đã có. 136 dòng khác nhau toàn là CSS tím / menu cũ / form đăng ký cũ mà redesign đã thay hoặc cố ý bỏ. Lịch sử 2 nhánh **khác gốc** (không có commit chung) nên KHÔNG `git merge` được — đừng thử.
- `origin/main` (repo public `dieu-do-web`) chỉ có `README.md` + `index.html`; commit `d129951` "Gợi ý v4" chỉ sửa `index.html` → **đã port tay** vào `src/app.src.html` của `master` (xem dưới).
- ⇒ **Tài khoản nào cũng làm tiếp trên `master`**, không commit vào `main` nữa.

## Đang làm

### Nạp Excel "dư liệu hôm nay.xlsx" (24/09, tài khoản phụ) — ✅ ĐÃ CHẠY TRÊN SUPABASE, có sao lưu

Anh Hi: "cập nhật dữ liệu thực tế hôm nay lên Supabase, bỏ hết dữ liệu [đợt] hôm qua, cách làm như hôm qua". Hỏi trắc nghiệm, anh chốt: **nạp chồng, Excel là chuẩn** (không xoá đợt 22/09; ô Excel có giá trị thì ghi đè, trống thì giữ DB; cont app đã đi xa hơn Excel thì giữ theo app); lô đã qua CLS xử lý như luật hôm qua → **xoá 611A**; 5 cont Evergreen chưa có lô (ghi chú "… sang hàng" = cont thay cho cont bị rệp của 604B/607B) → nạp **bước 1 Chờ cắt rỗng**, không gán lô; **617 và 624 là lô rớt tàu (sheet KD đánh dấu "R")** → giữ lại, phục hồi theo Excel (617 trả booking/tàu thật thay giá trị thử "234"/"1243", CLS để trống chờ booking mới; 624 lùi cont về Ở bãi HLS, bỏ tích KD + thanh lý).

- **Công cụ dùng lại hằng ngày: `tools/nap_excel.py`** (+ `tools/model.py`, bảng ánh xạ tên `tools/anh_xa_ten.local.json` — file này gitignore vì chứa tên khách/kho/nhà xe). Chạy: `python tools/nap_excel.py "<file>.xlsx" --ngay 24/09 --moc 23/09 --xoa-lo 611A --rot-tau 617,624 --doi-ma "613A>613,622>622A" --ra sao-luu/nap_24-09_that.sql` (thêm `--thu` để sinh bản chạy thử: cuối khối `raise exception 'KET_QUA…'` → rollback, đọc báo cáo trước). SQL sinh ra là 1 khối `do $$…$$` tự bật `dieu_do.bo_qua_kiem_tra`, có bảng tạm `_bao_cao` liệt kê từng thay đổi; file SQL nằm `sao-luu/nap_*.sql` (gitignore, chứa dữ liệu thật). Cần `pip install openpyxl`.
- Luật trong script: lô lấy từ dòng ≥ 1250 sheet MỚI ĐIỀU ĐỘ; CLS = Cls mail (sheet KD cột Q) → Cls ePort (cột O, rồi cột C) → ETD − 1 ngày; **chỉ nạp lô CLS ≥ giờ chạy** hoặc lô "R"; lô sheet KD ghi Kiểm dịch + Thanh lý = True → bỏ qua. ETD lấy sheet KD (khối phải → khối trái → Điều độ). Trạng thái cont: hiện trạng = tên bãi → 4 (HLS/HT/PD); "已登船" → 6; có ngày đến kho < mốc → 3, = mốc → 2; không có ngày → 1. Mỗi lô 1 cont KD theo cột D sheet KD (lô đã tích KD thì không đổi, chỉ báo). `closing_eport` trong DB do sync ePort giữ (script chỉ điền khi trống); `closing_mail` Excel thắng. Cont mới id `C260924-<số cont>`, `nguon = 'Excel 24/09 (dòng N)'`.
- Kết quả chạy thật (báo cáo đầy đủ nằm trong nhật ký `nhat_ky`, người = "hệ thống", ~109 dòng lúc ~01:30 24/09): đổi mã lô 613A→613 (2 cont) và 622→622A; xoá 611A (2 cont); 3 lô mới xếp lại tàu theo sheet KD **604B, 607B (ETD 02/10, CLS 01/10 22:00, cont bị rệp, booking/tàu trong Điều độ còn cũ — ghi chú sẵn) và 609E** (BUXMELODY 26/09); lô mới 613A (1 cont), 622B (2 cont); 12 lô sửa ETD/CLS theo sheet KD (588, 590A-C, 597A-B, 598A-C, 613x, 614x, 619A-B…); 601A đổi mã KDTV theo sheet KD; 21 cont mới (16 thuộc lô + 5 chưa lô); ~14 cont đổi bước (2→3 vì đã qua ngày, 3→4 vào bãi theo Excel); KD lô 590C chuyển dấu sang cont theo sheet KD; 11 lô được gắn cont KD mới. Sau chạy: 38 lô đang chạy, cont bước 1=6, 2=4, 3=47, 4=28; không lô nào >1 cont KD; gợi ý đã duyệt (620A ↔ đơn rỗng) còn nguyên.
- **Sao lưu trước khi nạp:** bảng `private.sao_luu_20260924_truoc_nap` (luc, bang, dong jsonb — lo 231, cont 491, goi_y 30, lo_su_co 4, thong_tin_cu 2), RLS bật, không lộ qua API. Muốn hoàn tác dòng nào: lấy jsonb trong đó ghi đè lại.
- **Việc team cần xem sau nạp:** (1) 604B/607B: booking + tàu mới chưa có trong Excel, sync ePort có thể ghi đè CLS bằng tàu cũ; (2) 617/624 chờ booking mới — khi có thì vào hồ sơ lô sửa booking/tàu/CLS; (3) cont FSCU… lô 588: app ghi bãi HLS, Excel ghi HT → đã theo Excel (HT); (4) 601A mã KDTV đổi theo sheet KD (cũ TV…3715 → TV…5158) — nếu sheet KD sai thì sửa lại; (5) 5 cont Evergreen "sang hàng" đang bước 1 chưa gán lô — khi có booking thì gán; (6) 590C cont KD đổi theo sheet KD.
- Lần sau nạp: cùng lệnh trên với `--ngay`/`--moc` mới, bỏ `--doi-ma`/`--xoa-lo`/`--rot-tau` nếu không còn; chạy `--thu` trước, đọc KET_QUA, rồi chạy thật; SHA-256 file khớp editor rồi mới Run. Bổ sung tên mới vào `anh_xa_ten.local.json` khi báo cáo có "DANH MỤC: thêm…".

### Giao diện kính 3D tím – chàm, nền động chủ đề điều độ (24/09, tài khoản phụ) — ĐÃ LÀM Ở MÁY, CHƯA commit/push

Anh Hi gửi ảnh mẫu Pinterest (dashboard kính mờ: khung trắng bo tròn nổi trên nền có khối tím/hồng + quả cầu cam). Anh chốt bằng câu hỏi trắc nghiệm: màu nhấn **tím – chàm như mẫu**; nền 3D **thêm hình cont / tàu / cần cẩu mờ**; chuyển động **nhẹ**; **làm xong 3D rồi đẩy GitHub một lần** (chưa đẩy).

Chỉ đổi lớp trình bày — **không đổi chức năng, không đổi tên class, không đổi DB**:
- `src/app.src.html`: viết lại toàn bộ khối `<style>` (token `:root` mới: `--pri #6D5AE6`, `--pri-ink #4F3FCF`, `--pri-grad`, `--tint`, `--sh-card`, `--frame`…; mọi tên biến cũ vẫn còn vì JS dùng inline). Khung ứng dụng `.app` giờ là **tấm kính cố định** (`position:fixed; inset:var(--frame)`, bo 26px, `::before` blur 30px + bóng lớn); **`.main` tự cuộn bên trong** (không cuộn cả trang) → `.top` dính trong `.main`; sidebar chuyển sáng (mục đang chọn tím + vạch trái); thẻ / bảng / nút / chip / ô nhập / ngăn kéo / đăng nhập theo kính trắng bo tròn, bóng mềm; ngăn kéo desktop là tấm kính nổi bo 22px cách mép 12px.
- Lớp nền `<div class="bg3d">` tĩnh ngay sau `<body>` (ngoài `#root`, không nhận chuột): 4 khối màu (`b1`–`b4`), quả cầu cam (`sph`), 3 SVG mềm `sh-crane` (cần cẩu + cont treo), `sh-ship` (tàu chở cont), `sh-cont` (cont isometric). Trôi chậm bằng `transform` (drift1/2/3, bob, sail, sway — 14–46 giây); `@media (prefers-reduced-motion)` tắt; máy ≤2 nhân hoặc ≤2GB tự thêm `html.lite` → nền đứng yên (đầu `<script>`).
- Chuyển động nhẹ: `.card`/`.gy-card` nhấc 2px khi rê chuột; đổi tab → `#main.swap` hiện dần (handler `tab`, kèm `scrollTop = 0` cho `.main`); ngăn kéo trượt vào **chỉ khi mở mới** (`drawerIn()` gắn class `in` nếu `#drawer` đang trống — vẽ lại sau khi lưu thì không nháy); khung kính hiện dần chỉ lần đầu (`app-in`).
- Điện thoại (≤900px): khung sát mép, không bo; sidebar trượt là tấm kính trắng đục; thanh menu dưới kính; tắt hover-lift; ẩn cần cẩu.
- Icon logo sidebar đổi sang trắng trên nền gradient tím; `theme-color` + favicon `#5B47E0`. Pill trạng thái 1/2, cảnh báo CLS, màu đỏ/vàng/xanh lá **giữ nguyên** (màu nghĩa, để nhân viên khỏi lạ).
- Test: `tests/test_3d.py` **22/22** (lớp nền, khung cố định, cuộn trong `.main`, thanh tiêu đề dính, đổi tab fade + về đầu, sidebar sáng, gradient tím, hover nhấc thẻ, ngăn kéo `in` chỉ khi mở mới, mobile, reduced-motion, lite). Bộ cũ vẫn xanh: test_duyet_bai 12/12, test_tinnhan 22/22, test_suco 30/30, test_moi 40/40, run_test 39/40 (font).
- Đã build tại máy: `src/app.src.html` sha `929948e3…`, `index.html` sha `34d06700…` (khớp bản test).
- Lưu ý khi làm tiếp: `window.scrollTo` không còn cuộn gì (trang không cuộn) — muốn cuộn nội dung dùng `document.querySelector('.main').scrollTop`. Không đặt `transform`/`filter` lên `.app` (sẽ làm hỏng `position:fixed` của scrim / sidebar mobile) — kính nằm ở `.app::before`.

### Sửa 4 lỗi team báo 23/09 (tài khoản phụ, ~19:30) — ĐÃ SỬA Ở MÁY + ĐÃ CHẠY SQL; CHƯA commit / push

Yêu cầu gốc: file `yêu cần mới.md` anh Hi gửi. Anh dặn: **chỉ làm đúng mấy cái anh nói, không tự thêm bộ lọc / quy tắc nào**.

1. **Không đổi được mã lô** → thêm ô "Đổi mã lô" (lúc đầu chỉ Quản lý, sau mở cho Điều độ — xem mục 5) trong hồ sơ lô, bấm 2 lần xác nhận. Gọi RPC mới `doi_ma_lo(p_cu, p_moi)` — file `supabase/migrations/20260923190000_doi_ma_lo.sql`.
   - `cont.lo` đã là `references lo(lo) on update cascade` → đổi `lo.lo` là cont tự đổi theo. `goi_y` nối qua id cont, không chứa mã lô.
   - Hàm bật `dieu_do.bo_qua_kiem_tra` trong lúc đổi, vì trigger `cont_sau_kd` sẽ tự BỎ TÍCH "Lô đã kiểm dịch" khi cont KD "đổi lô".
   - Nhật ký không sửa: `nk_lo` tự ghi dòng `lo: cũ → mới` dưới mã mới; web (`loadHistory`) tự nối lịch sử mã cũ theo dòng đó.
   - ✅ **ĐÃ CHẠY trên Supabase 23/09** (anh Hi cho phép; SHA trong SQL editor khớp file `4c2ecabd…`). Test thật trong khối tự hủy: lô 3 cont đổi mã → 3 cont theo, mã cũ 0 cont, cont KD giữ dấu, lô đã tích KD vẫn giữ tích, nhật ký ghi dòng đổi mã, tài khoản Điều độ bị chặn "Chỉ Quản lý…". Kiểm lại sau test: dữ liệu thật không đổi, không sót dòng test.
2. **Tích nhầm "Lô đã kiểm dịch" không lùi được** → bản redesign làm mất nút `kd-undo` (bản cũ có). Gắn lại ở hồ sơ lô + từng thẻ lô màn Hạ cảng. Quản lý + Điều độ; khóa nếu lô có cont ở cảng/lên tàu. DB (`private.kiem_tra_lo`) vốn đã chặn đúng quy tắc này → không đổi DB.
3. **Hạ cảng: lệnh chép gom theo lô, gửi bãi nào cũng dính cont bãi khác** → thêm 4 ô lọc Tàu / Bãi / Lô / CLS (giá trị lấy từ chính danh sách đang hiện, không có mốc giờ tự đặt). Nút "Chép gửi quản lý bãi" chép đúng các cont đang lọc. Lệnh chép chỉ tiếng Việt, bỏ dòng Booking; nếu chỉ còn 1 bãi thì tiêu đề ghi "· Bãi X".
4. **Container ở bãi** → thêm kiểu sắp xếp "Cont kiểm dịch" (cont KD lên đầu, rồi theo giờ vào bãi), nhãn KD cạnh mã lô, mỗi bãi 1 nút "Chép cont kiểm dịch (n)" — chép mọi cont có dấu KD đang ở bãi đó (số cont, seal, lô, mã KDTV, CLS; lô đã KD thì ghi chú "(lô đã kiểm dịch)").

5. **Mở quyền cho Điều độ (anh Hi yêu cầu sau đó):** Đổi mã lô, Giá cước nhà xe, Bãi tạm → **Quản lý + Điều độ** đều nhập / sửa được (trước chỉ Quản lý). Web: hàm `canDm()`. DB: migration `20260923200000_quyen_dieu_do_bai_gia_doi_ma_lo.sql` — **ĐÃ CHẠY trên Supabase** (SHA `3fe0585b…` khớp): policy `ql dd them/sua` cho `bai_tam` (xoá bãi vẫn chỉ Quản lý), `ql dd them/sua/xoa` cho `bang_gia_xe` (xoá = để trống ô giá), `doi_ma_lo` cho QL + Điều độ. Test thật dưới role `authenticated` (khối tự hủy): Điều độ sửa bãi / thêm-xoá giá / đổi mã lô được; CSKH bị chặn cả 3. Không sót dòng test.

Test: `tests/test_moi.py` 40/40 PASS (cần `fixtures.json` + `test.html` dựng như build.py); bộ cũ `run_test.py` 39/40 — 1 "lỗi" là request font Google do chính test chặn, không liên quan.

### Duyệt gợi ý → gán nhà xe vào đơn rỗng + chọn bãi khi Vào bãi (24/09, tài khoản phụ) — ĐÃ CHẠY SQL, CHƯA commit/push

- Migration `20260924090000_duyet_goi_y_gan_nha_xe.sql` **ĐÃ CHẠY** (SHA `10be024a…`): trigger `goi_y_gan_nha_xe` (after update of duyet, nha_xe_chon, id_cont_rong on goi_y). Duyệt → **chỉ đơn rỗng** (`id_cont_rong`, còn trạng thái '1') nhận nhà xe = `coalesce(nha_xe_chon, nha_xe_goi_y)` (phải có trong Danh mục nhà xe); cont đầy không đổi. Bỏ duyệt → gỡ nhà xe nếu đơn vẫn '1' và đúng nhà xe đã gán. Đổi nhà xe khi đã duyệt → đổi theo. Backfill: gợi ý đã duyệt chưa chạy → đã gán nhà xe cho đơn rỗng tương ứng. Test thật (khối tự hủy): bỏ duyệt → null, duyệt lại → VTL. Bộ gợi ý v4 vốn chỉ ghép rỗng có nhà xe với đầy cùng nhà xe → không lệch.
- Web: tab Chờ cắt rỗng — cột Nhà xe hiện nhà xe theo kế hoạch duyệt; dưới dòng đơn có dòng `data-ke-hoach` "↳ Đã duyệt · <loại lệnh> · Nhà xe X · Kéo đầy về <cont> Lô <lô> → <nơi hạ>" (`keHoachRong()`).
- Vào bãi (mọi nút chuyển sang bước 4 — bảng + hồ sơ cont): nhà xe **HLS → thẳng bãi HLS** (`BAI_THEO_NX`); nhà xe khác → hiện nút các bãi (`baiChon()`, `S.pickBai`, act `move-bai` / `pick-bai-x`). `moveCont(id, to, bai)`. Nút "Đánh dấu đã chạy" gợi ý vẫn dùng bãi theo kế hoạch như cũ.
- Test `tests/test_duyet_bai.py` 12/12; test_tinnhan 22/22, test_suco 30/30, test_moi 40/40, run_test 39/40 (font).

### Làm gọn UI/UX — anh Hi ĐỔI Ý (23/09 tối): bỏ hướng bản mẫu 6 màn

Bản mẫu Design "Điều độ – Mẫu giao diện gọn" (Việc của tôi, ghép booking, vào bãi 1 chạm, chọn chuyến ePort, điện thoại) **KHÔNG làm nữa**. Anh chốt: giữ nguyên phương án hiện tại, **chỉ đổi bước Thêm đơn / cont thành lọc được từ tin nhắn**, còn lại giữ nguyên.
- ✅ ĐÃ LÀM (chưa commit/push): form "Đơn / cont mới" (mở từ Container → Thêm đơn / cont, hoặc hồ sơ lô → Thêm cont) có thêm khối "Lọc từ tin nhắn khách" ở đầu (chỉ khi tạo mới + canWrite). Dán tin kiểu nào cũng được → `parseTinNhan()` (nhãn "Chủ hàng:"… hoặc viết tự do) → `tnDien()` điền các ô CÓ SẴN: Mã đơn, Khách hàng, Kho (khớp Danh mục, không khớp thì báo chọn tay), Cần lên kho (ngày + giờ: sáng 07:00 / chiều 13:00 / "8h30"), Giờ lên kho ghi chú, Ghi chú (nơi đến, tàu, hãng, số lượng, ngày đặt). Tin ghi N cont (N>1) → hiện ô "Số đơn tạo cùng lúc" (id `tn-n`, không có name nên không lọt vào dữ liệu) → Lưu tạo N dòng cont. Không đổi DB. Test `tests/test_tinnhan.py` 22/22.
- ✅ ĐÃ LÀM 24/09: phong cách kính 3D tím – chàm, nền động chủ đề điều độ — xem mục đầu "Đang làm".

### Lô có sự cố + chặn CSKH (23/09 tối, tài khoản phụ) — ĐÃ CHẠY SQL, CHƯA commit/push

Anh Hi chốt: (1) chặn CSKH lùi kiểm dịch vòng; (2) "Chế độ thử" giữ nguyên = mặc định cho Quản lý (KHÔNG tắt); (3) thêm mục **Theo dõi cont → Lô có sự cố**.
- Migration `20260923210000_lo_su_co_va_chan_cskh_kd.sql` — **ĐÃ CHẠY trên Supabase** (SHA `23fb7588…`). Bảng mới `lo_su_co` (sự cố đang mở: `da_xu_ly=false`, 1 lô tối đa 1 sự cố mở), `thong_tin_cu` (giá trị cũ bị thay; FK `lo`/`cont_id` on update cascade; chỉ Quản lý sửa/xoá). RPC `bao_su_co(p_lo, p_loai, p_ghi_chu)`, `xu_ly_su_co(p_lo, p_huong, p_du_lieu jsonb, p_ghi_chu)` (security definer, QL + Điều độ). Trigger: `cont_khoa_su_co_cskh` (lô sự cố → cấm đổi trạng thái cont; CSKH cấm bỏ dấu/đổi lô/hủy cont KD của lô đã KD), `lo_khoa_su_co` (cấm tích KD khi đang sự cố), `goi_y_bo_lo_su_co` (bỏ gợi ý mới của lô sự cố). Cờ bỏ qua khi xử lý: `dieu_do.xu_ly_su_co`.
- Quy tắc: loại = "KD không đạt" (tự bỏ tích KD) hoặc "Rớt tàu" (giữ tích). Báo → xoá gợi ý CHƯA duyệt của lô. Xử lý: Rớt tàu → "Đổi tàu / booking" (bắt booking, tàu/chuyến, CLS mail; kèm hãng tàu, ETD, ETA; xoá kết quả ePort tàu cũ) | "Hủy lô". KD không đạt → "Đổi cont" (cont cũ → 9, cont mới insert ở '1', số cont/seal cũ lưu thong_tin_cu) | "Xông trùng, giữ cont" (bắt ghi chú, lô vẫn chưa KD) | "Hủy lô" (gọi huy_lo — chỉ được khi cont chưa chạy).
- Web: tab `suco` (form báo + thẻ từng lô + nút hướng xử lý), banner + ô báo trong hồ sơ lô, drawer `f-xuly`, nhãn "!" trên bảng cont, nút bước bị thay bằng "Sự cố – chờ xử lý", Hạ cảng ẩn lô sự cố; giá trị cũ in nghiêng dưới ô mới (`withCu`, `contCell`), Quản lý có ô sửa/✕.
- Test: `tests/test_suco.py` 30/30, `test_moi.py` 40/40, `run_test.py` 39/40 (font). Test thật trên DB (khối tự hủy, role authenticated): CSKH báo bị chặn; ĐĐ báo KD không đạt; chuyển bước / tích KD bị chặn; gợi ý mới bị bỏ; đổi cont → cũ 9, mới '1' + lưu số cũ; rớt tàu thiếu booking bị chặn, đủ thì đổi + lưu 5 giá trị cũ; CSKH bỏ dấu cont KD bị chặn. Kiểm lại: DB không sót gì.

**Mục 6 (phân tích thao tác NV) — sơ bộ, 23/09 tối:** đã đọc `nhat_ky` 22–23/09 (chỉ SELECT). Dữ liệu rất ít (Điều độ 2 lượt, CSKH ~11, còn lại Quản lý + máy). Thấy: (1) lùi kiểm dịch bằng cách bỏ/đánh lại dấu "Cont kiểm dịch" → lô tự về CHƯA KD, CSKH lùi được KD qua đường này; (2) lùi-tiến trạng thái cont nhiều lần (bấm nhầm bước); (3) sửa tên tàu nhiều lần cho khớp ePort; (4) dữ liệu thử lẫn dữ liệu thật + xoá hẳn cont thật; (5) không ai duyệt gợi ý từ 22/09; (6) Quản lý đang làm việc vận hành thay Điều độ. → anh Hi đã quyết: chặn CSKH (ĐÃ LÀM, xem mục trên); Chế độ thử giữ nguyên cho Quản lý. Phân tích lại sau ~1 tuần dùng thật.

**Việc còn lại:** (a) ~~chạy SQL~~ xong; (b) commit `master` + đẩy `only-me` + đẩy public theo quy trình commit-tree bên dưới (Pages chạy từ `master` public → đẩy là team dùng luôn); (c) mục 6 (phân tích thao tác nhân viên) chưa làm — cần anh cho cách lấy nhật ký thao tác.

### Nhập dữ liệu thật vào Supabase (23/09, ~01:30 giờ VN)

- Đã nhập **34 lô + 66 cont** đang chạy, CLS còn hiệu lực, từ file Excel ngày 22/09 (sheet MỚI ĐIỀU ĐỘ + Kế hoạch Hạ - Kiểm Dịch) — 1 giao dịch SQL, kiểm tra SHA trước khi chạy. Trước đó DB chỉ có lô tới ETD 05/09 (425 cont đều đã lên tàu).
- Mọi cont nhập có `nguon = 'Excel 22/09 (dòng N)'`, id dạng `C260923-<số cont>`; giữ tên kho gốc ở `kho_goc`, hiện trạng gốc ở `hien_trang_goc`.
- Quy ước đã chốt với Hi: VT LSG = VTL; cont ở kho → đến kho trước 22/09 = "Đầy chờ kéo" (3), đến kho 22/09 = "Đang đóng hàng" (2); Hoàng Liên Sơn/Hưng Thịnh/Phương Đông = "Ở bãi tạm" (HLS/HT/PD); 6 lô thiếu CLS ghi CLS nhập tay = ETD − 1 ngày; một số kho có tên gốc trùng tên khách → map về đúng tên kho trong Danh mục. Ô Số lô/Booking trong Excel là ô gộp → đã tách theo vùng gộp.
- Đánh dấu sẵn cont kiểm dịch theo kế hoạch KD (28 lô); mang theo tick ePort + mã KDTV có trong Excel. **Chưa tích "Lô đã kiểm dịch"** lô nào (Excel ghi chưa, và luật DB chặn tích khi nhập).
- Việc cho team: rà lại trạng thái cont thực tế (nhất là 48 cont "Đầy chờ kéo"), tích kiểm dịch khi đủ điều kiện. Cron gợi ý v4 chạy phút 5 mỗi giờ sẽ tự sinh gợi ý cho các lô này.
- Muốn nhập lại / nhập thêm: lệnh chặn nếu đã có cont `nguon like 'Excel 22/09%'` — phải xoá đợt cũ hoặc đổi nhãn nguồn.

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

0. **Anh Hi mở `index.html` xem giao diện kính 3D** (Tổng quan, Container, ngăn kéo, điện thoại). Anh chốt: xong 3D thì **đẩy GitHub một lần** cả 7 phần đang giữ (đổi mã lô, bỏ tích KD, lọc hạ cảng, lô sự cố, lọc tin nhắn, duyệt → nhà xe + chọn bãi, giao diện 3D) — `only-me master` + bản public theo quy ước commit-tree bên dưới. Chưa có lệnh đẩy → chưa đẩy.
1. Hi mở `index.html` bản mới, bấm thử **Điều phối → Gợi ý**: khi có 2+ cont đầy tranh 1 rỗng sẽ thấy nhãn ★ Phương án, chọn 1 cont → các cont còn lại tự thành Rút mooc.
2. **Push** commit gộp lên GitHub — chạy trên terminal Windows (VM Cowork không có đăng nhập GitHub): `git push only-me master` (+ `git push origin master` nếu muốn cập nhật bản public `dieu-do-web`).
3. (Tuỳ chọn) Đổi default branch của `only-me` sang `master` (Settings → General → Default branch) để mở repo thấy đúng bản chính; nhánh `main` giữ làm lưu trữ, không commit thêm.
4. (Tuỳ chọn) Siết quyền 2 hàm v4 (revoke anon — xem ghi chú bảo mật ở trên).
5. (Tuỳ chọn, còn treo từ trước) Phase 5 polish biểu đồ Tổng quan còn vài màu tím; dọn các file nháp PHASE*/prototype/XEM_THU.

## Quy ước — đừng làm sai

- **Đẩy bản public (`origin` = dieu-do-web):** KHÔNG `git push origin master` (lịch sử master có commit chứa dữ liệu thật + đã tách khỏi origin). Làm: `SHA=$(git commit-tree "master^{tree}" -p origin/master -m "mô tả")` → `git branch -f ban-public $SHA` → kiểm tra `git diff origin/master ban-public` không có dữ liệu thật → `git push origin ban-public:master`.
- **Không chép dữ liệu thật** (booking, số cont, tên khách, email nhân viên) vào bất kỳ file nào được git theo dõi, kể cả TIEN_DO.md.
- **Không sửa trực tiếp `index.html`.** Sửa `src/app.src.html` (và `src/kiem_dich_wizard.js` nếu cần) rồi chạy `python build.py`.
- `build.py` nhúng cả supabase + wizard vào index.html → **index.html tự chứa** (mở ở đâu cũng chạy, không cần file js ngoài).
- Thay đổi DB = **thêm file migration mới** trong `supabase/migrations/`, không sửa migration cũ.
- **`service_role` key KHÔNG được đưa vào bất kỳ file client nào** (app.src.html, index.html) — chỉ đặt trong Edge Function (Supabase tự cấp qua biến môi trường, không cần lưu ở đâu khác).
- Sửa hàm gợi ý / quy tắc KD xong phải chạy lại `tests/kiem_thu_goi_y_v3.sql` và `tests/kiem_thu_kd.sql`.
- Không đưa lên GitHub: dữ liệu thật, Excel, mật khẩu, mã sao lưu, token KDTV, `service_role` key.
- **Sau khi sửa `<script>` inline, phải test tải app** (lỗi cú pháp làm trắng màn hình mà không báo gì rõ) — phiên này đã `node --check` phần JS trích ra, không lỗi cú pháp.

## Việc còn treo (chưa ai yêu cầu làm, chỉ ghi để nhớ)

- Bảng màu đã quay về tím – chàm (24/09) nên các hex tím trong `vTong` (area/heatmap/bar) nay hợp tông. Pill trạng thái 1/2 + CLS xa vẫn xanh dương (`#DBEAFE/#1D4ED8`, `#E0E7FF/#4338CA`) — cố ý giữ, đổi thì phải hỏi anh Hi.
- Ngưỡng `html.lite` (≤2 nhân / ≤2GB → nền đứng yên) đặt để máy văn phòng yếu không giật; nếu anh Hi muốn nền động cả trên máy yếu thì bỏ dòng đầu `<script>`.
- Thư mục `Claude outputs/` (ảnh chụp màn hình có số cont thật) và các file nháp PHASE* đang **untracked** — đừng `git add -A`; chỉ add đúng file.
- `canh_bao_thieu_rong()` có trong DB nhưng web chưa gọi.
- Hàm cũ `tao_goi_y()` giữ để đối chiếu, không còn được gọi. Chưa quyết định xoá.
- Cấu hình "Chế độ thử: cho xoá dữ liệu đã chạy": khi chạy chính thức phải đổi thành **Tắt**.
- File nháp `src/app.src.PHASE1-4.html`, `kiem_dich_wizard.PHASE3.js`, `prototype_glassmorphism.html`, `XEM_THU_PHASE4.html` — nội dung đã gộp vào bản thật, có thể xoá khi được yêu cầu.

## Nhật ký phiên

| Ngày | Tài khoản / phiên | Đã làm |
|---|---|---|
| 24/09/2026 (~01:30) | Cowork (tài khoản phụ · nạp Excel) | Nạp chồng "dư liệu hôm nay.xlsx" vào Supabase theo luật Excel-là-chuẩn (anh Hi chốt): 38 lô, 21 cont mới, 611A xoá, 613A→613 / 622→622A, 604B/607B/609E thêm, 617/624 phục hồi (rớt tàu). Sao lưu `private.sao_luu_20260924_truoc_nap`. Viết `tools/nap_excel.py` dùng lại hằng ngày (chạy thử rollback + báo cáo). Chưa commit/push. |
| 24/09/2026 | Cowork (tài khoản phụ · giao diện 3D) | Đổi toàn bộ web sang phong cách kính 3D tím – chàm theo ảnh mẫu anh Hi gửi: viết lại `<style>`, khung kính cố định + `.main` cuộn trong, sidebar sáng, lớp nền `bg3d` (khối màu, quả cầu, cont/tàu/cẩu SVG trôi chậm), chuyển động nhẹ (hover nhấc thẻ, fade đổi tab, ngăn kéo trượt lần mở), fallback reduced-motion + máy yếu. Test mới `test_3d.py` 22/22, bộ cũ xanh. Build tại máy, hash khớp. Chưa commit/push (anh chốt đẩy một lần sau 3D). |
| 23/09/2026 | Cowork (phiên gộp nhánh) | Đối chiếu `only-me/main` ↔ `master`: main nằm trọn trong master (khác gốc, không merge được). Port tay Gợi ý v4 (`d129951`) vào redesign (vGoiY + vWorkflowHub + approveGy + runGoiY). Kiểm tra DB bằng SQL chỉ đọc: `tao_goi_y_v4`, `duyet_phuong_an`, cột `la_phuong_an`/`nhom_gy` đã có; cron đã chạy v4. Thêm migration `20260922120000_goi_y_v4_phuong_an.sql` (SHA khớp DB). Sửa lưới cột Cảng hạ/Cảng đến + nút Tạo tài khoản. Test Playwright 40/40 với 5 lô thật. Commit `a796eba`, Hi đã push `only-me/master` 23/09. |
| 22/09/2026 | Cowork (phiên sửa Cảng hạ + tài khoản) | Sửa bug Cảng hạ hiện nhầm bảng Nhân viên (thiếu nhánh `cangha` trong `vDanhMuc`); sửa luôn bug Cảng đến/Cảng hạ không submit/lưu/xoá được đúng bảng. Bỏ tự đăng ký (`sb.auth.signUp`) khỏi trang đăng nhập. Thêm tab Nhân viên: Quản lý tạo tài khoản (email+mật khẩu+vai trò) và đặt lại mật khẩu cho nhân viên đã có, gọi Edge Function mới `quan-ly-nhan-vien` (đã deploy 23/09). Đọc Excel dữ liệu thật 22/09 lấy 5 lô gần nhất làm ví dụ test. Build lại `index.html`, `node --check` JS OK. Commit `987e679`, đã push `only-me/master`. |
| 22/09/2026 | Cowork (Account 2 · redesign) | **CHỐT Phase 1→4 vào bản thật**: app.src.html + kiem_dich_wizard.js (inline) + build.py (nhúng wizard) + rebuild index.html (tự chứa, test V8 OK). Cập nhật TIEN_DO. Đã push (`ed7d351`). |
| 22/09/2026 | Cowork (Account 2 · redesign) | Phase 4 Container Board + sửa 2 lỗi cú pháp vWorkflowHub (PHASE1/2/3 trắng màn hình) + đổi màu status→blue. Test headless OK. |
| 22/09/2026 | Cowork (Account 2 · redesign) | Phase 3 KD inline, Phase 2 Glassmorphism Blue + prototype, Phase 1 Workflow Hub. |
| 22/09/2026 | Cowork | KD Wizard drawer, rebuild index.html, commit `5e19aff`. |
| 21/09/2026 | Cowork | Đọc lại dự án, tạo `TIEN_DO.md`. |
