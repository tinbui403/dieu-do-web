-- ============================================================
-- QUY TRÌNH KIỂM DỊCH → KÉO → HẠ CẢNG (chặn sai ngay trong cơ sở dữ liệu)
-- Anh Tín chốt 20/09/2026 22:00:
--  1. Mỗi lô chỉ 1 cont kiểm dịch (KD). Đánh dấu cont thứ 2 → báo lỗi, phải bỏ cont cũ trước.
--  2. Tích "Lô đã kiểm dịch" chỉ khi: cont KD đang "Ở bãi tạm" tại HLS / PD / HT (không DCL,
--     không kiểm ở kho) + lô có Mã KDTV + người tích là Điều độ / Quản lý.
--  3. Bỏ tích: Điều độ / Quản lý, chỉ khi lô chưa có cont ở cảng / lên tàu.
--  4. Lô chưa kiểm dịch (kể cả lô chưa chọn cont KD) → KHÔNG cont nào được "Đã hạ cảng" / "Đã lên tàu".
--  5. Lô đã KD: cont từ kho (chờ cắt rỗng / đang đóng / đầy chờ kéo) chỉ hạ thẳng cảng khi còn
--     ≤ 48 giờ tới CLS (cấu hình "Giờ trước closing hạ thẳng cảng"); còn lại phải hạ bãi.
--  6. Cont KD bị Hủy (9) hoặc bỏ dấu / đổi sang cont khác / đổi lô / bị xoá → lô tự về CHƯA kiểm dịch.
--  7. "Cho kéo hạ cảng" = "Lô đã kiểm dịch" (tự động, không tích tay).
--  8. Chuyển cont về "Ở bãi tạm" bắt buộc có bãi. Lùi trạng thái cont: chỉ Quản lý / Điều độ.
--  9. Chế độ thử: Quản lý xoá được lô / cont đã chạy khi cấu hình "Chế độ thử: cho xoá dữ liệu đã chạy" = Bật.
-- Kiểm thử: tests/kiem_thu_kd.sql (43 tình huống, chạy rồi tự huỷ).
-- Bỏ qua kiểm tra (chỉ dùng trong migration dọn dữ liệu): set_config('dieu_do.bo_qua_kiem_tra', 'on', true)
-- ============================================================

-- 0. Cấu hình
update public.cau_hinh
   set gia_tri = '48',
       giai_thich = 'Lô ĐÃ kiểm dịch: cont đầy ở kho chỉ hạ thẳng cảng khi còn ≤ bấy nhiêu giờ tới CLS; còn lại phải hạ bãi. Lô chưa kiểm dịch không bao giờ được hạ cảng.'
 where tham_so = 'Giờ trước closing hạ thẳng cảng';
insert into public.cau_hinh (tham_so, gia_tri, giai_thich)
select 'Chế độ thử: cho xoá dữ liệu đã chạy', 'Bật',
       'Bật = Quản lý xoá hẳn được lô / cont đã chạy thực tế (tới kho, bãi, cảng, lên tàu) để làm lại dữ liệu thử. Khi chạy chính thức đổi thành Tắt.'
where not exists (select 1 from public.cau_hinh where tham_so = 'Chế độ thử: cho xoá dữ liệu đã chạy');

create or replace function private.cfg_so(p_ten text, p_mac_dinh numeric)
 returns numeric language sql stable security definer set search_path to ''
as $$
  select coalesce((select case when trim(gia_tri) ~ '^-?[0-9]+(\.[0-9]+)?$' then trim(gia_tri)::numeric end
                   from public.cau_hinh where tham_so = p_ten), p_mac_dinh)
$$;

create or replace function private.ten_trang_thai(p text)
 returns text language sql stable security definer set search_path to ''
as $$ select coalesce((select t.ten_vi from public.trang_thai t where t.ma = p), p) $$;

-- 1. Kiểm tra cont (trước khi ghi)
create or replace function private.kiem_tra_cont()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare
  v_user boolean := auth.uid() is not null;
  v_role text := coalesce(private.vai_tro_hien_tai(), '');
  v_old text;
  v_ten text := coalesce(new.so_cont, new.ma_don, new.id, 'mới');
  v_kd text; v_lo_kd boolean; v_cls timestamptz; v_h numeric; v_gio numeric;
