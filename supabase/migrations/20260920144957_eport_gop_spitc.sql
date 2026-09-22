-- ============================================================
-- Gộp ePort SPITC (Hiệp Phước) vào quy trình CLS ePort có sẵn.
--  * eport_gui_yeu_cau(): ngoài tra từng tàu trên ePort Cát Lái (SNP), gọi thêm 1 lần
--    lịch tàu SPITC (cả khoảng -3 → +45 ngày).
--  * eport_xu_ly_ket_qua(): tàu nào Cát Lái không có đúng tàu + chuyến (hoặc lỗi kết nối)
--    thì tra trong lịch tàu SPITC mới nhất; khớp tên tàu + số chuyến (bỏ dấu cách, chấm,
--    gạch) → closing_eport = YARD_CLOSE ("SP-ITC COT"), eport_cang = 'SPITC'.
--  * YARD_CLOSE là giờ Việt Nam không kèm múi giờ → đổi đúng sang timestamptz.
--  * Cột mới lo.eport_cang: 'CTL' | 'SPITC' — cảng lấy được CLS ePort.
--  * Bỏ hai hàm + hai lịch chạy SPITC riêng của migration cls_eport_spitc (lọc theo cang_ha
--    đang trống, đọc sai múi giờ, ghi đè ghi chú của job Cát Lái, gọi được bằng khoá công khai).
-- ============================================================

-- 1. Dọn bản thử
select cron.unschedule(jobid) from cron.job where jobname in ('eport-spitc-goi', 'eport-spitc-xu-ly');
drop function if exists public.cap_nhat_eport_spitc();
drop function if exists public.xu_ly_eport_spitc();
delete from private.spitc_req;

-- 2. Cột cảng ePort + đưa ra view
alter table public.lo add column if not exists eport_cang text;
comment on column public.lo.eport_cang is 'Cảng có CLS ePort: CTL (Cát Lái) hoặc SPITC (Hiệp Phước)';

create or replace view public.lo_tong_hop with (security_invoker = true) as
 select l.lo, l.booking, l.hang_tau, l.ten_tau, l.cang_den, l.etd_kho, l.etd, l.eta,
    l.closing, l.closing_mail, l.cang_ha, l.da_kiem_dich, l.da_khai_eport, l.thanh_ly,
    l.cho_keo_ha_cang, l.ma_don_kdtv, l.so_to_khai, l.cskh, l.ghi_chu, l.cap_nhat_luc,
    l.nguoi_cap_nhat, l.so_luong_cont, l.thu_tu, l.da_huy, l.ly_do_huy, l.huy_boi, l.huy_luc,
    l.closing_eport, l.eport_tau, l.eport_chuyen, l.eport_ghi_chu, l.eport_luc,
    l.dong_trong_ngay, l.cls,
    count(c.id) as so_cont,
    count(c.id) filter (where c.trang_thai = any (array['1', '2', '3', '4', '5'])) as so_cont_dang_chay,
    l.eport_cang
   from public.lo l
     left join public.cont c on c.lo = l.lo
  group by l.lo;

-- 3. Chuẩn hoá tên tàu / số chuyến để so khớp: chỉ giữ chữ + số
create or replace function private.chuan_ma(p text)
 returns text language sql immutable set search_path to ''
as $$ select nullif(regexp_replace(upper(coalesce(p, '')), '[^A-Z0-9]', '', 'g'), '') $$;

-- 4. Gửi yêu cầu: Cát Lái từng tàu + SPITC một lần
create or replace function public.eport_gui_yeu_cau()
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r record; t record; v_n int := 0; v_site text;
        v_vn timestamp := now() at time zone 'Asia/Ho_Chi_Minh';
