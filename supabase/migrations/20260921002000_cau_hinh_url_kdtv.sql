-- Nút "Cập nhật mã KDTV" trên web đọc URL Web App (Apps Script) từ tham số này.
-- Sau khi deploy Apps Script thành Web App, dán chuỗi:  <URL_exec>?token=<KDTV_WEBAPP_TOKEN>
-- vào ô giá trị (Danh mục → Cấu hình → "URL đồng bộ KDTV"). Chỉ Quản lý sửa được (RLS bảng cau_hinh).
insert into public.cau_hinh (tham_so, gia_tri, giai_thich)
values (
  'URL đồng bộ KDTV',
  null,
  'URL Web App Apps Script (kèm ?token=…) cho nút "Cập nhật mã KDTV". Trống = nút báo chưa cấu hình.'
)
on conflict (tham_so) do update set giai_thich = excluded.giai_thich;
