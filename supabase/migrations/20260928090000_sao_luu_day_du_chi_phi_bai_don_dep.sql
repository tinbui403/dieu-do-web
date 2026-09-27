-- ============================================================
-- SAO LƯU ĐẦY ĐỦ + CHI PHÍ BÃI THEO NGÀY + DỌN DẸP TỰ ĐỘNG HẰNG THÁNG (anh Hi chốt phương án C, 28/09/2026)
--  1. sao_luu_du_lieu(p_ma): sao lưu MỌI bảng trong schema public (tự động gồm cả bảng thêm sau này:
--     booking, lo_su_co, chi_phi_cont, bang_gia_xe, thong_tin_cu, lo_da_don…). Trước đây thiếu các bảng này
--     → dọn lô làm MẤT VĨNH VIỄN sự cố + chi phí phát sinh. Giữ nguyên tên/tham số → Apps Script cũ vẫn chạy.
--  2. chi_phi_bai_ngay(p_ma, p_ngay): chi phí từng cont ở từng bãi trong 1 ngày (giờ VN) để Apps Script xuất ra Drive.
--     Cách tính KHỚP màn Bãi tạm: điện = số giờ (làm tròn lên) × giá/giờ; nâng hạ 1 lần; hạ cảng theo giá bãi; + phát sinh.
--     "Trong ngày" = phần phát sinh đúng ngày đó (điện theo giờ trong ngày, nâng hạ ngày vào bãi, hạ cảng ngày ra bãi,
--     phát sinh theo ngày nhập) → cộng các ngày lại = tổng thực tế. Dùng GIÁ BÃI HIỆN TẠI (bảng bai_tam).
--  3. private.don_dep_dinh_ky(): pg_cron chạy 02:00 sáng ngày 2 hằng tháng (giờ VN), sau bản sao lưu ngày 1:
--     nhật ký cũ > N ngày (mặc định 45) · lô đủ điều kiện dọn · booking mồ côi · yêu cầu ePort > 30 ngày ·
--     gợi ý > 60 ngày · lịch sử chạy cron > 14 ngày. CHỈ dọn lô/booking khi đã nằm trong một bản sao lưu
--     ĐẦY ĐỦ của NGÀY 1 (bản được giữ vĩnh viễn trên Drive) sau lần sửa cuối.
--     Tắt được: Danh mục → Cấu hình → "Tự động dọn dẹp hằng tháng" = Tắt.
-- Chạy lại nhiều lần không hỏng.
-- ============================================================

-- ---------- 0. Cấu hình ----------
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values
  ('Tự động dọn dẹp hằng tháng', 'Bật', 'Bật = 02:00 ngày 2 hằng tháng máy tự dọn: nhật ký cũ, lô đã lên tàu quá hạn (đã có bản sao lưu ngày 1), booking không còn lô, yêu cầu ePort cũ, gợi ý cũ. Tắt = không tự dọn.'),
  ('Số ngày giữ nhật ký', '45', 'Tự động dọn giữ lại nhật ký thay đổi trong bấy nhiêu ngày gần nhất (nên ≥ 35 để bản sao lưu ngày 1 hằng tháng luôn chứa đủ nhật ký tháng trước).')
on conflict (tham_so) do nothing;