begin
  if auth.uid() is not null and coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ', 'CSKH') then
    raise exception 'Bạn không có quyền cập nhật CLS ePort';
  end if;

  -- SPITC: một lần gọi trả cả lịch tàu
  insert into private.spitc_req (req_id, goi_luc)
  values (net.http_post(
            url := 'https://eport.sp-itc.com.vn/7e47d3928bbec8c5cb9d65a600139a33/c4f822fec11066d1ed15469717e6d9e1.xc',
            body := jsonb_build_object('from_date', to_char(v_vn - interval '3 days', 'YYYY-MM-DD') || ' 00:00:00',
                                       'to_date',   to_char(v_vn + interval '45 days', 'YYYY-MM-DD') || ' 23:59:59'),
            headers := '{"Content-Type":"application/json"}'::jsonb,
            timeout_milliseconds := 20000),
          now());
  delete from private.spitc_req where goi_luc < now() - interval '1 day';

  -- Cát Lái: từng tàu
  v_site := coalesce((select gia_tri from public.cau_hinh where tham_so = 'ePort siteId'), 'CTL');
  for r in
    select distinct private.chuan_ten_tau(l.ten_tau) as tt
    from public.lo l
    where private.chuan_ten_tau(l.ten_tau) is not null and not l.da_huy
      and (coalesce(l.etd, l.etd_kho) >= (now() at time zone 'Asia/Ho_Chi_Minh')::date - 1
           or exists (select 1 from public.cont c where c.lo = l.lo and c.trang_thai in ('1','2','3','4','5')))
  loop
    select * into t from private.tach_ten_tau(r.tt);
    insert into private.eport_yeu_cau (request_id, ten_tau, vessel, voyage)
    values (net.http_post(
              url := 'https://eport.saigonnewport.com.vn/ships/Searcher',
              body := jsonb_build_object('siteId', v_site, 'vesselName', t.vessel),
              headers := '{"Content-Type":"application/json"}'::jsonb,
              timeout_milliseconds := 20000),
            r.tt, t.vessel, t.voyage);
    v_n := v_n + 1;
  end loop;
  return v_n;
end; $function$;

-- 5. Xử lý kết quả: Cát Lái trước, không có thì SPITC
create or replace function public.eport_xu_ly_ket_qua()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set "TimeZone" to 'UTC'
as $function$
declare r record; m jsonb; v_found jsonb; v_cls timestamptz; v_note text; v_xong int := 0; v_doi int := 0; v_cho int; v_rows int;
        v_sp jsonb; v_sp_found jsonb; v_sp_voy text; v_cang text; v_vessel text; v_voyage text;
        v_han text := to_char(now() at time zone 'Asia/Ho_Chi_Minh' - interval '1 day', 'YYYY-MM-DD HH24:MI:SS');
