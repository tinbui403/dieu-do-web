-- ============================================================
-- BOOKING / LÔ / ĐƠN HÀNG — mô hình mới (anh Hi chốt 24/09/2026, xem TIEN_DO "KẾ HOẠCH XÂY LẠI")
--  - Booking là bảng riêng: số booking, hãng, tàu, chuyến, cảng đến, ETD, ETA, tổng số cont. 1 booking → nhiều lô.
--  - Lô = 1 khách = 1 đơn; lô giữ BẢN SAO tàu/ETD/ETA để sửa riêng (booking đổi KHÔNG tự kéo theo lô).
--    lo.booking (chữ, web cũ) và lo.so_booking (khoá) được trigger đồng bộ 2 chiều; lô nhập booking lạ → tự tạo booking.
--    Lô vừa gắn booking: ô nào trống thì chép từ booking (điền sẵn), ô đã có thì giữ.
--  - Đơn hàng = cont "Chờ cắt rỗng": thêm ngày đặt hàng + cảng đến / ngày tàu / hãng YÊU CẦU (để tìm booking khi chưa có lô).
--  - goi_y_booking(): máy gợi ý booking cho đơn (đúng cảng, sát ngày tàu, đúng hãng nếu yêu cầu, còn chỗ).
--  - booking_tong_hop: số lô, cont kế hoạch / thực tế → web cảnh báo thừa / thiếu so với booking.
--  Chạy lại không hỏng (if not exists / create or replace).
-- ============================================================

-- ---------- 1. Bảng booking ----------
create table if not exists public.booking (
  so_booking text primary key check (so_booking <> '' and so_booking = upper(trim(so_booking))),
  hang_tau text references public.hang_tau(ma) on update cascade,
  ten_tau text,
  chuyen text,
  cang_den text references public.cang_den(ma) on update cascade,
  etd date,
  eta date,
  so_luong_cont int check (so_luong_cont is null or so_luong_cont between 0 and 500),
  ghi_chu text,
  nguon text,
  cap_nhat_luc timestamptz not null default now(),
  nguoi_cap_nhat text
);
create index if not exists booking_etd_idx on public.booking (etd);
create index if not exists booking_cang_idx on public.booking (cang_den);

-- ---------- 2. Lô gắn booking + khách; đơn hàng (cont chờ cắt rỗng) có thông tin đặt hàng ----------
alter table public.lo add column if not exists so_booking text references public.booking(so_booking) on update cascade on delete set null;
alter table public.lo add column if not exists khach_hang text references public.khach_hang(ten) on update cascade;
create index if not exists lo_so_booking_idx on public.lo (so_booking);
alter table public.cont add column if not exists ngay_dat_hang date;
alter table public.cont add column if not exists cang_den_yc text references public.cang_den(ma) on update cascade;
alter table public.cont add column if not exists ngay_tau_yc date;
alter table public.cont add column if not exists hang_tau_yc text references public.hang_tau(ma) on update cascade;

