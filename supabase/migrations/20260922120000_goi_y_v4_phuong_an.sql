-- =====================================================================
-- GỢI Ý v4: nhóm phương án + mức 1 nhất quán toàn lô
--
-- GHI LẠI TỪ DATABASE THẬT (23/09/2026). Các đối tượng dưới đây đã được
-- tài khoản chính tạo thẳng trên Supabase (commit d129951 chỉ sửa index.html,
-- không kèm migration). File này bổ sung để repo có đủ mã nguồn.
-- KHÔNG cần chạy lại trên DB hiện tại (đã có sẵn). Viết idempotent nên
-- chạy lại cũng không hỏng (add column if not exists / create or replace).
--
-- Cách hoạt động:
--  * tao_goi_y_v4(): khi 1 rỗng có ≥2 cont đầy "ngang tài" (cùng kho/khu vực,
--    cùng mức ưu tiên, CLS lệch ≤24h) → sinh tối đa 4 gợi ý cùng nhom_gy,
--    đánh dấu la_phuong_an = true để điều độ chọn 1.
--  * duyet_phuong_an(p_id, p_nha_xe): duyệt cont được chọn; các cont còn lại
--    cùng nhóm tự chuyển thành lệnh RÚT MOOC (không mang rỗng).
--  * Cron "goi-y-ke-hoach-moi-gio" chạy tao_goi_y_v4() phút 5 mỗi giờ.
-- =====================================================================

alter table public.goi_y add column if not exists la_phuong_an boolean default false;
alter table public.goi_y add column if not exists nhom_gy text;