-- ---------- 1. Sao lưu MỌI bảng public ----------
create or replace function public.sao_luu_du_lieu(p_ma text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r record; v jsonb; t jsonb; dem jsonb := '{}'::jsonb;
begin
  if p_ma is null or encode(extensions.digest(p_ma, 'sha256'), 'hex')
       is distinct from (select b.bam from private.bi_mat b where b.ten = 'sao_luu') then
    raise exception 'Sai mã sao lưu' using errcode = '42501';
  end if;
  v := jsonb_build_object('thoi_diem', now());
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relname !~ '^_' order by c.relname loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.%I x', r.relname) into t;
    v := v || jsonb_build_object(r.relname, t);
    dem := dem || jsonb_build_object(r.relname, jsonb_array_length(t));
  end loop;
  return v || jsonb_build_object('so_dong', dem);
end; $$;
revoke execute on function public.sao_luu_du_lieu(text) from public, authenticated;
grant execute on function public.sao_luu_du_lieu(text) to anon;

-- ---------- 2. Chi phí bãi theo ngày ----------
create or replace function public.chi_phi_bai_ngay(p_ma text, p_ngay date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_ngay date := coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date);
  d0 timestamptz := v_ngay::timestamp at time zone 'Asia/Ho_Chi_Minh';
  d1 timestamptz := (v_ngay + 1)::timestamp at time zone 'Asia/Ho_Chi_Minh';
  v_rows jsonb; v_bai jsonb;
begin
  if p_ma is null or encode(extensions.digest(p_ma, 'sha256'), 'hex')
       is distinct from (select b.bam from private.bi_mat b where b.ten = 'sao_luu') then
    raise exception 'Sai mã sao lưu' using errcode = '42501';
  end if;
  with c as (
    select c.*, b.ten as ten_bai, coalesce(b.dien_moi_gio, 0) as gia_dien, coalesce(b.nang_ha, 0) as gia_nang, coalesce(b.trucking, 0) as gia_ha,
           -- cont đang ở bãi: tính tới hiện tại (giống web); đã rời bãi: tới giờ ra bãi
           coalesce(c.gio_ra_bai, case when c.trang_thai = '4' then now() else c.gio_vao_bai end) as t_het,
           coalesce(l.khach_hang, c.khach_hang) as kh
      from public.cont c
      left join public.bai_tam b on b.ma = c.bai_tam
      left join public.lo l on l.lo = c.lo
     where c.bai_tam is not null and c.gio_vao_bai is not null
       and c.trang_thai not in ('1', '2', '3')
       and c.gio_vao_bai < d1
       and (c.gio_ra_bai is null or c.gio_ra_bai >= d0)
  ), g as (
    select c.*,
      ceil(greatest(0, extract(epoch from (least(d0, c.t_het) - c.gio_vao_bai)) / 3600))::int as h_dau,
      ceil(greatest(0, extract(epoch from (least(d1, c.t_het) - c.gio_vao_bai)) / 3600))::int as h_cuoi,
      coalesce((select sum(p.so_tien) from public.chi_phi_cont p where p.cont_id = c.id), 0) as ps_tong,
      coalesce((select sum(p.so_tien) from public.chi_phi_cont p where p.cont_id = c.id and p.tao_luc >= d0 and p.tao_luc < d1), 0) as ps_ngay
    from c
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'bai', g.bai_tam, 'ten_bai', g.ten_bai, 'so_cont', g.so_cont, 'lo', g.lo, 'khach_hang', g.kh,
      'trang_thai', g.trang_thai, 'kiem_dich', g.cont_kiem_dich, 'gio_vao_bai', g.gio_vao_bai, 'gio_ra_bai', g.gio_ra_bai,
      'gio_trong_ngay', g.h_cuoi - g.h_dau, 'gio_tich_luy', g.h_cuoi,
      'dien_ngay', (g.h_cuoi - g.h_dau) * g.gia_dien,
      'nang_ha_ngay', case when g.gio_vao_bai >= d0 and g.gio_vao_bai < d1 then g.gia_nang else 0 end,
      'ha_cang_ngay', case when g.gio_ra_bai >= d0 and g.gio_ra_bai < d1 then g.gia_ha else 0 end,
      'phat_sinh_ngay', g.ps_ngay,
      'tong_ngay', (g.h_cuoi - g.h_dau) * g.gia_dien
                   + case when g.gio_vao_bai >= d0 and g.gio_vao_bai < d1 then g.gia_nang else 0 end
                   + case when g.gio_ra_bai >= d0 and g.gio_ra_bai < d1 then g.gia_ha else 0 end + g.ps_ngay,
      -- tổng tích luỹ tới cuối ngày: giống cột "Tổng chi phí" trên web (tính cả hạ cảng dự kiến khi còn ở bãi)
      'tong_tich_luy', g.h_cuoi * g.gia_dien + g.gia_nang + g.gia_ha + g.ps_tong
    ) order by g.bai_tam, g.gio_vao_bai, g.so_cont), '[]'::jsonb)
    into v_rows from g;
  select coalesce(jsonb_agg(jsonb_build_object('ma', b.ma, 'ten', b.ten, 'dien_moi_gio', b.dien_moi_gio, 'nang_ha', b.nang_ha, 'ha_cang', b.trucking) order by b.ma), '[]'::jsonb)
    into v_bai from public.bai_tam b;
  return jsonb_build_object('ngay', v_ngay, 'luc', now(), 'bai', v_bai, 'cont', v_rows);
end; $$;
revoke execute on function public.chi_phi_bai_ngay(text, date) from public, authenticated;
grant execute on function public.chi_phi_bai_ngay(text, date) to anon;