begin
  if auth.uid() is not null and coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ', 'CSKH') then
    raise exception 'Bạn không có quyền cập nhật CLS ePort';
  end if;

  -- Lịch tàu SPITC mới nhất đã trả về
  begin
    select h.content::jsonb into v_sp
    from private.spitc_req s join net._http_response h on h.id = s.req_id
    where h.status_code = 200 and left(ltrim(h.content), 1) = '['
    order by s.goi_luc desc limit 1;
  exception when others then v_sp := null;
  end;
  if jsonb_typeof(v_sp) is distinct from 'array' or jsonb_array_length(v_sp) = 0 then v_sp := null; end if;

  for r in
    select y.request_id, y.ten_tau, y.vessel, y.voyage, h.status_code, h.content, h.error_msg, h.timed_out
    from private.eport_yeu_cau y join net._http_response h on h.id = y.request_id
    where not y.xong
  loop
    v_cls := null; v_note := null; v_found := null; m := null; v_cang := null; v_sp_found := null; v_sp_voy := null;

    -- 5a. ePort Cát Lái (như cũ)
    if r.status_code = 200 then
      begin m := r.content::jsonb; exception when others then m := null; end;
      if m is not null and m ->> 'type' = 'success' and jsonb_typeof(m -> 'model') = 'array' and jsonb_array_length(m -> 'model') > 0 then
        select e into v_found from jsonb_array_elements(m -> 'model') e
         where r.voyage is null
            or regexp_replace(upper(coalesce(e ->> 'IN_OUT_VOYAGE', '')), '[^A-Z0-9]', '', 'g')
               like '%' || regexp_replace(r.voyage, '[^A-Z0-9]', '', 'g') || '%'
         limit 1;
        if v_found is null then
          v_note := 'Sai số chuyến (ePort: ' || (select string_agg(distinct e ->> 'IN_OUT_VOYAGE', ', ') from jsonb_array_elements(m -> 'model') e) || ')';
        else
          begin
            v_cls := (to_timestamp(v_found ->> 'CLOSING_TIME', 'HH24:MI DD/MM/YYYY') at time zone 'UTC') at time zone 'Asia/Ho_Chi_Minh';
            v_cang := 'CTL';
          exception when others then
            v_note := 'Không đọc được CLS ePort: ' || coalesce(v_found ->> 'CLOSING_TIME', '');
          end;
        end if;
      else
        v_note := 'Không tìm thấy tàu trên ePort';
      end if;
    else
      v_note := 'Lỗi kết nối ePort' || coalesce(' ' || r.status_code::text, '') || coalesce(' ' || r.error_msg, '');
    end if;

    -- 5b. Không có CLS Cát Lái → tra lịch tàu SPITC
    if v_cls is null and v_sp is not null then
      v_vessel := private.chuan_ma(coalesce(r.vessel, (private.tach_ten_tau(r.ten_tau)).vessel));
      v_voyage := private.chuan_ma(coalesce(r.voyage, (private.tach_ten_tau(r.ten_tau)).voyage));
      if v_vessel is not null then
        select e into v_sp_found from jsonb_array_elements(v_sp) e
         where private.chuan_ma(e ->> 'ShipName') = v_vessel
           and coalesce(e ->> 'YARD_CLOSE', '') <> ''
           and (v_voyage is null
                or private.chuan_ma(e ->> 'ExVoy') like '%' || v_voyage || '%'
                or private.chuan_ma(e ->> 'ImVoy') like '%' || v_voyage || '%')
         order by (e ->> 'YARD_CLOSE') < v_han, e ->> 'YARD_CLOSE'
         limit 1;
        if v_sp_found is not null then
          begin
            v_cls := ((v_sp_found ->> 'YARD_CLOSE')::timestamp) at time zone 'Asia/Ho_Chi_Minh';
            v_cang := 'SPITC';
            v_note := null;
            v_found := jsonb_build_object(
              'VESSELNAME', v_sp_found ->> 'ShipName',
              'IN_OUT_VOYAGE', case when coalesce(v_sp_found ->> 'ImVoy', '') in ('', coalesce(v_sp_found ->> 'ExVoy', ''))
                                    then v_sp_found ->> 'ExVoy'
                                    else (v_sp_found ->> 'ImVoy') || '/' || coalesce(v_sp_found ->> 'ExVoy', '') end);
          exception when others then
            v_cls := null; v_cang := null;
            v_note := 'Không đọc được CLS SPITC: ' || coalesce(v_sp_found ->> 'YARD_CLOSE', '');
          end;
        elsif v_note = 'Không tìm thấy tàu trên ePort' then
          select string_agg(distinct e ->> 'ExVoy', ', ') into v_sp_voy
            from jsonb_array_elements(v_sp) e where private.chuan_ma(e ->> 'ShipName') = v_vessel;
          v_note := case when v_sp_voy is not null then 'Sai số chuyến (SPITC: ' || v_sp_voy || ')'
                         else 'Không tìm thấy tàu trên ePort Cát Lái và SPITC' end;
        end if;
      end if;
    end if;

    update public.lo l set
      closing_eport = coalesce(v_cls, l.closing_eport),
      eport_tau = coalesce(nullif(trim(v_found ->> 'VESSELNAME'), ''), l.eport_tau),
      eport_chuyen = coalesce(v_found ->> 'IN_OUT_VOYAGE', l.eport_chuyen),
      eport_cang = coalesce(v_cang, l.eport_cang),
      eport_ghi_chu = v_note,
      eport_luc = now()
    where private.chuan_ten_tau(l.ten_tau) = r.ten_tau and not l.da_huy
      and (l.closing_eport is distinct from coalesce(v_cls, l.closing_eport)
           or l.eport_ghi_chu is distinct from v_note
           or l.eport_chuyen is distinct from coalesce(v_found ->> 'IN_OUT_VOYAGE', l.eport_chuyen)
           or l.eport_cang is distinct from coalesce(v_cang, l.eport_cang));
    get diagnostics v_rows = row_count;
    v_doi := v_doi + v_rows;
    update private.eport_yeu_cau
       set xong = true,
           ket_qua = coalesce(to_char(v_cls at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM/YYYY')
                              || case when v_cang = 'SPITC' then ' (SPITC)' else '' end, v_note)
     where request_id = r.request_id;
    v_xong := v_xong + 1;
  end loop;
  select count(*) into v_cho from private.eport_yeu_cau where not xong and gui_luc > now() - interval '5 minutes';
  update private.eport_yeu_cau set xong = true, ket_qua = 'Hết giờ chờ' where not xong and gui_luc <= now() - interval '5 minutes';
  delete from private.eport_yeu_cau where gui_luc < now() - interval '3 days';
  return jsonb_build_object('da_xu_ly', v_xong, 'lo_thay_doi', v_doi, 'con_cho', v_cho);
end; $function$;