-- ---------- 3. Backfill từ dữ liệu hiện có (tắt trigger của lô: không đổi "cập nhật lúc", không ghi nhật ký hàng loạt) ----------
do $bf$
begin
  alter table public.lo disable trigger user;
  -- 3a. tạo booking cho mọi mã booking đang có trên lô: mỗi ô lấy giá trị đầu tiên KHÔNG trống
  --     theo thứ tự ưu tiên lô chưa hủy, cập nhật mới nhất (lô anh em có ô trống không làm mất thông tin)
  insert into public.booking (so_booking, hang_tau, ten_tau, cang_den, etd, eta, nguon)
  select x.bk,
         (array_remove(array_agg(x.hang_tau order by x.uu_tien), null))[1],
         (array_remove(array_agg(x.ten_tau  order by x.uu_tien), null))[1],
         (array_remove(array_agg(x.cang_den order by x.uu_tien), null))[1],
         (array_remove(array_agg(x.etd      order by x.uu_tien), null))[1],
         (array_remove(array_agg(x.eta      order by x.uu_tien), null))[1],
         'từ lô cũ'
    from (select upper(trim(l.booking)) as bk, l.hang_tau, nullif(trim(l.ten_tau), '') as ten_tau, l.cang_den, l.etd, l.eta,
                 row_number() over (partition by upper(trim(l.booking)) order by (not l.da_huy) desc, l.cap_nhat_luc desc) as uu_tien
            from public.lo l
           where nullif(trim(coalesce(l.booking, '')), '') is not null) x
   group by x.bk
  on conflict (so_booking) do nothing;
  -- 3b. gắn khoá cho lô + chuẩn hoá chữ (IN HOA, bỏ khoảng trắng đầu/cuối)
  update public.lo set so_booking = upper(trim(booking)), booking = upper(trim(booking))
   where nullif(trim(coalesce(booking, '')), '') is not null and so_booking is null;
  -- 3c. khách của lô = khách xuất hiện nhiều nhất trong cont (còn hiệu lực) của lô
  update public.lo l
     set khach_hang = (select c.khach_hang from public.cont c
                        where c.lo = l.lo and c.khach_hang is not null and c.trang_thai <> '9'
                        group by c.khach_hang order by count(*) desc, c.khach_hang limit 1)
   where l.khach_hang is null;
  -- 3d. tổng số cont booking = số cont các lô chưa hủy đang dùng (mỗi lô: kế hoạch hoặc số cont thực tế, lấy số lớn hơn)
  --     → điểm xuất phát "đủ", không báo động giả; Điều độ sửa lại theo booking thật khi cần
  update public.booking b
     set so_luong_cont = (select sum(greatest(coalesce(l.so_luong_cont, 0),
                                              (select count(*) from public.cont c where c.lo = l.lo and c.trang_thai <> '9')))::int
                            from public.lo l where l.so_booking = b.so_booking and not l.da_huy)
   where b.so_luong_cont is null
     and exists (select 1 from public.lo l where l.so_booking = b.so_booking and not l.da_huy);
  alter table public.lo enable trigger user;
end $bf$;

-- ---------- 4. Trigger đồng bộ lo.booking (chữ) <-> lo.so_booking (khoá) ----------
create or replace function private.lo_dong_bo_booking() returns trigger
language plpgsql security definer set search_path = ''
as $fn$
declare b public.booking%rowtype; v_moi boolean := false;
begin
  new.booking := nullif(upper(trim(coalesce(new.booking, ''))), '');
  new.so_booking := nullif(upper(trim(coalesce(new.so_booking, ''))), '');
  if tg_op = 'INSERT' then
    if new.so_booking is null then new.so_booking := new.booking; end if;
    v_moi := true;
  elsif new.so_booking is distinct from old.so_booking then
    v_moi := true;                                   -- chọn booking khác (web mới)
  elsif new.booking is distinct from old.booking then
    new.so_booking := new.booking; v_moi := true;    -- sửa ô chữ (web cũ / đổi booking khi rớt tàu) → khoá theo chữ
  end if;
  if new.so_booking is null then
    new.booking := null;
    return new;
  end if;
  new.booking := new.so_booking;
  select * into b from public.booking where so_booking = new.so_booking;
  if not found then
    insert into public.booking (so_booking, hang_tau, ten_tau, cang_den, etd, eta, nguon, nguoi_cap_nhat)
    values (new.so_booking, new.hang_tau, new.ten_tau, new.cang_den, new.etd, new.eta,
            'tự tạo từ lô ' || new.lo, coalesce(auth.jwt() ->> 'email', new.nguoi_cap_nhat))
    on conflict (so_booking) do nothing;
  elsif v_moi then
    -- lô vừa gắn booking: ô trống chép từ booking (sau đó lô sửa riêng, booking đổi không kéo theo)
    new.hang_tau := coalesce(new.hang_tau, b.hang_tau);
    new.ten_tau  := coalesce(new.ten_tau,  b.ten_tau);
    new.cang_den := coalesce(new.cang_den, b.cang_den);
    new.etd      := coalesce(new.etd,      b.etd);
    new.eta      := coalesce(new.eta,      b.eta);
  end if;
  return new;