begin
  if current_setting('dieu_do.bo_qua_kiem_tra', true) = 'on' then return new; end if;
  if tg_op = 'UPDATE' then v_old := old.trang_thai; end if;

  -- Cont hủy / đổi cont: không còn là cont kiểm dịch
  if new.trang_thai = '9' and coalesce(new.cont_kiem_dich, false) then
    new.cont_kiem_dich := false;
  end if;

  -- Về bãi tạm phải có bãi
  if new.trang_thai = '4' and nullif(trim(coalesce(new.bai_tam, '')), '') is null then
    raise exception 'Cont % chuyển về "Ở bãi tạm" thì phải chọn bãi (HLS / PD / HT / DCL).', v_ten;
  end if;

  -- Lùi trạng thái: chỉ Quản lý / Điều độ
  if tg_op = 'UPDATE' and v_old is distinct from new.trang_thai and v_user
     and v_role not in ('Quản lý', 'Điều độ')
     and (v_old = '9' or (new.trang_thai <> '9' and new.trang_thai < v_old)) then
    raise exception 'Chỉ Quản lý hoặc Điều độ được lùi trạng thái cont (% : "%" → "%").',
      v_ten, private.ten_trang_thai(v_old), private.ten_trang_thai(new.trang_thai);
  end if;

  -- Mỗi lô chỉ 1 cont kiểm dịch
  if coalesce(new.cont_kiem_dich, false) and new.lo is not null
     and (tg_op = 'INSERT' or not coalesce(old.cont_kiem_dich, false) or old.lo is distinct from new.lo) then
    select string_agg(coalesce(c.so_cont, c.ma_don, c.id), ', ') into v_kd
      from public.cont c
     where c.lo = new.lo and c.id is distinct from new.id and c.cont_kiem_dich and c.trang_thai <> '9';
    if v_kd is not null then
      raise exception 'Lô % đã có cont kiểm dịch %. Mỗi lô chỉ 1 cont kiểm dịch — bỏ dấu cont đó trước.', new.lo, v_kd;
    end if;
  end if;

  -- Hạ cảng / lên tàu: lô phải đã kiểm dịch, không ngoại lệ
  if new.trang_thai in ('5', '6')
     and (tg_op = 'INSERT' or v_old is distinct from new.trang_thai or old.lo is distinct from new.lo) then
    select coalesce(l.da_kiem_dich, false), l.cls into v_lo_kd, v_cls from public.lo l where l.lo = new.lo;
    if not found then
      raise exception 'Cont % chưa thuộc lô nào nên không chuyển sang "%" được.', v_ten, private.ten_trang_thai(new.trang_thai);
    end if;
    if not v_lo_kd then
      raise exception 'Lô % chưa kiểm dịch → không cont nào của lô được "%". Cont kiểm dịch của lô phải về bãi HLS / PD / HT và được tích "Lô đã kiểm dịch" trước.',
        new.lo, private.ten_trang_thai(new.trang_thai);
    end if;
    -- Từ kho đi thẳng cảng: chỉ khi CLS còn ≤ 48 giờ
    if new.trang_thai = '5' and v_old in ('1', '2', '3') then
      v_gio := private.cfg_so('Giờ trước closing hạ thẳng cảng', 48);
      v_h := extract(epoch from (v_cls - now())) / 3600;
      if v_h is null or v_h > v_gio then
        raise exception 'Lô % còn % tới CLS (hạ thẳng cảng chỉ khi ≤ % giờ) → cont % phải hạ bãi trước.',
          new.lo, coalesce(round(v_h) || ' giờ', '— (chưa có CLS)'), v_gio, v_ten;
      end if;
    end if;
  end if;
  return new;
end;
$function$;

-- 2. Sau khi ghi cont: cont kiểm dịch thay đổi → lô về chưa kiểm dịch
create or replace function private.cont_sau_kd()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare v_los text[] := '{}';
begin
  if current_setting('dieu_do.bo_qua_kiem_tra', true) = 'on' then return null; end if;
  if tg_op = 'DELETE' then
    if coalesce(old.cont_kiem_dich, false) then v_los := v_los || old.lo; end if;
  elsif tg_op = 'INSERT' then
    if coalesce(new.cont_kiem_dich, false) then v_los := v_los || new.lo; end if;
  else
    if coalesce(old.cont_kiem_dich, false)
       and (not coalesce(new.cont_kiem_dich, false) or old.lo is distinct from new.lo) then
      v_los := v_los || old.lo;
    end if;
    if coalesce(new.cont_kiem_dich, false)
       and (not coalesce(old.cont_kiem_dich, false) or old.lo is distinct from new.lo) then
      v_los := v_los || new.lo;
    end if;
  end if;
  v_los := array_remove(v_los, null);
  if coalesce(array_length(v_los, 1), 0) > 0 then
    perform set_config('dieu_do.tu_bo_kd', 'on', true);
    update public.lo set da_kiem_dich = false where lo = any (v_los) and da_kiem_dich;
    perform set_config('dieu_do.tu_bo_kd', 'off', true);
  end if;
  return null;