CREATE OR REPLACE FUNCTION public.duyet_phuong_an(p_id text, p_nha_xe text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_nhom text;
  v_cnt int := 0;
begin
  if auth.uid() is not null and coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ') then
    raise exception 'Bạn không có quyền duyệt gợi ý';
  end if;

  select nhom_gy into v_nhom from public.goi_y where id = p_id;
  if not found then
    raise exception 'Không tìm thấy gợi ý %', p_id;
  end if;

  update public.goi_y
     set duyet        = true,
         la_phuong_an = false,
         nhom_gy      = null,
         nha_xe_chon  = coalesce(p_nha_xe, nha_xe_chon, nha_xe_goi_y)
   where id = p_id;

  if v_nhom is null then
    return 0;
  end if;

  update public.goi_y g
     set loai_lenh        = 'Rút mooc 拉满柜',
         la_phuong_an     = false,
         nhom_gy          = null,
         id_cont_rong     = null,
         ma_don_rong      = null,
         booking_lay_rong = null,
         kho_cat_rong     = null,
         hang_tau         = null,
         chi_phi_uoc_tinh = null,
         chi_phi_ghi_chu  = 'Chuyển từ phương án đổi rỗng — cần tính lại giá rút mooc',
         ly_do = '⚠ Rỗng đã dành cho cont khác cùng nhóm → cont này chuyển RÚT MOOC (đầu kéo lên kéo đầy, không mang rỗng)',
         noi_dung_lenh = concat_ws(E'\n',
            'LỆNH RÚT MOOC 拉满柜',
            'Đầu kéo chạy không lên kéo cont đầy 空车上去拉满柜',
            case when g.cont_day is not null then 'Cont đầy 满柜: ' || g.cont_day end,
            'Kho đầy 装货点: ' || coalesce(g.kho_day, '—'),
            case when g.noi_ha is not null then 'Nơi hạ 还柜点: ' || g.noi_ha end,
            'CUT-OFF 截关: ' || coalesce(to_char(g.closing at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM/YYYY'), '—'),
            'Nhà xe 车队: ' || coalesce(g.nha_xe_goi_y, '—'),
            '⚠ Đã chọn phương án khác cho rỗng — cont này chuyển RÚT MOOC')
   where g.nhom_gy = v_nhom and g.id <> p_id;

  get diagnostics v_cnt = row_count;
  return v_cnt;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.tao_goi_y_v4()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_now timestamptz := now();
  v_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_bai text; v_gio_ha numeric; v_khung numeric; v_gio_dong numeric; v_giu int; v_quen int;
  v_kd numeric; v_thuong numeric; v_gan numeric; v_bai_kd text;
  v_phien int;
  v_prefix text;
  v_id text; v_n int; e record;
  used_f text[] := '{}'; used_e text[] := '{}';
  v_grp text; v_tie text[]; v_top_id text; v_top_ck boolean; v_top_muc int; v_top_cls timestamptz;
begin
  if auth.uid() is not null and coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ') then
    raise exception 'Bạn không có quyền chạy gợi ý kế hoạch';
  end if;

  if not pg_try_advisory_xact_lock(hashtext('tao_goi_y')) then
    return -1;
  end if;

  v_phien  := nextval('public.goi_y_phien_seq');
  v_prefix := 'GY' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYYMMDDHH24MISS') || '-';

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
  v_bai_kd := case when v_bai in ('HLS', 'PD', 'HT') then v_bai else 'HLS' end;

  delete from public.goi_y where not duyet;

  create temp table _day on commit drop as
  select z.*,
    case when z.h_cls < 0 then 0
         when (not z.lo_kd) and z.h_cls <= v_kd then 1
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

  create temp table _cap (stt serial, loai text, id_rong text, id_day text, nhom text, pa boolean default false) on commit drop;

  insert into _cap (loai, id_rong, id_day)
  select 'dong', r.id, null from _rong r where r.dong_ngay order by r.can nulls first, r.id;
  select coalesce(array_agg(id), '{}') into used_e from _rong where dong_ngay;

  for e in select id, kho, khu_vuc, nha_xe from _rong where not (id = any(used_e)) order by can nulls first, id loop
    v_top_id := null;
    select d.id, (d.kho = e.kho), d.muc, d.closing
      into v_top_id, v_top_ck, v_top_muc, v_top_cls
    from _day d
    where (d.kho = e.kho or (e.khu_vuc is not null and d.khu_vuc = e.khu_vuc))
      and d.nha_xe is not null and (e.nha_xe is null or d.nha_xe = e.nha_xe)
      and not (d.id = any(used_f))
    order by (d.kho = e.kho) desc, d.muc, d.closing nulls last, d.id
    limit 1;

    if v_top_id is null then
      continue;
    end if;

    select array_agg(t.id order by t.rn)
      into v_tie
    from (
      select d.id,
             row_number() over (order by (d.kho = e.kho) desc, d.muc, d.closing nulls last, d.id) as rn
      from _day d
      where (d.kho = e.kho or (e.khu_vuc is not null and d.khu_vuc = e.khu_vuc))
        and d.nha_xe is not null and (e.nha_xe is null or d.nha_xe = e.nha_xe)
        and not (d.id = any(used_f))
        and (d.kho = e.kho) = v_top_ck
        and d.muc = v_top_muc
        and ( (d.closing is null and v_top_cls is null)
              or (d.closing is not null and v_top_cls is not null
                  and abs(extract(epoch from (d.closing - v_top_cls)) / 3600) <= 24) )
    ) t
    where t.rn <= 4;

    if coalesce(array_length(v_tie, 1), 0) >= 2 then
      v_grp := 'PA-' || v_phien || '-' || e.id;
      insert into _cap (loai, id_rong, id_day, nhom, pa)
      select 'doi', e.id, x, v_grp, true from unnest(v_tie) as x;
      used_f := used_f || v_tie;
      used_e := used_e || e.id;
    else
      insert into _cap (loai, id_rong, id_day) values ('doi', e.id, v_top_id);
      used_f := used_f || v_top_id;
      used_e := used_e || e.id;
    end if;
  end loop;

  insert into _cap (loai, id_rong, id_day)
  select 'cat', r.id, null from _rong r where not (r.id = any(used_e)) order by r.can nulls first, r.id;

  insert into _cap (loai, id_rong, id_day)
  select 'rut', null, d.id from _day d where not (d.id = any(used_f)) and d.muc <= 2 order by d.muc, d.closing nulls last, d.id;

  insert into public.goi_y (id, ngay_kh, uu_tien, loai_lenh, booking_lay_rong, hang_tau, kho_cat_rong, id_cont_rong, ma_don_rong,
    cont_day, id_cont_day, kho_day, du_kien_day, noi_ha, closing, con_lai_gio, nha_xe_goi_y, ly_do, noi_dung_lenh,
    chi_phi_uoc_tinh, chi_phi_ghi_chu, muc_uu_tien, phien, nhom_gy, la_phuong_an)
  select v_prefix || lpad((row_number() over (order by x.uu_tien, x.closing nulls last, x.stt))::text, 2, '0'),
    v_today, x.uu_tien, x.loai_lenh, x.booking, x.hang_tau, x.kho_rong, x.id_rong, x.ma_don_rong,
    x.so_cont, x.id_day, x.kho_day, x.du_kien, x.noi_ha, x.closing, round(x.h_cl), x.nha_xe,
    nullif(concat_ws('; ',
      case x.muc when 0 then '⚠ ĐÃ QUÁ CLS ' || round(-x.h_cl) || 'h — kéo gấp, kiểm tra đổi tàu / CLS mới'
                 when 1 then 'GẤP: lô chưa kiểm dịch, còn ' || round(x.h_cl) || 'h tới CLS (≤72h) — toàn lô gấp, cần về bãi kiểm dịch'
                 when 2 then 'Sát CLS: còn ' || round(x.h_cl) || 'h'
                 when 3 then 'CLS trong ' || v_gan || ' ngày' end,
      case when x.pa then '★ PHƯƠNG ÁN: rỗng này có nhiều cont đầy ngang mức — chọn cont này thì (các) cont còn cùng nhóm chuyển rút mooc' end,
      case when x.id_day is not null and x.nx_day is not null then 'Mooc của ' || x.nx_day || coalesce(' (kéo lên ' || to_char(x.den_day, 'DD/MM') || ')', '') || ' → chỉ ' || x.nx_day || ' kéo được' end,
      case when x.id_day is not null and x.nx_day is null then '⚠ Chưa rõ cont nằm trên mooc nhà xe nào — hỏi kho trước khi điều xe' end,
      case when x.loai = 'doi' and x.kho_day is distinct from x.kho_rong then 'Kéo đầy ở kho khác cùng khu vực ' || coalesce(x.khu_vuc_rong, '') end,
      case when x.loai = 'cat' then 'Không có cont đầy cùng kho / khu vực để ghép → cắt mooc' end,
      case when x.loai = 'dong' then 'Lô đóng TRONG NGÀY — quá ngày phát sinh phí đầy chờ kéo 1.600.000đ/ngày' end,
      case when x.id_rong is not null and x.can is not null then 'Kho cần rỗng ' || to_char(x.can at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') end,
      case when x.id_day is not null and x.trang_thai_day = '2' and x.du_kien_day is null then 'Cont đang đóng, chưa nhập Dự kiến đầy — CLS gần nên máy coi như đã đầy' end,
      case when x.closing_uoc then 'CLS ước tính = ETD - 1 ngày' end,
      case when x.kd_chua then 'Cont kiểm dịch → về bãi ' || v_bai_kd || ' chờ kiểm (chỉ kiểm ở HLS / PD / HT)'
           when x.id_day is not null and not x.lo_kd_day then 'Lô chưa kiểm dịch → chỉ về bãi, chưa được hạ cảng'
           when x.id_day is not null and x.h_cl <= v_gio_ha then 'Lô đã kiểm dịch, còn ' || round(x.h_cl) || 'h tới CLS (≤ ' || v_gio_ha || 'h) → hạ thẳng cảng'
           when x.id_day is not null then 'Lô đã kiểm dịch, CLS còn > ' || v_gio_ha || 'h → hạ bãi' end,
      case when x.h_cl < 0 and x.muc is distinct from 0 then '⚠ ĐÃ QUÁ CLOSING' end,
      case when x.id_rong is not null and x.booking is null then '⚠ Đơn chưa có booking' end,
      case when x.gia is null and x.nha_xe is not null then 'Chưa có giá cước ' || x.nha_xe || ' cho lệnh này' end
    ), ''),
    concat_ws(E'\n',
      case x.loai when 'dong' then 'LỆNH ĐÓNG TRONG NGÀY 当天装柜' when 'doi' then 'LỆNH ĐỔI RỖNG KÉO ĐẦY 换空拉满'
                  when 'cat' then 'LỆNH CẮT MOOC 甩挂' else 'LỆNH RÚT MOOC 拉满柜' end,
      case when x.pa then '★ 1 trong nhiều phương án — điều độ chọn 1 请选一个方案' end,
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
    case x.muc when 0 then 'Quá CLS' when 1 then 'KD gấp' when 2 then 'Sát CLS' when 3 then 'CLS gần' when 4 then 'CLS xa' end,
    v_phien,
    x.nhom,
    x.pa
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
        select cap.stt, cap.loai, cap.id_rong, cap.id_day, cap.nhom, cap.pa,
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
$function$
;

-- Quyền trên DB thật (23/09): cả 2 hàm có EXECUTE cho PUBLIC, anon,
-- authenticated, service_role (mặc định khi tạo hàm). An toàn vì hàm chạy
-- quyền người gọi (không SECURITY DEFINER) nên RLS bảng goi_y vẫn chặn anon.

-- Lịch chạy mỗi giờ đã chuyển sang v4 (thay cron v3 của 20260921091002):
select cron.schedule('goi-y-ke-hoach-moi-gio', '5 * * * *', 'select public.tao_goi_y_v4();');