end;
$fn$;
revoke execute on function private.lo_dong_bo_booking() from public, anon, authenticated;
drop trigger if exists lo_dong_bo_booking on public.lo;
create trigger lo_dong_bo_booking before insert or update of booking, so_booking on public.lo
  for each row execute function private.lo_dong_bo_booking();

-- ---------- 5. View ----------
create or replace view public.lo_tong_hop with (security_invoker = true) as
 select l.lo, l.booking, l.hang_tau, l.ten_tau, l.cang_den, l.etd_kho, l.etd, l.eta,
    l.closing, l.closing_mail, l.cang_ha, l.da_kiem_dich, l.da_khai_eport, l.thanh_ly,
    l.cho_keo_ha_cang, l.ma_don_kdtv, l.so_to_khai, l.cskh, l.ghi_chu, l.cap_nhat_luc,
    l.nguoi_cap_nhat, l.so_luong_cont, l.thu_tu, l.da_huy, l.ly_do_huy, l.huy_boi, l.huy_luc,
    l.closing_eport, l.eport_tau, l.eport_chuyen, l.eport_ghi_chu, l.eport_luc,
    l.dong_trong_ngay, l.cls,
    count(c.id) as so_cont,
    count(c.id) filter (where c.trang_thai = any (array['1', '2', '3', '4', '5'])) as so_cont_dang_chay,
    l.eport_cang,
    l.so_booking, l.khach_hang
   from public.lo l
     left join public.cont c on c.lo = l.lo
  group by l.lo;

create or replace view public.booking_tong_hop with (security_invoker = true) as
 select b.*,
    (select count(*) from public.lo l where l.so_booking = b.so_booking and not l.da_huy)::int as so_lo,
    (select coalesce(sum(l.so_luong_cont), 0) from public.lo l where l.so_booking = b.so_booking and not l.da_huy)::int as cont_ke_hoach,
    (select count(*) from public.cont c join public.lo l on l.lo = c.lo
      where l.so_booking = b.so_booking and not l.da_huy and c.trang_thai <> '9')::int as cont_thuc_te,
    -- đã xếp = mỗi lô lấy số lớn hơn giữa kế hoạch và số cont thực tế → so với so_luong_cont để báo thừa / thiếu
    (select coalesce(sum(greatest(coalesce(l.so_luong_cont, 0),
                                  (select count(*) from public.cont c where c.lo = l.lo and c.trang_thai <> '9'))), 0)
       from public.lo l where l.so_booking = b.so_booking and not l.da_huy)::int as cont_da_xep,
    (select string_agg(l.lo || coalesce(' (' || l.khach_hang || ')', ''), ', ' order by l.lo)
       from public.lo l where l.so_booking = b.so_booking and not l.da_huy) as cac_lo
   from public.booking b;

-- ---------- 6. Gợi ý booking cho đơn ----------
create or replace function public.goi_y_booking(p_cang_den text, p_ngay_tau date, p_hang_tau text default null, p_so_cont int default 1)
returns table (so_booking text, hang_tau text, ten_tau text, chuyen text, cang_den text, etd date, eta date,
               so_luong_cont int, da_xep int, con_lai int, diem int, ly_do text)
