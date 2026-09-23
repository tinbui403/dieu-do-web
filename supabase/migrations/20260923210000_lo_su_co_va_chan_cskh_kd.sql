-- ============================================================
-- LÔ CÓ SỰ CỐ + CHẶN CSKH ĐỔI DẤU CONT KIỂM DỊCH (anh Hi chốt 23/09/2026)
--
-- A. Chặn CSKH: không được bỏ dấu / đổi lô / hủy "Cont kiểm dịch" của lô ĐÃ kiểm dịch
--    (trước đây CSKH làm vậy thì lô tự về chưa kiểm dịch = lùi kiểm dịch vòng).
--
-- B. Lô có sự cố: Quản lý / Điều độ báo sự cố cho lô (KD không đạt – có dịch hại / Rớt tàu)
--    → TOÀN BỘ lô "Đang chờ xử lý": cont giữ nguyên vị trí nhưng khóa: không chuyển trạng thái,
--      không tích kiểm dịch, không sinh gợi ý mới. KD không đạt → tự bỏ tích "Lô đã kiểm dịch".
--    Điều độ / Quản lý xử lý:
--      Rớt tàu      : "Đổi tàu / booking" (bắt nhập Booking, Tàu/chuyến, Hãng tàu, CLS mail, ETD, ETA mới)
--                     hoặc "Hủy lô".
--      KD không đạt : "Đổi cont" (nhập số cont mới thay từng cont; cont cũ → Hủy/đổi cont, cont mới
--                     về Chờ cắt rỗng), "Xông trùng, giữ cont", hoặc "Hủy lô".
--    Thông tin cũ bị thay lưu ở bảng thong_tin_cu (web hiện in nghiêng dưới thông tin mới);
--    chỉ Quản lý sửa / xoá được.
-- ============================================================

-- ---------- 1. Bảng sự cố lô ----------
create table public.lo_su_co (
  id bigint generated always as identity primary key,
  lo text not null references public.lo(lo) on update cascade on delete cascade,
  loai text not null check (loai in ('KD không đạt', 'Rớt tàu')),
  ghi_chu text,
  bao_luc timestamptz not null default now(),
  bao_boi text,
  da_xu_ly boolean not null default false,
  huong_xu_ly text check (huong_xu_ly in ('Đổi tàu / booking', 'Đổi cont', 'Xông trùng, giữ cont', 'Hủy lô')),
  xu_ly_ghi_chu text,
  xu_ly_luc timestamptz,
  xu_ly_boi text
);
create unique index lo_su_co_mot_dang_mo on public.lo_su_co (lo) where not da_xu_ly;
create index lo_su_co_lo_idx on public.lo_su_co (lo);
alter table public.lo_su_co enable row level security;
create policy "nhan vien doc" on public.lo_su_co for select to authenticated
  using ((select private.vai_tro_hien_tai()) is not null);
-- Ghi chỉ qua hàm bao_su_co / xu_ly_su_co (không mở insert/update/delete trực tiếp)
create trigger nk_lo_su_co after insert or update or delete on public.lo_su_co
  for each row execute function private.ghi_nhat_ky('lo');

-- ---------- 2. Thông tin cũ (hiện in nghiêng dưới thông tin mới) ----------
create table public.thong_tin_cu (
  id bigint generated always as identity primary key,
  lo text references public.lo(lo) on update cascade on delete cascade,
  cont_id text references public.cont(id) on update cascade on delete cascade,
  truong text not null,
  gia_tri text,
  ly_do text,
  luc timestamptz not null default now(),
  boi text,
  check ((lo is null) <> (cont_id is null))
);
create index thong_tin_cu_lo_idx on public.thong_tin_cu (lo);
create index thong_tin_cu_cont_idx on public.thong_tin_cu (cont_id);
alter table public.thong_tin_cu enable row level security;
create policy "nhan vien doc" on public.thong_tin_cu for select to authenticated
  using ((select private.vai_tro_hien_tai()) is not null);
create policy "quan ly sua" on public.thong_tin_cu for update to authenticated
  using ((select private.vai_tro_hien_tai()) = 'Quản lý') with check ((select private.vai_tro_hien_tai()) = 'Quản lý');
create policy "quan ly xoa" on public.thong_tin_cu for delete to authenticated
  using ((select private.vai_tro_hien_tai()) = 'Quản lý');
