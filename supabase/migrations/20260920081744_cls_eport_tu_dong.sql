-- CLS tự động từ ePort SNP (Cát Lái): gửi yêu cầu theo tên tàu + số chuyến, cập nhật hàng loạt mọi lô cùng tàu/chuyến
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values
  ('ePort siteId', 'CTL', 'Mã cảng trên ePort SNP để tra CLS (CTL = Cát Lái)')
on conflict (tham_so) do nothing;

create table private.eport_yeu_cau (
  request_id bigint primary key,
  ten_tau text not null,
  vessel text not null,
  voyage text,
  gui_luc timestamptz not null default now(),
  xong boolean not null default false,
  ket_qua text
);

create or replace function private.chuan_ten_tau(p text)
returns text language sql immutable set search_path = '' as $$
  select nullif(upper(regexp_replace(trim(coalesce(p, '')), '\s+', ' ', 'g')), '')
$$;

-- Tách "XIN AN 71/N" → tàu "XIN AN", chuyến "71/N" (chữ cuối có số là số chuyến)
create or replace function private.tach_ten_tau(p text, out vessel text, out voyage text)
language plpgsql immutable set search_path = '' as $$
declare t text := private.chuan_ten_tau(p); parts text[]; n int;
begin
  parts := string_to_array(t, ' ');
  n := coalesce(array_length(parts, 1), 0);
  if n > 1 and parts[n] ~ '[0-9]' then
    voyage := parts[n];
    vessel := array_to_string(parts[1:n - 1], ' ');
  else
    vessel := t; voyage := null;
  end if;
end; $$;

create or replace function public.eport_gui_yeu_cau()
returns integer language plpgsql security definer set search_path = '' as $$
declare r record; t record; v_n int := 0; v_site text;
begin
  if auth.uid() is not null and coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ', 'CSKH') then
    raise exception 'Bạn không có quyền cập nhật CLS ePort';
  end if;
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
end; $$;
revoke execute on function public.eport_gui_yeu_cau() from public, anon;
grant execute on function public.eport_gui_yeu_cau() to authenticated;

create or replace function public.eport_xu_ly_ket_qua()
returns jsonb language plpgsql security definer
set search_path = '' set "TimeZone" = 'UTC' as $$
declare r record; m jsonb; v_found jsonb; v_cls timestamptz; v_note text; v_xong int := 0; v_doi int := 0; v_cho int; v_rows int;
begin
  if auth.uid() is not null and coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ', 'CSKH') then
    raise exception 'Bạn không có quyền cập nhật CLS ePort';
  end if;
  for r in
    select y.request_id, y.ten_tau, y.voyage, h.status_code, h.content, h.error_msg, h.timed_out
    from private.eport_yeu_cau y join net._http_response h on h.id = y.request_id
    where not y.xong
  loop
    v_cls := null; v_note := null; v_found := null; m := null;
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

    update public.lo l set
      closing_eport = coalesce(v_cls, l.closing_eport),
      eport_tau = coalesce(nullif(trim(v_found ->> 'VESSELNAME'), ''), l.eport_tau),
      eport_chuyen = coalesce(v_found ->> 'IN_OUT_VOYAGE', l.eport_chuyen),
      eport_ghi_chu = v_note,
      eport_luc = now()
    where private.chuan_ten_tau(l.ten_tau) = r.ten_tau and not l.da_huy
      and (l.closing_eport is distinct from coalesce(v_cls, l.closing_eport)
           or l.eport_ghi_chu is distinct from v_note
           or l.eport_chuyen is distinct from coalesce(v_found ->> 'IN_OUT_VOYAGE', l.eport_chuyen));
    get diagnostics v_rows = row_count;
    v_doi := v_doi + v_rows;
    update private.eport_yeu_cau
       set xong = true, ket_qua = coalesce(to_char(v_cls at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM/YYYY'), v_note)
     where request_id = r.request_id;
    v_xong := v_xong + 1;
  end loop;
  select count(*) into v_cho from private.eport_yeu_cau where not xong and gui_luc > now() - interval '5 minutes';
  update private.eport_yeu_cau set xong = true, ket_qua = 'Hết giờ chờ' where not xong and gui_luc <= now() - interval '5 minutes';
  delete from private.eport_yeu_cau where gui_luc < now() - interval '3 days';
  return jsonb_build_object('da_xu_ly', v_xong, 'lo_thay_doi', v_doi, 'con_cho', v_cho);
end; $$;
revoke execute on function public.eport_xu_ly_ket_qua() from public, anon;
grant execute on function public.eport_xu_ly_ket_qua() to authenticated;

-- Lần tra ePort gần nhất (để hiện trên web)
create or replace function public.eport_trang_thai()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'lan_cuoi', (select max(gui_luc) from private.eport_yeu_cau),
    'so_tau', (select count(*) from private.eport_yeu_cau where gui_luc > (select max(gui_luc) - interval '2 minutes' from private.eport_yeu_cau)),
    'ket_qua', (select jsonb_agg(jsonb_build_object('tau', ten_tau, 'kq', ket_qua) order by ten_tau)
                from private.eport_yeu_cau where gui_luc > (select max(gui_luc) - interval '2 minutes' from private.eport_yeu_cau)))
  where coalesce(private.vai_tro_hien_tai(), '') <> '' or auth.uid() is null
$$;
revoke execute on function public.eport_trang_thai() from public, anon;
grant execute on function public.eport_trang_thai() to authenticated;

-- Tự chạy mỗi giờ: phút 20 gửi, phút 22 xử lý (trước lần gợi ý kế hoạch phút 05 của giờ sau)
select cron.schedule('cls-eport-gui', '20 * * * *', $$select public.eport_gui_yeu_cau();$$);
select cron.schedule('cls-eport-xu-ly', '22 * * * *', $$select public.eport_xu_ly_ket_qua();$$);