end;
$function$;

-- 3. Kiểm tra lô (trước khi ghi)
create or replace function private.kiem_tra_lo()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare
  v_user boolean := auth.uid() is not null;
  v_role text := coalesce(private.vai_tro_hien_tai(), '');
  c record; v_n int;
begin
  new.cho_keo_ha_cang := coalesce(new.da_kiem_dich, false);
  if current_setting('dieu_do.bo_qua_kiem_tra', true) = 'on' then return new; end if;

  if tg_op = 'INSERT' then
    if coalesce(new.da_kiem_dich, false) then
      raise exception 'Lô mới chưa có cont kiểm dịch nên chưa tích "Lô đã kiểm dịch" được.';
    end if;
    return new;
  end if;

  if coalesce(new.da_kiem_dich, false) and not coalesce(old.da_kiem_dich, false) then
    if v_user and v_role not in ('Quản lý', 'Điều độ') then
      raise exception 'Chỉ Điều độ hoặc Quản lý được tích "Lô đã kiểm dịch".';
    end if;
    select * into c from public.cont
     where lo = new.lo and cont_kiem_dich and trang_thai <> '9' order by id limit 1;
    if not found then
      raise exception 'Lô % chưa chọn cont kiểm dịch — mở cont cần kiểm và đánh dấu "Cont kiểm dịch" trước.', new.lo;
    end if;
    if c.trang_thai <> '4' then
      raise exception 'Cont kiểm dịch % của lô % đang ở "%" — phải về bãi HLS / PD / HT rồi mới tích kiểm dịch được.',
        coalesce(c.so_cont, c.ma_don, c.id), new.lo, private.ten_trang_thai(c.trang_thai);
    end if;
    if coalesce(c.bai_tam, '') not in ('HLS', 'PD', 'HT') then
      raise exception 'Cont kiểm dịch % đang ở bãi % — chỉ kiểm dịch ở bãi HLS, PD, HT.',
        coalesce(c.so_cont, c.ma_don, c.id), coalesce(c.bai_tam, '(chưa chọn)');
    end if;
    if nullif(trim(coalesce(new.ma_don_kdtv, '')), '') is null then
      raise exception 'Lô % chưa có Mã KDTV (tự đồng bộ từ PQS NEW mỗi giờ, hoặc nhập tay) nên chưa tích kiểm dịch được.', new.lo;
    end if;
  elsif coalesce(old.da_kiem_dich, false) and not coalesce(new.da_kiem_dich, false) then
    if current_setting('dieu_do.tu_bo_kd', true) = 'on' then return new; end if;
    if v_user and v_role not in ('Quản lý', 'Điều độ') then
      raise exception 'Chỉ Điều độ hoặc Quản lý được bỏ tích "Lô đã kiểm dịch".';
    end if;
    select count(*) into v_n from public.cont where lo = new.lo and trang_thai in ('5', '6');
    if v_n > 0 then
      raise exception 'Lô % đã có % cont ở cảng / lên tàu nên không bỏ tích kiểm dịch được.', new.lo, v_n;
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists cont_kiem_tra_kd on public.cont;
create trigger cont_kiem_tra_kd before insert or update on public.cont
  for each row execute function private.kiem_tra_cont();
drop trigger if exists cont_sau_kd on public.cont;
create trigger cont_sau_kd after insert or update or delete on public.cont
  for each row execute function private.cont_sau_kd();
drop trigger if exists lo_kiem_tra_kd on public.lo;
create trigger lo_kiem_tra_kd before insert or update on public.lo
  for each row execute function private.kiem_tra_lo();

-- 4. Xoá hẳn: chế độ thử cho Quản lý xoá cả dữ liệu đã chạy
create or replace function private.che_do_thu()
 returns boolean language sql stable security definer set search_path to ''
as $$ select coalesce((select lower(trim(gia_tri)) in ('bật', 'bat', 'on', '1', 'có')
                       from public.cau_hinh where tham_so = 'Chế độ thử: cho xoá dữ liệu đã chạy'), false) $$;

create or replace function public.xoa_cont(p_id text)
 returns void language plpgsql set search_path to ''