create trigger nk_thong_tin_cu after insert or update or delete on public.thong_tin_cu
  for each row execute function private.ghi_nhat_ky('id');

alter publication supabase_realtime add table public.lo_su_co, public.thong_tin_cu;

-- ---------- 3. Chặn trên cont: khóa lô sự cố + chặn CSKH đổi dấu cont KD ----------
create or replace function private.cont_khoa_su_co_cskh()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare v_loai text;
begin
  if current_setting('dieu_do.bo_qua_kiem_tra', true) = 'on' or current_setting('dieu_do.xu_ly_su_co', true) = 'on' then
    return new;
  end if;
  -- Lô đang có sự cố: không chuyển trạng thái cont
  if new.trang_thai is distinct from old.trang_thai and new.lo is not null then
    select s.loai into v_loai from public.lo_su_co s where s.lo = new.lo and not s.da_xu_ly;
    if found then
      raise exception 'Lô % đang có sự cố (%) — chờ Điều độ xử lý xong mới chuyển trạng thái cont được.', new.lo, v_loai;
    end if;
  end if;
  -- CSKH không được bỏ dấu / đổi lô / hủy cont kiểm dịch của lô đã kiểm dịch
  if coalesce(private.vai_tro_hien_tai(), '') = 'CSKH' and coalesce(old.cont_kiem_dich, false)
     and (not coalesce(new.cont_kiem_dich, false) or new.lo is distinct from old.lo
          or (new.trang_thai = '9' and old.trang_thai is distinct from '9'))
     and exists (select 1 from public.lo l where l.lo = old.lo and l.da_kiem_dich) then
    raise exception 'Lô % đã kiểm dịch: CSKH không được bỏ dấu / đổi lô / hủy cont kiểm dịch — báo Điều độ xử lý.', old.lo;
  end if;
  return new;
end;
$function$;
revoke execute on function private.cont_khoa_su_co_cskh() from public, anon, authenticated;
create trigger cont_khoa_su_co_cskh before update on public.cont
  for each row execute function private.cont_khoa_su_co_cskh();

-- ---------- 4. Chặn trên lô: đang sự cố thì không tích kiểm dịch ----------
create or replace function private.lo_khoa_su_co()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  if current_setting('dieu_do.bo_qua_kiem_tra', true) = 'on' or current_setting('dieu_do.xu_ly_su_co', true) = 'on' then
    return new;
  end if;
  if coalesce(new.da_kiem_dich, false) and not coalesce(old.da_kiem_dich, false)
     and exists (select 1 from public.lo_su_co s where s.lo = new.lo and not s.da_xu_ly) then
    raise exception 'Lô % đang có sự cố — xử lý xong mới tích "Lô đã kiểm dịch" được.', new.lo;
  end if;
  return new;
end;
$function$;
revoke execute on function private.lo_khoa_su_co() from public, anon, authenticated;
create trigger lo_khoa_su_co before update on public.lo
  for each row execute function private.lo_khoa_su_co();

-- ---------- 5. Gợi ý: không sinh gợi ý cho cont của lô đang sự cố ----------
create or replace function private.goi_y_bo_lo_su_co()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  if exists (select 1 from public.cont c join public.lo_su_co s on s.lo = c.lo and not s.da_xu_ly
             where c.id = new.id_cont_rong or c.id = new.id_cont_day) then
    return null;  -- bỏ qua dòng gợi ý này
  end if;
  return new;
end;
$function$;
revoke execute on function private.goi_y_bo_lo_su_co() from public, anon, authenticated;
create trigger goi_y_bo_lo_su_co before insert on public.goi_y
  for each row execute function private.goi_y_bo_lo_su_co();

