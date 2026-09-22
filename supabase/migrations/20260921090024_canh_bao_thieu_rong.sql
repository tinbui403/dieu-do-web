-- =====================================================================
-- canh_bao_thieu_rong()  —  [V3] mới
-- =====================================================================
-- Cont đầy mức 3 (CLS gần, chưa gấp) mà khu vực KHÔNG còn rỗng nào.
-- KHÔNG ghi vào goi_y (không duyệt được, sẽ làm rác hàng chờ duyệt).
-- Web gọi riêng, hiện 1 dòng nhỏ để điều độ chuẩn bị sớm.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.canh_bao_thieu_rong()
 RETURNS TABLE(id_cont text, so_cont text, lo text, kho text, khu_vuc text,
               closing timestamptz, con_lai_gio numeric, nha_xe text, canh_bao text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with cfg as (
    select coalesce(max(gia_tri) filter (where tham_so = 'Số giờ cont thường cần kéo trước CLS'), '48')::numeric as g_thuong,
           coalesce(max(gia_tri) filter (where tham_so = 'Số ngày CLS gần'), '5')::numeric as n_gan
    from public.cau_hinh
  ),
  day as (
    select c.id, c.so_cont, c.lo, c.kho, k.khu_vuc, c.nha_xe,
           coalesce(l.cls, ((coalesce(l.etd, l.etd_kho) - 1)::timestamp at time zone 'Asia/Ho_Chi_Minh')) as cls
    from public.cont c
    left join public.lo l on l.lo = c.lo
    left join public.kho k on k.ten = c.kho
    where c.trang_thai = '3' and c.so_cont is not null and not coalesce(l.da_huy, false)
  ),
  rong as (
    select distinct k.khu_vuc
    from public.cont c
    left join public.lo l on l.lo = c.lo
    left join public.kho k on k.ten = c.kho
    where c.trang_thai = '1' and not coalesce(l.da_huy, false) and k.khu_vuc is not null
  )
  select d.id, d.so_cont, d.lo, d.kho, d.khu_vuc, d.cls,
         round(extract(epoch from (d.cls - now())) / 3600) as con_lai_gio,
         d.nha_xe,
         'CLS còn ' || round(extract(epoch from (d.cls - now())) / 3600)
           || 'h — khu vực ' || coalesce(d.khu_vuc, '(chưa điền)') || ' chưa có rỗng nào. Cần chuẩn bị sớm.'
  from day d, cfg
  where d.cls is not null
    and extract(epoch from (d.cls - now())) / 3600 > cfg.g_thuong
    and extract(epoch from (d.cls - now())) / 3600 <= cfg.n_gan * 24
    and (d.khu_vuc is null or d.khu_vuc not in (select khu_vuc from rong))
  order by d.cls;
$function$;

GRANT EXECUTE ON FUNCTION public.canh_bao_thieu_rong() TO authenticated;