as $function$
declare v_tt text;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được xoá cont';
  end if;
  select trang_thai into v_tt from public.cont where id = p_id;
  if not found then raise exception 'Không tìm thấy cont %', p_id; end if;
  if v_tt not in ('1', '9') and not private.che_do_thu() then
    raise exception 'Cont đã chạy thực tế nên không xoá được. Nếu bỏ, hãy chuyển sang trạng thái "Hủy đổi cont". (Muốn xoá dữ liệu thử: bật "Chế độ thử: cho xoá dữ liệu đã chạy" trong Cấu hình.)';
  end if;
  delete from public.chi_phi_cont where cont_id = p_id;
  delete from public.goi_y where id_cont_rong = p_id or id_cont_day = p_id;
  delete from public.cont where id = p_id;
end;
$function$;

create or replace function public.xoa_lo(p_lo text)
 returns integer language plpgsql set search_path to ''
as $function$
declare v_chay int; v_n int;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được xoá lô';
  end if;
  if not exists (select 1 from public.lo where lo = p_lo) then
    raise exception 'Không tìm thấy lô %', p_lo;
  end if;
  select count(*) into v_chay from public.cont where lo = p_lo and trang_thai not in ('1', '9');
  if v_chay > 0 and not private.che_do_thu() then
    raise exception 'Lô % có % cont đã chạy thực tế (đã tới kho / bãi / cảng / lên tàu) nên không xoá được, để giữ lịch sử và tiền cước. (Muốn xoá dữ liệu thử: bật "Chế độ thử: cho xoá dữ liệu đã chạy" trong Cấu hình.)', p_lo, v_chay;
  end if;
  delete from public.chi_phi_cont where cont_id in (select c.id from public.cont c where c.lo = p_lo);
  delete from public.goi_y g
   where g.id_cont_rong in (select c.id from public.cont c where c.lo = p_lo)
      or g.id_cont_day in (select c.id from public.cont c where c.lo = p_lo);
  delete from public.cont where lo = p_lo;
  get diagnostics v_n = row_count;
  delete from public.lo where lo = p_lo;
  return v_n;
end;
$function$;

-- 5. Dọn dữ liệu cũ theo quy tắc mới (bỏ qua kiểm tra trong migration này)
select set_config('dieu_do.bo_qua_kiem_tra', 'on', true);
-- 5a. Lô đang chạy ghi "đã kiểm dịch" mà cont KD chưa từng về bãi HLS/PD/HT → bỏ tích (ghi nhật ký)
update public.lo l set da_kiem_dich = false, cho_keo_ha_cang = false
 where l.da_kiem_dich
   and exists (select 1 from public.cont c where c.lo = l.lo and c.trang_thai in ('1', '2', '3', '4', '5'))
   and not exists (select 1 from public.cont c where c.lo = l.lo and c.cont_kiem_dich
                     and c.trang_thai in ('4', '5', '6') and c.bai_tam in ('HLS', 'PD', 'HT'));
-- 5b. "Cho kéo hạ cảng" = "Lô đã kiểm dịch" cho mọi lô (trường tự động, không ghi nhật ký)
select set_config('dieu_do.bo_qua_nhat_ky', 'on', true);
update public.lo set cho_keo_ha_cang = coalesce(da_kiem_dich, false)
 where cho_keo_ha_cang is distinct from coalesce(da_kiem_dich, false);
select set_config('dieu_do.bo_qua_nhat_ky', 'off', true);
select set_config('dieu_do.bo_qua_kiem_tra', 'off', true);

-- 6. Gợi ý kế hoạch: Quá CLS gấp nhất; đổi rỗng ghép cùng kho trước; nơi hạ theo kiểm dịch

create or replace function public.tao_goi_y()
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_bai text; v_gio_ha numeric; v_khung numeric; v_gio_dong numeric; v_giu int; v_quen int;
  v_kd numeric; v_thuong numeric; v_gan numeric; v_bai_kd text;
  v_prefix text := 'GY' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYYMMDDHH24MI') || '-';
  v_id text; v_n int; e record;
  used_f text[] := '{}'; used_e text[] := '{}';