-- ---------- 6. Báo sự cố ----------
create or replace function public.bao_su_co(p_lo text, p_loai text, p_ghi_chu text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ') then
    raise exception 'Chỉ Quản lý hoặc Điều độ được báo sự cố lô';
  end if;
  if p_loai is null or p_loai not in ('KD không đạt', 'Rớt tàu') then
    raise exception 'Chọn loại sự cố: KD không đạt hoặc Rớt tàu';
  end if;
  if not exists (select 1 from public.lo where lo = p_lo) then
    raise exception 'Không tìm thấy lô %', p_lo;
  end if;
  if exists (select 1 from public.lo where lo = p_lo and da_huy) then
    raise exception 'Lô % đã hủy', p_lo;
  end if;
  if exists (select 1 from public.lo_su_co where lo = p_lo and not da_xu_ly) then
    raise exception 'Lô % đang có sự cố chưa xử lý', p_lo;
  end if;
  insert into public.lo_su_co (lo, loai, ghi_chu, bao_boi)
  values (p_lo, p_loai, nullif(trim(coalesce(p_ghi_chu, '')), ''), auth.jwt() ->> 'email');
  if p_loai = 'KD không đạt' then
    perform set_config('dieu_do.tu_bo_kd', 'on', true);
    update public.lo set da_kiem_dich = false where lo = p_lo and da_kiem_dich;
    perform set_config('dieu_do.tu_bo_kd', 'off', true);
  end if;
  -- Bỏ các gợi ý CHƯA duyệt của lô (gợi ý đã duyệt giữ lại; cont bị khóa nên không chạy được)
  delete from public.goi_y
   where not duyet
     and (id_cont_rong in (select id from public.cont where lo = p_lo) or id_cont_day in (select id from public.cont where lo = p_lo));
end;
$$;
revoke execute on function public.bao_su_co(text, text, text) from public, anon;
grant execute on function public.bao_su_co(text, text, text) to authenticated;

-- ---------- 7. Xử lý sự cố ----------
create or replace function public.xu_ly_su_co(p_lo text, p_huong text, p_du_lieu jsonb, p_ghi_chu text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  s record; r record; c record; x jsonb;
  v_n int := 0; v_moi_id text; v_so text; v_seal text; v_ly text;
  v_booking text; v_tau text; v_hang text; v_cls timestamptz; v_etd date; v_eta date; v_can timestamptz;
  v_ghi text := nullif(trim(coalesce(p_ghi_chu, '')), '');
  v_who text := auth.jwt() ->> 'email';
begin
  if coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ') then
    raise exception 'Chỉ Quản lý hoặc Điều độ được xử lý sự cố lô';
  end if;
  select * into s from public.lo_su_co where lo = p_lo and not da_xu_ly;
  if not found then
    raise exception 'Lô % không có sự cố đang chờ xử lý', p_lo;
  end if;
  perform set_config('dieu_do.xu_ly_su_co', 'on', true);

  if p_huong = 'Đổi tàu / booking' then
    if s.loai <> 'Rớt tàu' then raise exception 'Đổi tàu / booking chỉ dùng cho sự cố Rớt tàu'; end if;
    v_booking := nullif(trim(coalesce(p_du_lieu ->> 'booking', '')), '');
    v_tau := nullif(trim(coalesce(p_du_lieu ->> 'ten_tau', '')), '');
    v_hang := nullif(trim(coalesce(p_du_lieu ->> 'hang_tau', '')), '');
    v_cls := nullif(trim(coalesce(p_du_lieu ->> 'closing_mail', '')), '')::timestamptz;
    v_etd := nullif(trim(coalesce(p_du_lieu ->> 'etd', '')), '')::date;
    v_eta := nullif(trim(coalesce(p_du_lieu ->> 'eta', '')), '')::date;
    if v_booking is null or v_tau is null or v_cls is null then
      raise exception 'Rớt tàu: cần nhập Booking mới, Tàu / chuyến mới và CLS mail mới';
    end if;
    select * into r from public.lo where lo = p_lo;
    v_ly := 'Rớt tàu ' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY');
    insert into public.thong_tin_cu (lo, truong, gia_tri, ly_do, boi)
    select p_lo, t.truong, t.cu, v_ly, v_who
      from (values
        ('booking', r.booking, v_booking),
        ('ten_tau', r.ten_tau, v_tau),
        ('hang_tau', r.hang_tau, v_hang),
        ('closing_mail', to_char(r.closing_mail at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI'), to_char(v_cls at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')),
        ('etd', to_char(r.etd, 'DD/MM/YYYY'), to_char(v_etd, 'DD/MM/YYYY')),
        ('eta', to_char(r.eta, 'DD/MM/YYYY'), to_char(v_eta, 'DD/MM/YYYY'))
      ) t(truong, cu, moi)
     where t.cu is not null and t.cu is distinct from t.moi;
    get diagnostics v_n = row_count;
    -- Tàu mới: xoá kết quả ePort của tàu cũ để lần tra ePort kế tiếp tra theo tàu mới
    update public.lo
       set booking = v_booking, ten_tau = v_tau, hang_tau = v_hang, closing_mail = v_cls, etd = v_etd, eta = v_eta,
           closing_eport = null, eport_tau = null, eport_chuyen = null, eport_cang = null, eport_ghi_chu = null
     where lo = p_lo;

  elsif p_huong = 'Đổi cont' then
    if s.loai <> 'KD không đạt' then raise exception 'Đổi cont chỉ dùng cho sự cố KD không đạt'; end if;
    v_can := nullif(trim(coalesce(p_du_lieu ->> 'ngay_can_len_kho', '')), '')::timestamptz;
    v_ly := 'KD không đạt – đổi cont ' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY');
    for x in select * from jsonb_array_elements(coalesce(p_du_lieu -> 'conts', '[]'::jsonb)) loop
      v_so := upper(nullif(trim(coalesce(x ->> 'so_cont', '')), ''));
      continue when v_so is null;
      v_seal := nullif(trim(coalesce(x ->> 'so_seal', '')), '');
      select * into c from public.cont where id = x ->> 'id' and lo = p_lo and trang_thai <> '9';
      if not found then raise exception 'Cont % không thuộc lô % (hoặc đã hủy)', x ->> 'id', p_lo; end if;
      -- Gợi ý của cont cũ: bỏ duyệt (chưa chạy) rồi xoá
      update public.goi_y set duyet = false where duyet and not da_ap_dung and (id_cont_rong = c.id or id_cont_day = c.id);
      delete from public.goi_y where not duyet and (id_cont_rong = c.id or id_cont_day = c.id);
      -- Cont cũ → Hủy / đổi cont (giữ lịch sử, chi phí bãi)
      update public.cont
         set trang_thai = '9', ghi_chu = concat_ws(' · ', nullif(ghi_chu, ''), 'Đổi cont (KD không đạt) → ' || v_so)
       where id = c.id;
      -- Cont mới về Chờ cắt rỗng
      insert into public.cont (lo, ma_don, khach_hang, kho, so_cont, so_seal, trang_thai, ngay_goi_cont,
                               ngay_can_len_kho, gio_len_kho_ghi_chu, can_tem, cont_kiem_dich, cskh, nguon)
      values (c.lo, c.ma_don, c.khach_hang, c.kho, v_so, v_seal, '1', (now() at time zone 'Asia/Ho_Chi_Minh')::date,
              v_can, c.gio_len_kho_ghi_chu, c.can_tem, c.cont_kiem_dich, c.cskh, 'Đổi cont từ ' || coalesce(c.so_cont, c.id))
      returning id into v_moi_id;
      insert into public.thong_tin_cu (cont_id, truong, gia_tri, ly_do, boi)
      select v_moi_id, t.truong, t.cu, v_ly, v_who
        from (values ('so_cont', c.so_cont), ('so_seal', c.so_seal)) t(truong, cu)
       where t.cu is not null;
      v_n := v_n + 1;
    end loop;
    if v_n = 0 then raise exception 'Đổi cont: chưa nhập số cont mới nào'; end if;

  elsif p_huong = 'Xông trùng, giữ cont' then
    if s.loai <> 'KD không đạt' then raise exception 'Xông trùng chỉ dùng cho sự cố KD không đạt'; end if;
    if v_ghi is null then raise exception 'Ghi cách xử lý (xông trùng ở đâu, khi nào)'; end if;

  elsif p_huong = 'Hủy lô' then
    perform public.huy_lo(p_lo, coalesce(v_ghi, 'Sự cố: ' || s.loai));

  else
    raise exception 'Hướng xử lý không hợp lệ: %', p_huong;
  end if;

  update public.lo_su_co
     set da_xu_ly = true, huong_xu_ly = p_huong, xu_ly_ghi_chu = v_ghi, xu_ly_luc = now(), xu_ly_boi = v_who
   where id = s.id;
  perform set_config('dieu_do.xu_ly_su_co', 'off', true);
  return v_n;
end;
$$;
revoke execute on function public.xu_ly_su_co(text, text, jsonb, text) from public, anon;
grant execute on function public.xu_ly_su_co(text, text, jsonb, text) to authenticated;