language sql stable set search_path = ''
as $fn$
  with t as (
    select b.*,
           coalesce((select sum(greatest(coalesce(l.so_luong_cont, 0),
                                         (select count(*) from public.cont c where c.lo = l.lo and c.trang_thai <> '9')))
                       from public.lo l where l.so_booking = b.so_booking and not l.da_huy), 0)::int as da_xep
      from public.booking b
     where (b.etd is null or b.etd >= (now() at time zone 'Asia/Ho_Chi_Minh')::date)
       and (p_cang_den is null or b.cang_den is null or b.cang_den = p_cang_den)
  )
  select t.so_booking, t.hang_tau, t.ten_tau, t.chuyen, t.cang_den, t.etd, t.eta, t.so_luong_cont, t.da_xep,
         case when t.so_luong_cont is null then null else t.so_luong_cont - t.da_xep end as con_lai,
         (case when p_cang_den is not null and t.cang_den = p_cang_den then 50 else 0 end
          + case when p_ngay_tau is null or t.etd is null then 10
                 when t.etd = p_ngay_tau then 40
                 when abs(t.etd - p_ngay_tau) <= 2 then 30
                 when abs(t.etd - p_ngay_tau) <= 5 then 15 else 0 end
          + case when p_hang_tau is null then 0 when t.hang_tau = p_hang_tau then 20 else -30 end
          + case when t.so_luong_cont is null then 5
                 when t.so_luong_cont - t.da_xep >= coalesce(p_so_cont, 1) then 25 else -40 end)::int as diem,
         concat_ws(' · ',
           case when t.cang_den is null then 'chưa ghi cảng' when p_cang_den is not null and t.cang_den = p_cang_den then 'đúng cảng' end,
           case when t.etd is null then 'chưa có ETD'
                when p_ngay_tau is null then 'ETD ' || to_char(t.etd, 'DD/MM')
                when t.etd = p_ngay_tau then 'đúng ngày tàu'
                else 'ETD ' || to_char(t.etd, 'DD/MM') || ' (lệch ' || (t.etd - p_ngay_tau) || ' ngày)' end,
           case when p_hang_tau is not null and t.hang_tau = p_hang_tau then 'đúng hãng'
                when p_hang_tau is not null then 'khác hãng (' || coalesce(t.hang_tau, '?') || ')' end,
           case when t.so_luong_cont is null then 'chưa ghi số cont'
                when t.so_luong_cont - t.da_xep >= coalesce(p_so_cont, 1) then 'còn ' || (t.so_luong_cont - t.da_xep) || ' chỗ'
                else 'THIẾU CHỖ (còn ' || greatest(t.so_luong_cont - t.da_xep, 0) || ')' end) as ly_do
    from t
   order by diem desc, t.etd nulls last, t.so_booking
   limit 10;
$fn$;
revoke execute on function public.goi_y_booking(text, date, text, int) from public, anon;
grant execute on function public.goi_y_booking(text, date, text, int) to authenticated;

-- ---------- 7. Quyền, nhật ký, realtime (giống bảng lô) ----------
alter table public.booking enable row level security;
drop policy if exists "nhan vien doc" on public.booking;
drop policy if exists "nhan vien them" on public.booking;
drop policy if exists "nhan vien sua" on public.booking;
drop policy if exists "quan ly xoa" on public.booking;
create policy "nhan vien doc" on public.booking for select to authenticated
  using ((select private.vai_tro_hien_tai()) is not null);
create policy "nhan vien them" on public.booking for insert to authenticated
  with check ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ', 'CSKH'));
create policy "nhan vien sua" on public.booking for update to authenticated
  using ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ', 'CSKH'))
  with check ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ', 'CSKH'));
create policy "quan ly xoa" on public.booking for delete to authenticated
  using ((select private.vai_tro_hien_tai()) = 'Quản lý');
drop trigger if exists booking_cap_nhat on public.booking;
create trigger booking_cap_nhat before insert or update on public.booking
  for each row execute function public.dat_nguoi_cap_nhat();
drop trigger if exists nk_booking on public.booking;
create trigger nk_booking after insert or update or delete on public.booking
  for each row execute function private.ghi_nhat_ky('so_booking');
do $pub$ begin
  alter publication supabase_realtime add table public.booking;
exception when duplicate_object then null; end $pub$;
