-- ============================================================
-- YÊU CẦU anh Hi 28/09:
--  (#3) CLS mail nằm ở BOOKING (đọc từ file booking) → chép sang lô khi lô gắn booking.
--       Bỏ CLS nhập tay ở lô (frontend đã bỏ ô); CLS máy dùng (cột generated cls) = closing_mail → closing_eport → closing.
--  (#5) CLS ePort cập nhật THỦ CÔNG (nút trên web), KHÔNG chạy cron mỗi giờ nữa → gỡ 4 cron ePort.
--  (#6) Mã KDTV thủ công: gỡ trigger chạy mỗi giờ trong Apps Script (DongBo.gs) — KHÔNG thuộc DB, làm ở file .gs.
-- Chạy lại nhiều lần vẫn OK.
-- ============================================================

-- (#3) Booking mang CLS mail
alter table public.booking add column if not exists closing_mail timestamptz;

-- Trigger booking↔lô: khi lô gắn booking, chép thêm closing_mail (ô trống mới chép); tạo booking từ lô cũng mang closing_mail
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
    v_moi := true;
  elsif new.booking is distinct from old.booking then
    new.so_booking := new.booking; v_moi := true;
  end if;
  if new.so_booking is null then
    new.booking := null;
    return new;
  end if;
  new.booking := new.so_booking;
  select * into b from public.booking where so_booking = new.so_booking;
  if not found then
    insert into public.booking (so_booking, hang_tau, ten_tau, cang_den, etd, eta, closing_mail, nguon, nguoi_cap_nhat)
    values (new.so_booking, new.hang_tau, new.ten_tau, new.cang_den, new.etd, new.eta, new.closing_mail,
            'tự tạo từ lô ' || new.lo, coalesce(auth.jwt() ->> 'email', new.nguoi_cap_nhat))
    on conflict (so_booking) do nothing;
  elsif v_moi then
    new.hang_tau     := coalesce(new.hang_tau, b.hang_tau);
    new.ten_tau      := coalesce(new.ten_tau,  b.ten_tau);
    new.cang_den     := coalesce(new.cang_den, b.cang_den);
    new.etd          := coalesce(new.etd,      b.etd);
    new.eta          := coalesce(new.eta,      b.eta);
    new.closing_mail := coalesce(new.closing_mail, b.closing_mail);   -- CLS mail lấy từ booking
  end if;
  return new;
end;
$fn$;
revoke execute on function private.lo_dong_bo_booking() from public, anon, authenticated;
drop trigger if exists lo_dong_bo_booking on public.lo;
create trigger lo_dong_bo_booking before insert or update of booking, so_booking on public.lo
  for each row execute function private.lo_dong_bo_booking();

-- Khi SỬA booking.closing_mail: cập nhật cho các lô của booking mà lô chưa tự nhập CLS mail riêng
create or replace function private.booking_day_cls_mail() returns trigger
language plpgsql security definer set search_path = ''
as $fn$
begin
  if new.closing_mail is distinct from old.closing_mail and new.closing_mail is not null then
    update public.lo set closing_mail = new.closing_mail
     where so_booking = new.so_booking and not da_huy
       and (closing_mail is null or closing_mail = old.closing_mail);
  end if;
  return new;
end;
$fn$;
revoke execute on function private.booking_day_cls_mail() from public, anon, authenticated;
drop trigger if exists booking_day_cls_mail on public.booking;
create trigger booking_day_cls_mail after update of closing_mail on public.booking
  for each row execute function private.booking_day_cls_mail();

-- (#5) Gỡ 4 cron ePort (giữ nút thủ công trên web + cron gợi ý kế hoạch)
do $$
declare j text;
begin
  foreach j in array array['cls-eport-gui','cls-eport-xu-ly','eport-spitc-goi','eport-spitc-xu-ly'] loop
    begin
      perform cron.unschedule(jobid) from cron.job where jobname = j;
    exception when others then null;
    end;
  end loop;
end $$;