-- ---------- 3. Lần sửa cuối của 1 lô (gồm cont, chi phí phát sinh, sự cố) ----------
create or replace function private.lo_sua_cuoi(p_lo text)
returns timestamptz language sql stable security definer set search_path = '' as $$
  select greatest(
    (select l.cap_nhat_luc from public.lo l where l.lo = p_lo),
    (select max(c.cap_nhat_luc) from public.cont c where c.lo = p_lo),
    (select max(p.tao_luc) from public.chi_phi_cont p join public.cont c on c.id = p.cont_id where c.lo = p_lo),
    (select max(greatest(s.bao_luc, s.xu_ly_luc)) from public.lo_su_co s where s.lo = p_lo))
$$;
revoke execute on function private.lo_sua_cuoi(text) from public, anon, authenticated;

-- Nút "Dọn dữ liệu" (tay): chỉ tính bản sao lưu ĐẦY ĐỦ (có so_dong gồm chi_phi_cont) sau lần sửa cuối
create or replace function public.lo_co_the_don()
returns table (lo text, booking text, ten_tau text, etd date, so_cont bigint, sua_cuoi timestamptz, ban_sao_luu text, sao_luu_luc timestamptz)
language sql stable security invoker set search_path = '' as $$
  with ng as (select coalesce((select gia_tri::int from public.cau_hinh where tham_so = 'Số ngày sau ETD được dọn dữ liệu'), 90) as n),
  x as (
    select l.lo, l.booking, l.ten_tau, coalesce(l.etd, l.etd_kho) as etd, count(c.id) as so_cont, private.lo_sua_cuoi(l.lo) as sua_cuoi
    from public.lo l left join public.cont c on c.lo = l.lo
    group by l.lo
    having coalesce(bool_and(c.trang_thai in ('6', '9')), true)
  )
  select x.lo, x.booking, x.ten_tau, x.etd, x.so_cont, x.sua_cuoi, s.ten, s.luc
  from x
  cross join ng
  cross join lateral (select sl.ten, sl.luc from public.sao_luu_nhat_ky sl
                       where sl.luc > x.sua_cuoi and sl.so_dong ? 'chi_phi_cont' order by sl.luc desc limit 1) s
  where x.etd is not null and x.etd < (now() at time zone 'Asia/Ho_Chi_Minh')::date - ng.n
  order by x.etd, x.lo
$$;
revoke execute on function public.lo_co_the_don() from public, anon;
grant execute on function public.lo_co_the_don() to authenticated;
grant execute on function private.lo_sua_cuoi(text) to authenticated;

-- ---------- 4. Dọn dẹp tự động hằng tháng ----------
create or replace function private.don_dep_dinh_ky()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_bat text := coalesce((select trim(gia_tri) from public.cau_hinh where tham_so = 'Tự động dọn dẹp hằng tháng'), 'Bật');
  v_nk int := greatest(coalesce((select case when trim(gia_tri) ~ '^[0-9]+$' then trim(gia_tri)::int end from public.cau_hinh where tham_so = 'Số ngày giữ nhật ký'), 45), 35);
  v_etd int := coalesce((select case when trim(gia_tri) ~ '^[0-9]+$' then trim(gia_tri)::int end from public.cau_hinh where tham_so = 'Số ngày sau ETD được dọn dữ liệu'), 90);
  v_hom_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  r record; n_lo int := 0; n_cont int := 0; n_nk bigint := 0; n_bk int := 0; n_ep int := 0; n_gy int := 0; n_cron int := 0; v_ds text[] := '{}';