begin
  if auth.uid() is not null and coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ') then
    raise exception 'Bạn không có quyền chạy gợi ý kế hoạch';
  end if;

  select
    coalesce(max(gia_tri) filter (where tham_so = 'Bãi tạm mặc định'), 'HLS'),
    coalesce(max(gia_tri) filter (where tham_so = 'Giờ trước closing hạ thẳng cảng'), '36')::numeric,
    coalesce(max(gia_tri) filter (where tham_so = 'Khung kế hoạch (giờ tới)'), '36')::numeric,
    coalesce(max(gia_tri) filter (where tham_so = 'Giờ đóng hàng ước tính'), '24')::numeric,
    coalesce(max(gia_tri) filter (where tham_so = 'Số ngày giữ gợi ý đã duyệt'), '3')::int,
    coalesce(max(gia_tri) filter (where tham_so = 'Số ngày tính nhà xe quen'), '45')::int,
    coalesce(max(gia_tri) filter (where tham_so = 'Số giờ cont KD cần về bãi trước CLS'), '72')::numeric,
    coalesce(max(gia_tri) filter (where tham_so = 'Số giờ cont thường cần kéo trước CLS'), '48')::numeric,
    coalesce(max(gia_tri) filter (where tham_so = 'Số ngày CLS gần'), '5')::numeric
  into v_bai, v_gio_ha, v_khung, v_gio_dong, v_giu, v_quen, v_kd, v_thuong, v_gan
  from public.cau_hinh;
  -- cont kiểm dịch chỉ được kiểm ở HLS / PD / HT
  v_bai_kd := case when v_bai in ('HLS', 'PD', 'HT') then v_bai else 'HLS' end;

  delete from public.goi_y where not duyet;

  -- Cont đầy (hoặc chắc chắn đầy trước khi cần kéo), kèm nhà xe đang giữ mooc
  create temp table _day on commit drop as
  select z.*,
    case when z.h_cls < 0 then 0
         when z.kd_can and z.h_cls <= v_kd then 1
         when z.h_cls <= v_thuong then 2
         when z.h_cls <= v_gan * 24 then 3
         else 4 end as muc
  from (
    select c.id, c.so_cont, c.so_seal, c.lo, c.kho, c.nha_xe, c.ngay_den_kho, c.cont_kiem_dich, c.du_kien_day, c.trang_thai, k.khu_vuc,
      k.nguoi_lien_he as kho_lh, k.sdt as kho_sdt, k.google_map as kho_map,
      coalesce(l.cls, ((coalesce(l.etd, l.etd_kho) - 1)::timestamp at time zone 'Asia/Ho_Chi_Minh')) as closing,
      (l.cls is null and coalesce(l.etd, l.etd_kho) is not null) as closing_uoc,
      coalesce(l.da_kiem_dich, false) as lo_kd,
      (c.cont_kiem_dich and not coalesce(l.da_kiem_dich, false)) as kd_can,
      coalesce(extract(epoch from (coalesce(l.cls, ((coalesce(l.etd, l.etd_kho) - 1)::timestamp at time zone 'Asia/Ho_Chi_Minh')) - v_now)) / 3600, 99999) as h_cls
    from public.cont c
    left join public.lo l on l.lo = c.lo
    left join public.kho k on k.ten = c.kho
    where c.trang_thai in ('2', '3') and c.so_cont is not null and not coalesce(l.da_huy, false)
      and not exists (select 1 from public.goi_y g where g.duyet and g.id_cont_day = c.id and g.ngay_kh >= v_today - v_giu)
  ) z
  where z.trang_thai = '3'
     or (z.du_kien_day is not null and z.du_kien_day <= v_now + make_interval(hours => v_khung::int))
     or (z.du_kien_day is null and z.h_cls <= v_gan * 24);

  -- Đơn cần cont rỗng trong khung giờ
  create temp table _rong on commit drop as
  select c.id, c.ma_don, c.lo, c.kho, c.nha_xe, k.khu_vuc, l.booking, l.hang_tau, c.ngay_can_len_kho as can,
    coalesce(l.dong_trong_ngay, false) as dong_ngay,
    k.nguoi_lien_he as kho_lh, k.sdt as kho_sdt, k.google_map as kho_map,
    coalesce(l.cls, ((coalesce(l.etd, l.etd_kho) - 1)::timestamp at time zone 'Asia/Ho_Chi_Minh')) as closing,
    coalesce(l.da_kiem_dich, false) as lo_kd
  from public.cont c
  left join public.lo l on l.lo = c.lo
  left join public.kho k on k.ten = c.kho
  where c.trang_thai = '1' and not coalesce(l.da_huy, false)
    and (c.ngay_can_len_kho is null or c.ngay_can_len_kho <= v_now + make_interval(hours => v_khung::int))
    and not exists (select 1 from public.goi_y g where g.duyet and g.id_cont_rong = c.id and g.ngay_kh >= v_today - v_giu);

  create temp table _cap (stt serial, loai text, id_rong text, id_day text) on commit drop;

  -- 1. Đóng trong ngày: lô đánh dấu đóng trong ngày → xe chờ đóng xong kéo về luôn
  insert into _cap (loai, id_rong, id_day)
  select 'dong', r.id, null from _rong r where r.dong_ngay order by r.can nulls first, r.id;
  select coalesce(array_agg(id), '{}') into used_e from _rong where dong_ngay;

  -- 2. Đổi rỗng kéo đầy: đưa rỗng tới kho, kéo 1 cont đầy cùng kho hoặc cùng khu vực, CÙNG NHÀ XE giữ mooc.
  --    Ưu tiên: cont KD gấp → cont sát CLS → CLS trong N ngày → CLS xa; cùng kho trước; CLS gần trước.
  for e in select id, kho, khu_vuc, nha_xe from _rong where not (id = any(used_e)) order by can nulls first, id loop
    v_id := null;
    select d.id into v_id from _day d
     where (d.kho = e.kho or (e.khu_vuc is not null and d.khu_vuc = e.khu_vuc))
       and d.nha_xe is not null and (e.nha_xe is null or d.nha_xe = e.nha_xe)
       and not (d.id = any(used_f))
     order by (d.kho = e.kho) desc, d.muc, d.closing nulls last, d.id
     limit 1;
    if v_id is not null then
      insert into _cap (loai, id_rong, id_day) values ('doi', e.id, v_id);
      used_f := used_f || v_id; used_e := used_e || e.id;
    end if;
  end loop;

  -- 3. Cắt mooc: đơn còn lại (không có cont đầy để ghép) → đưa rỗng tới kho, để mooc, đầu kéo chạy không về
  insert into _cap (loai, id_rong, id_day)
  select 'cat', r.id, null from _rong r where not (r.id = any(used_e)) order by r.can nulls first, r.id;

  -- 4. Rút mooc: cont đầy GẤP còn lại (KD gấp hoặc sát CLS) → đầu kéo chạy không lên kéo về
  insert into _cap (loai, id_rong, id_day)
  select 'rut', null, d.id from _day d where not (d.id = any(used_f)) and d.muc <= 2 order by d.muc, d.closing nulls last, d.id;

  insert into public.goi_y (id, ngay_kh, uu_tien, loai_lenh, booking_lay_rong, hang_tau, kho_cat_rong, id_cont_rong, ma_don_rong,
    cont_day, id_cont_day, kho_day, du_kien_day, noi_ha, closing, con_lai_gio, nha_xe_goi_y, ly_do, noi_dung_lenh,
    chi_phi_uoc_tinh, chi_phi_ghi_chu, muc_uu_tien)
  select v_prefix || lpad((row_number() over (order by x.uu_tien, x.closing nulls last, x.stt))::text, 2, '0'),
    v_today, x.uu_tien, x.loai_lenh, x.booking, x.hang_tau, x.kho_rong, x.id_rong, x.ma_don_rong,
    x.so_cont, x.id_day, x.kho_day, x.du_kien, x.noi_ha, x.closing, round(x.h_cl), x.nha_xe,
    nullif(concat_ws('; ',
      case x.muc when 0 then '⚠ ĐÃ QUÁ CLS ' || round(-x.h_cl) || 'h — kéo gấp, kiểm tra đổi tàu / CLS mới'
                 when 1 then 'Cont kiểm dịch GẤP: còn ' || round(x.h_cl) || 'h tới CLS, cần về bãi kiểm dịch'
                 when 2 then 'Sát CLS: còn ' || round(x.h_cl) || 'h'
                 when 3 then 'CLS trong ' || v_gan || ' ngày' end,
      case when x.id_day is not null and x.nx_day is not null then 'Mooc của ' || x.nx_day || coalesce(' (kéo lên ' || to_char(x.den_day, 'DD/MM') || ')', '') || ' → chỉ ' || x.nx_day || ' kéo được' end,
      case when x.id_day is not null and x.nx_day is null then '⚠ Chưa rõ cont nằm trên mooc nhà xe nào — hỏi kho trước khi điều xe' end,
      case when x.loai = 'doi' and x.kho_day is distinct from x.kho_rong then 'Kéo đầy ở kho khác cùng khu vực ' || coalesce(x.khu_vuc_rong, '') end,
      case when x.loai = 'cat' then 'Không có cont đầy cùng kho / khu vực để ghép → cắt mooc' end,
      case when x.loai = 'dong' then 'Lô đóng trong ngày: xe chờ đóng xong kéo về' end,
      case when x.id_rong is not null and x.can is not null then 'Kho cần rỗng ' || to_char(x.can at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') end,
      case when x.id_day is not null and x.trang_thai_day = '2' and x.du_kien_day is null then 'Cont đang đóng, chưa nhập Dự kiến đầy — CLS gần nên máy coi như đã đầy' end,
      case when x.closing_uoc then 'CLS ước tính = ETD - 1 ngày' end,
      case when x.kd_chua then 'Cont kiểm dịch → về bãi ' || v_bai_kd || ' chờ kiểm (chỉ kiểm ở HLS / PD / HT)'
           when x.id_day is not null and not x.lo_kd_day then 'Lô chưa kiểm dịch → chỉ về bãi, chưa được hạ cảng'
           when x.id_day is not null and x.h_cl <= v_gio_ha then 'Lô đã kiểm dịch, còn ' || round(x.h_cl) || 'h tới CLS (≤ ' || v_gio_ha || 'h) → hạ thẳng cảng'
           when x.id_day is not null then 'Lô đã kiểm dịch, CLS còn > ' || v_gio_ha || 'h → hạ bãi'
           when x.loai = 'dong' and not x.lo_kd_rong then 'Lô chưa kiểm dịch → đóng xong về bãi, chưa được hạ cảng' end,
      case when x.h_cl < 0 and x.muc is distinct from 0 then '⚠ ĐÃ QUÁ CLOSING' end,
      case when x.id_rong is not null and x.booking is null then '⚠ Đơn chưa có booking' end,
      case when x.gia is null and x.nha_xe is not null then 'Chưa có giá cước ' || x.nha_xe || ' cho lệnh này' end
    ), ''),
    concat_ws(E'\n',
      case x.loai when 'dong' then 'LỆNH ĐÓNG TRONG NGÀY 当天装柜' when 'doi' then 'LỆNH ĐỔI RỖNG KÉO ĐẦY 换空拉满'
                  when 'cat' then 'LỆNH CẮT MOOC 甩挂' else 'LỆNH RÚT MOOC 拉满柜' end,
      case when x.id_rong is not null then 'Số Booking 订舱号: ' || coalesce(x.booking, '⚠ chưa có 无') end,
      case when x.id_rong is not null then 'Lấy rỗng lên kho 送空到: ' || coalesce(x.kho_rong, '—') || coalesce(' (đơn ' || x.ma_don_rong || ')', '') end,
      case x.loai when 'cat' then 'Để mooc tại kho, đầu kéo chạy không về 甩挂后空车返回'
                  when 'dong' then 'Xe chờ đóng xong kéo về 等装完拉回'
                  when 'rut' then 'Đầu kéo chạy không lên kéo cont đầy 空车上去拉满柜' end,
      case when x.id_day is not null then 'Cont đầy 满柜: ' || x.so_cont || coalesce(' · Seal ' || x.so_seal, '') || coalesce(' (lô ' || x.lo_day || ')', '') end,
      case when x.id_day is not null then 'Kho đầy 装货点: ' || coalesce(x.kho_day, '—') end,
      case when x.id_day is not null then 'Mooc 车架: ' || coalesce(x.nx_day, '⚠ chưa rõ 未知') || coalesce(' (kéo lên 上柜 ' || to_char(x.den_day, 'DD/MM') || ')', '') end,
      case when x.kd_chua then 'Cont kiểm dịch 检疫柜: hạ bãi chờ kiểm 堆场待检' end,
      case when coalesce(x.lh_day, x.lh_rong) is not null or coalesce(x.sdt_day, x.sdt_rong) is not null
           then 'Liên hệ kho 仓库联系: ' || concat_ws(' ', coalesce(x.lh_day, x.lh_rong), coalesce(x.sdt_day, x.sdt_rong)) end,
      case when coalesce(x.map_day, x.map_rong) is not null then 'Định vị 定位: ' || coalesce(x.map_day, x.map_rong) end,
      case when x.noi_ha is not null then 'Nơi hạ 还柜点: ' || x.noi_ha end,
      'CUT-OFF 截关: ' || coalesce(to_char(x.closing at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM/YYYY'), '—'),
      'Nhà xe 车队: ' || coalesce(x.nha_xe, '—'),
      case when x.gia is not null then 'Chi phí ước tính 预估费用: ' || to_char(x.gia, 'FM999G999G999') || 'đ' end),
    x.gia,
    case when x.nx_co_dinh then
           case when x.gia is not null then x.nha_xe || ' (chủ mooc): ' || to_char(x.gia, 'FM999G999G999') || 'đ' else x.nha_xe || ' (chủ mooc): chưa có giá' end
         else (select string_agg(q.nha_xe || ' ' || to_char(q.gia, 'FM999G999G999') || 'đ', ' · ')
               from (select * from private.nha_xe_re_nhat(x.loai_gia, x.khu_vuc_rong) limit 3) q) end,
    case x.muc when 0 then 'Quá CLS' when 1 then 'KD gấp' when 2 then 'Sát CLS' when 3 then 'CLS gần' when 4 then 'CLS xa' end
  from (
    select y.*,
      case when y.id_day is not null and y.muc <= 2 then 1
           when y.id_day is not null and y.muc = 3 then 2
           when y.id_day is not null then 3
           when y.h_ref is null or y.h_ref < 24 then 1
           when y.h_ref < 48 then 2 else 3 end as uu_tien,
      coalesce(private.gia_cuoc(y.nha_xe, y.loai_gia, coalesce(y.khu_vuc_rong, y.khu_vuc_day)), null) as gia
    from (
      select w.*,
        case when w.id_day is null then
               case when w.loai = 'dong' then
                      case when w.lo_kd_rong and w.h_cl <= v_gio_ha then 'Seal chính hạ cảng 正封还码头' else 'Seal tạm ' || v_bai || ' 临时封条' end
                    else null end
             when w.kd_chua then 'Seal tạm ' || v_bai_kd || ' 临时封条'
             when w.lo_kd_day and w.h_cl <= v_gio_ha then 'Seal chính hạ cảng 正封还码头'
             else 'Seal tạm ' || v_bai || ' 临时封条' end as noi_ha,
        (w.id_day is not null and w.nx_day is not null) as nx_co_dinh,
        case when w.id_day is not null and w.nx_day is not null then w.nx_day
             else coalesce(w.nx_rong,
                    (select q.nha_xe from private.nha_xe_re_nhat(w.loai_gia, coalesce(w.khu_vuc_rong, w.khu_vuc_day)) q limit 1),
                    (select c2.nha_xe from public.cont c2 join public.nha_xe n2 on n2.ma = c2.nha_xe and n2.hoat_dong
                      where c2.kho = coalesce(w.kho_day, w.kho_rong) and c2.ngay_goi_cont >= v_today - v_quen
                      group by c2.nha_xe order by count(*) desc, c2.nha_xe limit 1)) end as nha_xe
      from (
        select cap.stt, cap.loai, cap.id_rong, cap.id_day,
          case cap.loai when 'dong' then 'Đóng trong ngày 当天装柜' when 'doi' then 'Đổi rỗng kéo đầy 换空拉满'
                        when 'cat' then 'Cắt mooc 甩挂' else 'Rút mooc 拉满柜' end as loai_lenh,
          case cap.loai when 'dong' then 'dong_trong_ngay' when 'doi' then 'doi_rong' when 'cat' then 'cat_mooc' else 'rut_mooc' end as loai_gia,
          r.booking, r.hang_tau, r.kho as kho_rong, r.ma_don as ma_don_rong, r.can, r.khu_vuc as khu_vuc_rong, r.nha_xe as nx_rong, r.lo_kd as lo_kd_rong,
          r.kho_lh as lh_rong, r.kho_sdt as sdt_rong, r.kho_map as map_rong,
          d.so_cont, d.so_seal, d.lo as lo_day, d.kho as kho_day, d.khu_vuc as khu_vuc_day, d.du_kien_day, d.nha_xe as nx_day, d.ngay_den_kho as den_day,
          d.closing_uoc, d.muc, d.trang_thai as trang_thai_day, coalesce(d.lo_kd, false) as lo_kd_day,
          d.kho_lh as lh_day, d.kho_sdt as sdt_day, d.kho_map as map_day,
          coalesce(d.du_kien_day, d.closing) as du_kien,
          coalesce(d.closing, r.closing) as closing,
          extract(epoch from (coalesce(d.closing, r.closing) - v_now)) / 3600 as h_cl,
          case when cap.id_day is null then extract(epoch from (coalesce(r.can, v_now) - v_now)) / 3600 end as h_ref,
          (d.id is not null and d.kd_can) as kd_chua
        from _cap cap
        left join _rong r on r.id = cap.id_rong
        left join _day d on d.id = cap.id_day
      ) w
    ) y
  ) x;

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke execute on function public.tao_goi_y() from public, anon;
grant execute on function public.tao_goi_y() to authenticated;
