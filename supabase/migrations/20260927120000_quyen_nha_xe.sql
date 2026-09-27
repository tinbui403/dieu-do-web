-- Migration: SIẾT QUYỀN TÀI KHOẢN "Nhà xe"
-- Yêu cầu anh Hi 27/09: Nhà xe CHỈ được xem container của CHÍNH nhà xe đó (đang ở đâu),
-- KHÔNG xem được bất kỳ bảng/màn nào khác (khách, kho, giá, booking, lô, danh mục, nhân viên...).
-- Cách làm: chặn Nhà xe đọc mọi bảng (restrictive policy), chỉ mở 1 RPC an toàn cont_cua_toi().
-- An toàn ở lớp DB: kể cả gọi thẳng API, Nhà xe cũng không lấy được dữ liệu ngoài cont của mình.
-- Idempotent: chạy lại nhiều lần vẫn OK.

-- 1) Hàm lấy nhà xe của người đang đăng nhập (definer, chỉ trả nha_xe của chính họ)
create or replace function private.nha_xe_hien_tai()
returns text language sql stable security definer set search_path = '' as $$
  select nv.nha_xe from public.nhan_vien nv
  where nv.email = lower(coalesce(auth.jwt() ->> 'email', '')) and nv.hoat_dong
$$;
revoke execute on function private.nha_xe_hien_tai() from public, anon;
grant execute on function private.nha_xe_hien_tai() to authenticated;

-- 2) toi_la_ai: chuyển sang SECURITY DEFINER để Nhà xe vẫn đăng nhập được
--    (sau khi chặn đọc bảng nhan_vien, hàm invoker sẽ trả rỗng → không vào được app)
drop function if exists public.toi_la_ai();
create or replace function public.toi_la_ai()
returns table (email text, ho_ten text, vai_tro text, ngon_ngu text, nha_xe text)
language sql stable security definer set search_path = '' as $$
  select nv.email, nv.ho_ten, nv.vai_tro, nv.ngon_ngu, nv.nha_xe
  from public.nhan_vien nv
  where nv.email = lower(coalesce(auth.jwt() ->> 'email', '')) and nv.hoat_dong
$$;
revoke execute on function public.toi_la_ai() from public, anon;
grant execute on function public.toi_la_ai() to authenticated;

-- 3) RPC an toàn cho Nhà xe: chỉ cột cần thiết (KHÔNG giá, KHÔNG khách hàng), chỉ cont của họ
create or replace function public.cont_cua_toi()
returns table (
  so_cont text, lo text, trang_thai text, trang_thai_ten text,
  kho text, bai_tam text, ngay_den_kho date, ngay_can_len_kho timestamptz,
  gio_vao_bai timestamptz, cap_nhat_luc timestamptz
)
language sql stable security definer set search_path = '' as $$
  select c.so_cont, c.lo, c.trang_thai,
    case c.trang_thai
      when '1' then 'Đơn chờ lên' when '2' then 'Đang đóng hàng' when '3' then 'Đầy chờ kéo'
      when '4' then 'Ở bãi tạm'  when '5' then 'Đã hạ cảng'     when '6' then 'Đã lên tàu'
      when '9' then 'Hủy/đổi cont' else c.trang_thai end,
    c.kho, c.bai_tam, c.ngay_den_kho, c.ngay_can_len_kho, c.gio_vao_bai, c.cap_nhat_luc
  from public.cont c
  where (select private.nha_xe_hien_tai()) is not null
    and c.nha_xe = (select private.nha_xe_hien_tai())
    and c.trang_thai <> '9'
  order by c.trang_thai, c.so_cont
$$;
revoke execute on function public.cont_cua_toi() from public, anon;
grant execute on function public.cont_cua_toi() to authenticated;

-- 4) Chặn Nhà xe ĐỌC mọi bảng (restrictive: AND với policy đọc sẵn có → Nhà xe = false = bị chặn;
--    vai trò khác không bị ảnh hưởng). Áp cho tất cả bảng dữ liệu, kể cả cont và nhan_vien.
do $$
declare t text;
begin
  foreach t in array array[
    'trang_thai','khach_hang','kho','nha_xe','bai_tam','cang_den','cang_ha','hang_tau',
    'lo','cont','goi_y','booking','chi_phi_cont','nhat_ky','bang_gia_xe','cau_hinh',
    'thong_tin_cu','lo_su_co','nhan_vien','sao_luu_nhat_ky','lo_da_don'
  ] loop
    if to_regclass('public.'||t) is not null then
      execute format('alter table public.%I enable row level security', t);
      execute format('drop policy if exists "chan nha xe doc" on public.%I', t);
      execute format(
        'create policy "chan nha xe doc" on public.%I as restrictive for select to authenticated '
        || 'using (coalesce((select private.vai_tro_hien_tai()), '''') <> ''Nhà xe'')', t);
    end if;
  end loop;
end $$;
