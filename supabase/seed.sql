-- Dữ liệu khởi tạo tối thiểu để hệ thống chạy được (trạng thái + tham số).
-- Danh mục kho, nhà xe, khách hàng, cont, lô... là dữ liệu kinh doanh — KHÔNG để trong repo.

-- Trạng thái cont 1→6, 9
insert into public.trang_thai (ma, ten_vi, ten_zh, thu_tu, y_nghia) values ('1', 'Chờ cắt rỗng', '待提空', 1, 'Đã có đơn, chưa đưa cont rỗng tới kho');
insert into public.trang_thai (ma, ten_vi, ten_zh, thu_tu, y_nghia) values ('2', 'Đang đóng hàng', '装货中', 2, 'Cont rỗng đã ở kho, đang đóng hàng');
insert into public.trang_thai (ma, ten_vi, ten_zh, thu_tu, y_nghia) values ('3', 'Đầy chờ kéo', '已装满待拉回', 3, 'Đã đóng đầy, chờ xe tới kéo');
insert into public.trang_thai (ma, ten_vi, ten_zh, thu_tu, y_nghia) values ('4', 'Ở bãi tạm', '堆场插电', 4, 'Đang ở bãi tạm (HLS/HT/PD/DCL) cắm điện, seal tạm');
insert into public.trang_thai (ma, ten_vi, ten_zh, thu_tu, y_nghia) values ('5', 'Đã hạ cảng', '已回港待登船', 5, 'Đã hạ cảng, chờ lên tàu');
insert into public.trang_thai (ma, ten_vi, ten_zh, thu_tu, y_nghia) values ('6', 'Đã lên tàu', '已登船走船', 6, 'Tàu đã chạy');
insert into public.trang_thai (ma, ten_vi, ten_zh, thu_tu, y_nghia) values ('9', 'Hủy đổi cont', '取消换柜', 9, 'Hủy đơn hoặc đã đổi sang cont khác');

-- Tham số cho hàm gợi ý kế hoạch
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values ('Bãi tạm mặc định', 'HLS', 'Bãi hạ seal tạm khi chưa hạ thẳng cảng');
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values ('Giờ đóng hàng ước tính', '24', 'Nếu chưa nhập "Dự kiến đầy" thì lấy Ngày cont đến kho + số giờ này');
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values ('Giờ trước closing hạ thẳng cảng', '36', 'Nếu còn ít hơn số giờ này tới closing (và không vướng kiểm dịch) thì gợi ý seal chính hạ cảng');
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values ('ID file gốc', '', 'File "Điều Độ" cũ (chỉ đọc)');
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values ('Khung kế hoạch (giờ tới)', '36', 'Gợi ý cho cont đầy/cần rỗng trong bấy nhiêu giờ tới');
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values ('Số ngày giữ gợi ý đã duyệt', '3', 'Cont nằm trong gợi ý đã duyệt trong bấy nhiêu ngày sẽ không bị gợi ý lại');
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values ('Số ngày tính nhà xe quen', '45', 'Gợi ý nhà xe hay chạy kho đó trong bấy nhiêu ngày gần nhất');
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values ('Trang tính gốc', 'MỚI ĐIỀU ĐỘ', 'Trang nhập tay trong file cũ');

-- Tài khoản quản lý đầu tiên (đổi email nếu cài cho công ty khác)
insert into public.nhan_vien (email, ho_ten, vai_tro, ngon_ngu) values ('tinbui403@gmail.com', 'Tín', 'Quản lý', 'vi');
