create policy "quan ly them" on public.lo_da_don for insert to authenticated with check ((select private.vai_tro_hien_tai()) = 'Quản lý');
create policy "quan ly sua" on public.lo_da_don for update to authenticated using ((select private.vai_tro_hien_tai()) = 'Quản lý') with check ((select private.vai_tro_hien_tai()) = 'Quản lý');

create or replace function private.ghi_nhat_ky_tay(p_bang text, p_khoa text, p_hanh_dong text, p_thay_doi jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.nhat_ky (bang, khoa, hanh_dong, thay_doi, nguoi)
  values (p_bang, p_khoa, p_hanh_dong, p_thay_doi, coalesce(auth.jwt() ->> 'email', 'hệ thống'));
$$;
revoke execute on function private.ghi_nhat_ky_tay(text, text, text, jsonb) from public, anon;
grant execute on function private.ghi_nhat_ky_tay(text, text, text, jsonb) to authenticated;

create or replace function public.don_du_lieu(p_ds text[])
returns integer language plpgsql security invoker set search_path = '' as $$
declare r record; v_n int := 0;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được dọn dữ liệu';
  end if;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'on', true);
  for r in select * from public.lo_co_the_don() d where d.lo = any(p_ds) loop
    insert into public.lo_da_don (lo, booking, ten_tau, etd, so_cont, ban_sao_luu, don_boi)
    values (r.lo, r.booking, r.ten_tau, r.etd, r.so_cont, r.ban_sao_luu, auth.jwt() ->> 'email')
    on conflict (lo) do update set don_luc = now(), ban_sao_luu = excluded.ban_sao_luu, so_cont = excluded.so_cont;
    delete from public.goi_y g where g.id_cont_rong in (select c.id from public.cont c where c.lo = r.lo)
                                 or g.id_cont_day in (select c.id from public.cont c where c.lo = r.lo);
    delete from public.cont where lo = r.lo;
    delete from public.lo where lo = r.lo;
    v_n := v_n + 1;
  end loop;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'off', true);
  perform private.ghi_nhat_ky_tay('lo', 'dọn dữ liệu', 'xoa', jsonb_build_object('so_lo', v_n, 'danh_sach', to_jsonb(p_ds)));
  return v_n;
end; $$;
revoke execute on function public.don_du_lieu(text[]) from public, anon;
grant execute on function public.don_du_lieu(text[]) to authenticated;

-- Ghi nhận bản sao lưu đầu tiên (20/09/2026 15:02) đã chạy trước khi có bảng này
insert into public.sao_luu_nhat_ky (ten, url, luc)
values ('Sao lưu Supabase 20-09-2026', 'https://docs.google.com/spreadsheets/d/1_7HN-Ntd4O0N_v4VLGV0P3IJ1W5P-9raI2-7H291oO8/edit', '2026-09-20 08:02:15+00');