begin
  if lower(v_bat) not in ('bật', 'bat', 'on', 'true', '1') then
    return jsonb_build_object('bo_qua', 'Tự động dọn dẹp đang Tắt');
  end if;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'on', true);
  perform set_config('dieu_do.bo_qua_kiem_tra', 'on', true);

  -- a) Lô: mọi cont đã lên tàu/hủy, ETD quá v_etd ngày, có bản sao lưu ngày 1 đầy đủ SAU lần sửa cuối
  for r in
    select l.lo, l.booking, l.ten_tau, coalesce(l.etd, l.etd_kho) as etd, private.lo_sua_cuoi(l.lo) as sua_cuoi,
           (select count(*) from public.cont c where c.lo = l.lo) as so_cont
      from public.lo l
     where coalesce(l.etd, l.etd_kho) < v_hom_nay - v_etd
       and not exists (select 1 from public.cont c where c.lo = l.lo and c.trang_thai not in ('6', '9'))
  loop
    declare v_sl text;
    begin
      select sl.ten into v_sl from public.sao_luu_nhat_ky sl
       where sl.luc > r.sua_cuoi and sl.so_dong ? 'chi_phi_cont'
         and extract(day from (sl.luc at time zone 'Asia/Ho_Chi_Minh')) = 1
       order by sl.luc desc limit 1;
      if v_sl is null then continue; end if;
      insert into public.lo_da_don (lo, booking, ten_tau, etd, so_cont, ban_sao_luu, don_boi)
      values (r.lo, r.booking, r.ten_tau, r.etd, r.so_cont, v_sl, 'tự động hằng tháng')
      on conflict (lo) do update set don_luc = now(), ban_sao_luu = excluded.ban_sao_luu, so_cont = excluded.so_cont, don_boi = excluded.don_boi;
      delete from public.goi_y g where g.id_cont_rong in (select c.id from public.cont c where c.lo = r.lo)
                                   or g.id_cont_day in (select c.id from public.cont c where c.lo = r.lo);
      delete from public.cont c where c.lo = r.lo;          -- chi_phi_cont xoá theo (cascade)
      delete from public.lo l where l.lo = r.lo;            -- lo_su_co, thong_tin_cu xoá theo (cascade)
      n_lo := n_lo + 1; n_cont := n_cont + r.so_cont; v_ds := v_ds || r.lo;
    end;
  end loop;

  -- b) Booking không còn lô nào, tàu đã chạy quá v_etd ngày (hoặc không có ETD và 180 ngày không sửa), đã có bản sao lưu ngày 1
  with x as (
    delete from public.booking b
     where not exists (select 1 from public.lo l where l.so_booking = b.so_booking)
       and ((b.etd is not null and b.etd < v_hom_nay - v_etd) or (b.etd is null and b.cap_nhat_luc < now() - interval '180 days'))
       and exists (select 1 from public.sao_luu_nhat_ky sl where sl.luc > b.cap_nhat_luc and sl.so_dong ? 'chi_phi_cont'
                     and extract(day from (sl.luc at time zone 'Asia/Ho_Chi_Minh')) = 1)
    returning 1)
  select count(*) into n_bk from x;

  -- c) Nhật ký thay đổi cũ (đã nằm trong các bản sao lưu ngày 1)
  with x as (delete from public.nhat_ky where luc < now() - make_interval(days => v_nk) returning 1)
  select count(*) into n_nk from x;

  -- d) Gợi ý kế hoạch cũ > 60 ngày
  with x as (delete from public.goi_y where tao_luc < now() - interval '60 days' returning 1)
  select count(*) into n_gy from x;

  -- e) Yêu cầu tra ePort cũ > 30 ngày
  with x as (delete from private.eport_yeu_cau where gui_luc < now() - interval '30 days' returning 1)
  select count(*) into n_ep from x;

  -- f) Lịch sử chạy cron > 14 ngày (pg_cron không tự xoá)
  begin
    with x as (delete from cron.job_run_details where end_time < now() - interval '14 days' returning 1)
    select count(*) into n_cron from x;
  exception when others then n_cron := -1;
  end;

  perform set_config('dieu_do.bo_qua_nhat_ky', 'off', true);
  perform set_config('dieu_do.bo_qua_kiem_tra', 'off', true);
  perform private.ghi_nhat_ky_tay('he_thong', 'dọn dẹp hằng tháng', 'xoa', jsonb_build_object(
    'lo', n_lo, 'cont', n_cont, 'danh_sach_lo', to_jsonb(v_ds), 'booking', n_bk, 'nhat_ky', n_nk,
    'goi_y', n_gy, 'eport_yeu_cau', n_ep, 'cron_log', n_cron, 'giu_nhat_ky_ngay', v_nk));
  return jsonb_build_object('lo', n_lo, 'cont', n_cont, 'booking', n_bk, 'nhat_ky', n_nk, 'goi_y', n_gy, 'eport_yeu_cau', n_ep, 'cron_log', n_cron);
end; $$;
revoke execute on function private.don_dep_dinh_ky() from public, anon, authenticated;

-- 02:00 sáng ngày 2 hằng tháng giờ VN = 19:00 UTC ngày 1
select cron.unschedule(jobid) from cron.job where jobname = 'don-dep-hang-thang';
select cron.schedule('don-dep-hang-thang', '0 19 1 * *', $$select private.don_dep_dinh_ky();$$);
