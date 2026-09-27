// SƠ ĐỒ DỮ LIỆU cho chatbot — giúp AI tự hiểu câu hỏi theo nhiều cách nói và tự ghép dữ liệu nhiều bước.
// Viết theo schema thật (supabase/migrations) + công cụ thật (AI_TOOLS trong src/app.src.html) ngày 27/09/2026.
// Khi thêm bảng / cột / công cụ mới: SỬA FILE NÀY cho khớp, rồi deploy lại Edge Function doc-booking-pdf.
// Lưu ý: không dùng dấu backtick và chuỗi dollar-ngoặc-nhọn trong nội dung (đang nằm trong template literal).

export const SO_DO_DU_LIEU = `
SƠ ĐỒ DỮ LIỆU ZADAM — dùng để TỰ SUY LUẬN: hiểu câu hỏi → xác định thực thể → chọn công cụ → ghép kết quả (nhiều bước nếu cần).

[1] THỰC THỂ & QUAN HỆ
BOOKING (khoá so_booking) = chỗ trên tàu do hãng cấp. Cột: hang_tau, ten_tau, chuyen, cang_den, etd, eta, so_luong_cont (= số cont hãng cấp).
  └─ 1 booking → NHIỀU LÔ.
LÔ (khoá lo, vd "614A") = 1 khách + 1 đơn xuất, gắn 1 booking. Cột: khach_hang, so_booking, hang_tau, ten_tau, cang_den, etd, eta, cls, cang_ha, da_kiem_dich, ma_don_kdtv, so_luong_cont (kế hoạch), da_huy.
  Lô giữ BẢN SAO tàu/ETD/ETA của booking và có thể khác booking (sửa riêng, booking đổi không kéo theo lô).
  └─ 1 lô → NHIỀU CONT.
CONT (khoá id; so_cont có thể TRỐNG khi chưa cấp cont rỗng) = 1 container. Cột: lo, ma_don, khach_hang, kho, trang_thai, nha_xe, so_xe, bai_tam, cont_kiem_dich, so_seal, ngay_can_len_kho, ngay_den_kho, gio_vao_bai, gio_ra_bai.
  Cont CHƯA có lô (lo trống, trạng thái 1) = ĐƠN HÀNG MỚI chưa xếp; mang yêu cầu của khách: cang_den_yc, ngay_tau_yc, hang_tau_yc (KHÁC cang_den/etd của lô).
DANH MỤC:
  KHÁCH HÀNG (ten) = chủ hàng.
  KHO (ten; có khu_vuc) = nơi đóng hàng. khu_vuc dùng để gom chuyến kéo.
  NHÀ XE (ma) = đơn vị kéo cont.
  BÃI TẠM (ma: HLS = Hoàng Liên Sơn, PD, HT, DCL…) = nơi hạ cont chờ kiểm dịch / chờ hạ cảng. Có nhà xe kiêm luôn bãi (vd HLS).
  CẢNG ĐẾN (ma: SHA, DAL, KFK…) = cảng nước ngoài hàng tới.
  CẢNG HẠ (ten: Cát Lái, SPITC…) = cảng Việt Nam nơi hạ cont để lên tàu.
  HÃNG TÀU (ma).
SỰ CỐ LÔ: loại "KD không đạt" hoặc "Rớt tàu"; đang mở khi chưa xử lý.
ĐƯỜNG NỐI để ghép dữ liệu: KHÁCH → LÔ → CONT · BOOKING → LÔ → CONT · CONT → KHO → khu_vuc · CONT → BÃI · LÔ → CLS / tàu / cảng hạ.

[2] VÒNG ĐỜI CONT — trạng thái cho biết cont ĐANG Ở ĐÂU
1 Đơn chờ lên (chờ cắt rỗng) → chưa có cont / chưa lên kho (xem ngay_can_len_kho).
2 Đang đóng hàng → đang ở KHO (cột kho).
3 Đầy chờ kéo → đóng xong, VẪN Ở KHO, chờ xe kéo đi (bãi hoặc cảng).
4 Ở bãi tạm → ở BÃI (cột bai_tam), để kiểm dịch hoặc chờ hạ cảng.
5 Đã hạ cảng → ở CẢNG HẠ (lô.cang_ha).
6 Đã lên tàu → đã xuất đi (tàu lô.ten_tau).
9 Hủy/đổi cont → BỎ QUA khi đếm/thống kê, trừ khi người dùng hỏi riêng cont hủy.
"Đang chạy" / "còn hoạt động" / "chưa đi" = trạng thái 1–5. Lô da_huy = đã hủy, bỏ qua trừ khi hỏi riêng.

[3] QUY TẮC NGHIỆP VỤ (đại lượng suy ra — dùng giá trị công cụ trả về, KHÔNG tự tính lại ngày giờ)
- CLS hiệu lực của lô = cls (ưu tiên CLS mail → CLS ePort → CLS nhập tay); trống thì lấy closing; vẫn trống thì lấy (etd − 1 ngày). gio_con_lai ÂM = ĐÃ QUÁ hạn.
- KIỂM DỊCH tính theo LÔ: mỗi lô chỉ có 1 cont mẫu (cont_kiem_dich = true), kiểm tại bãi (HLS/PD/HT). Lô da_kiem_dich = true thì CẢ LÔ coi là đã kiểm. Lô chưa kiểm dịch KHÔNG được hạ cảng / lên tàu.
- Lô đã kiểm dịch: cont đầy ở kho chỉ được hạ THẲNG cảng khi còn ≤ 48 giờ tới CLS; còn lại phải hạ bãi.
- CHỜ HẠ CẢNG = lô đã kiểm dịch + cont trạng thái 4 (ở bãi) + CLS còn ≤ 72 giờ + lô không có sự cố đang mở.
- XẾP ĐƠN = đơn (cont trạng thái 1 chưa lô) → tìm booking phù hợp → tạo lô → gán cont.
- THỪA/THIẾU cont của booking: so so_luong_cont (hãng cấp) với cont_da_xep.
- KÉO CONT: gom cont CÙNG khu_vuc kho, ưu tiên CLS gấp; KHÔNG cần cùng khách. GHÉP LÔ mới cần cùng khách.

[4] CÔNG CỤ ↔ DỮ LIỆU (lấy cái gì ở đâu)
- tra_lo(ma_lo): 1 lô đầy đủ (tàu, CLS, kiểm dịch, khách, booking, số cont) + toàn bộ cont của lô.
- tra_booking(so_booking): booking + cont_ke_hoach / cont_thuc_te / cont_da_xep + các lô thuộc booking.
- tra_cont(tu_khoa): tìm cont theo số cont / mã đơn / mã lô / kho / khách (khớp một phần).
- loc_cont(kho, bai_tam, trang_thai, kiem_dich, lo, khach_hang, nha_xe): lọc cont theo nhiều điều kiện cùng lúc (tối đa 200 dòng). Bỏ trống điều kiện nào = không lọc theo điều kiện đó.
- dem_cont_theo_trang_thai(): số cont từng trạng thái toàn hệ thống.
- lo_toi_han_cls(so_ngay): các lô đã quá / sắp tới CLS trong so_ngay ngày (đã tính CLS hiệu lực, có khách, booking, tàu).
- cont_gap_can_keo(khu_vuc, kho, nha_xe): cont trạng thái 3 kèm khu vực + giờ còn lại tới CLS.
- lo_cho_ha_cang(hoi_het): lô đã kiểm dịch có cont ở bãi, chờ kéo hạ cảng.
- booking_thieu_cont(): booking chưa đủ cont so với số hãng cấp.
- goi_y_booking(cang_den, ngay_tau, hang_tau, so_cont): booking phù hợp cho 1 đơn.
KHÔNG có công cụ cho: giá cước, chi phí phát sinh, lịch sử sửa (nhật ký), thông tin nhân viên → nói thật chatbot chưa tra được, mời xem trên màn hình tương ứng.

[5] CÁCH TỰ SUY LUẬN khi câu hỏi lạ / mỗi người nói một kiểu
B1. Diễn lại câu hỏi bằng khái niệm dữ liệu: hỏi về THỰC THỂ nào (booking / lô / cont / khách / kho / bãi / nhà xe)? ĐIỀU KIỆN gì (trạng thái, vị trí, thời gian/CLS, kiểm dịch)? Muốn ĐẦU RA gì (danh sách, con số, 1 thông tin)?
B2. Chọn công cụ trả đúng thực thể đó. Cần ghép 2 thực thể thì gọi NHIỀU BƯỚC: kết quả bước trước làm đầu vào bước sau.
B3. Tự lọc / đếm / nhóm / sắp xếp tiếp trên kết quả công cụ khi công cụ chưa lọc sẵn (vd chỉ giữ cont có gio_con_lai < 24, nhóm theo khach_hang).
B4. Mỗi câu hỏi có TỐI ĐA khoảng 7 lượt gọi công cụ (mỗi lượt gọi được nhiều công cụ song song) → ưu tiên công cụ trả sẵn NHIỀU dữ liệu một lần (lo_toi_han_cls, loc_cont với ít điều kiện) rồi tự lọc, thay vì gọi tra_lo lần lượt từng lô.
B5. Câu hỏi vẫn có 2 nghĩa mà dữ liệu không phân định được → hỏi lại 1 câu ngắn kèm 2 lựa chọn cụ thể; KHÔNG đoán bừa.
VÍ DỤ:
- "Khách X còn bao nhiêu cont chưa đi?" → loc_cont(khach_hang = X) → đếm cont trạng thái 1–5, tách theo trạng thái.
- "Lô nào sắp cắt máng mà còn cont nằm ở kho?" → lo_toi_han_cls(so_ngay = 3) lấy danh sách lô → loc_cont(trang_thai = 3) (và/hoặc 2) → giữ cont thuộc các lô đó.
- "Bãi HLS đang giữ hàng của những ai?" → loc_cont(bai_tam = HLS, trang_thai = 4) → nhóm theo khach_hang, đếm cont.
- "Booking ABC đủ cont chưa?" → tra_booking(ABC) → so so_luong_cont với cont_da_xep.
- "Cont TGHU1234567 giờ ở đâu?" → tra_cont → đọc trang_thai → trả lời vị trí theo mục [2] (kèm tên kho / bãi / cảng hạ).
- "Nhà xe Y đang chạy mấy cont?" → loc_cont(nha_xe = Y) → đếm cont trạng thái 1–5.

[6] TỪ NGỮ ĐỜI THƯỜNG → KHÁI NIỆM DỮ LIỆU
- "chủ hàng", "khách", "bên hàng" = khach_hang. "xưởng", "nhà máy", "kho khách", "kho đóng" = kho. "bãi", "bãi tạm", "bãi Hoàng Liên Sơn" = bai_tam. "xe", "đội xe", "nhà xe" = nha_xe.
- Mã dạng số + chữ như 614A, 622A = mã LÔ. "đơn", "đơn mới", "đơn chưa xếp" = cont trạng thái 1 chưa có lô.
- "lấy rỗng", "cắt rỗng", "cấp rỗng", "chờ lên kho" = trạng thái 1. "đang đóng", "đang đóng hàng", "đang load" = 2. "đầy", "đóng xong", "chờ xe kéo ở kho" = 3. "về bãi", "hạ bãi", "nằm bãi" = 4. "hạ cảng", "vào cảng" = 5. "lên tàu", "xuất rồi", "tàu chạy rồi", "đi rồi" = 6.
- "cắt máng", "cut-off", "closing", "CLS", "hạn chót" = CLS. "ngày tàu chạy", "ETD" = etd. "ngày tới", "ETA" = eta.
- "KD", "kiểm", "kiểm dịch" = kiểm dịch (theo lô). "rớt tàu" = sự cố lô Rớt tàu. "KD rớt", "không đạt" = sự cố KD không đạt.
- "hôm nay", "mai", "tuần này", "cuối tuần" → quy về NGÀY CỤ THỂ theo THỜI GIAN HIỆN TẠI (giờ Việt Nam) ở cuối prompt, rồi so với etd / CLS.
`;
