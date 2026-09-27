-- Migration: xoá hàng loạt cho Quản lý (không điều kiện, không hỏi)
--   xoa_booking(ds)        : xoá các booking đã chọn + toàn bộ lô/cont/gợi ý thuộc booking đó
--   xoa_toan_bo_booking()  : xoá HẾT booking + lô + cont + gợi ý (làm trống vận hành)
--   xoa_lo_hang_loat(ds)   : xoá các lô đã chọn + cont/gợi ý thuộc lô (mọi trạng thái, kể cả đã lên tàu)
-- Chỉ Quản lý. lo_su_co / chi_phi tự xoá theo ON DELETE CASCADE; goi_y xoá tay (id_cont ON DELETE SET NULL).

create or replace function public.xoa_booking(p_ds text[])
returns integer language plpgsql security invoker set search_path = '' as $$
declare v_n int := 0;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then raise exception 'Chỉ Quản lý mới được xoá'; end if;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'on', true);
  delete from public.goi_y g where g.id_cont_rong in (select c.id from public.cont c join public.lo l on c.lo = l.lo where l.so_booking = any(p_ds))
                                or g.id_cont_day in (select c.id from public.cont c join public.lo l on c.lo = l.lo where l.so_booking = any(p_ds));
  delete from public.cont where lo in (select lo from public.lo where so_booking = any(p_ds));
  delete from public.lo where so_booking = any(p_ds);
  delete from public.booking where so_booking = any(p_ds);
  get diagnostics v_n = row_count;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'off', true);
  perform private.ghi_nhat_ky_tay('booking', 'xoá booking đã chọn', 'xoa', jsonb_build_object('danh_sach', to_jsonb(p_ds)));
  return v_n;
end; $$;
revoke execute on function public.xoa_booking(text[]) from public, anon;
grant execute on function public.xoa_booking(text[]) to authenticated;

create or replace function public.xoa_toan_bo_booking()
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare n_goiy int; n_cont int; n_lo int; n_bk int;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then raise exception 'Chỉ Quản lý mới được xoá'; end if;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'on', true);
  delete from public.goi_y; get diagnostics n_goiy = row_count;
  delete from public.cont;   get diagnostics n_cont = row_count;
  delete from public.lo;     get diagnostics n_lo = row_count;
  delete from public.booking;get diagnostics n_bk = row_count;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'off', true);
  perform private.ghi_nhat_ky_tay('booking', 'xoá TOÀN BỘ booking + lô + cont', 'xoa', jsonb_build_object('goi_y', n_goiy, 'cont', n_cont, 'lo', n_lo, 'booking', n_bk));
  return jsonb_build_object('goi_y', n_goiy, 'cont', n_cont, 'lo', n_lo, 'booking', n_bk);
end; $$;
revoke execute on function public.xoa_toan_bo_booking() from public, anon;
grant execute on function public.xoa_toan_bo_booking() to authenticated;

create or replace function public.xoa_lo_hang_loat(p_ds text[])
returns integer language plpgsql security invoker set search_path = '' as $$
declare v_n int := 0;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then raise exception 'Chỉ Quản lý mới được xoá'; end if;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'on', true);
  delete from public.goi_y g where g.id_cont_rong in (select c.id from public.cont c where c.lo = any(p_ds))
                                or g.id_cont_day in (select c.id from public.cont c where c.lo = any(p_ds));
  delete from public.cont where lo = any(p_ds);
  delete from public.lo where lo = any(p_ds);
  get diagnostics v_n = row_count;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'off', true);
  perform private.ghi_nhat_ky_tay('lo', 'xoá lô đã chọn (hàng loạt)', 'xoa', jsonb_build_object('danh_sach', to_jsonb(p_ds)));
  return v_n;
end; $$;
revoke execute on function public.xoa_lo_hang_loat(text[]) from public, anon;
grant execute on function public.xoa_lo_hang_loat(text[]) to authenticated;
