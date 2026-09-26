-- Migration: dọn nhật ký thay đổi cũ (nhat_ky) — giảm phình bảng theo thời gian
-- An toàn: chỉ xoá bản ghi nhật ký cũ hơn N ngày (mặc định 30). KHÔNG đụng dữ liệu cont/lô/booking.
-- Chỉ Quản lý mới được chạy. Có hàm đếm trước để web hiển thị số dòng sẽ xoá.

-- Đếm số dòng nhật ký cũ hơn N ngày (để xem trước khi dọn)
create or replace function public.dem_nhat_ky_cu(p_ngay int default 30)
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$
  select count(*)
  from public.nhat_ky
  where luc < (now() - make_interval(days => greatest(coalesce(p_ngay, 30), 1)))
$$;
revoke execute on function public.dem_nhat_ky_cu(int) from public, anon;
grant execute on function public.dem_nhat_ky_cu(int) to authenticated;

-- Xoá nhật ký cũ hơn N ngày. Chỉ Quản lý. Trả về số dòng đã xoá.
create or replace function public.don_nhat_ky_cu(p_ngay int default 30)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_ngay int := greatest(coalesce(p_ngay, 30), 1);
  v_n bigint := 0;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được dọn nhật ký';
  end if;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'on', true);
  with da_xoa as (
    delete from public.nhat_ky
    where luc < (now() - make_interval(days => v_ngay))
    returning 1
  )
  select count(*) into v_n from da_xoa;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'off', true);
  perform private.ghi_nhat_ky_tay(
    'nhat_ky', 'dọn nhật ký', 'xoa',
    jsonb_build_object('so_dong_xoa', v_n, 'giu_lai_ngay', v_ngay)
  );
  return v_n;
end;
$$;
revoke execute on function public.don_nhat_ky_cu(int) from public, anon;
grant execute on function public.don_nhat_ky_cu(int) to authenticated;
