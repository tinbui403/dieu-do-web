-- ============================================================
-- DUYỆT GỢI Ý → GÁN NHÀ XE VÀO ĐƠN RỖNG (anh Hi chốt 24/09/2026)
--  - Gợi ý được duyệt (bấm Duyệt thường hoặc duyet_phuong_an) có đơn rỗng (id_cont_rong):
--    đơn rỗng đang "1 · Chờ cắt rỗng" nhận nhà xe = nhà xe đã chọn khi duyệt (nha_xe_chon, không có thì nha_xe_goi_y).
--  - Chỉ đơn rỗng; cont đầy KHÔNG đổi.
--  - Đổi nhà xe trên gợi ý đã duyệt → đơn rỗng đổi theo.
--  - Bỏ duyệt → gỡ nhà xe khỏi đơn rỗng nếu đơn vẫn "Chờ cắt rỗng" và nhà xe đang đúng nhà xe đã gán.
--  - Bộ gợi ý v4 vốn đã tôn trọng nhà xe của đơn rỗng (chỉ ghép với cont đầy cùng nhà xe) → không lệch kế hoạch.
-- ============================================================
create or replace function private.goi_y_gan_nha_xe()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare v_moi text; v_cu text;
begin
  v_moi := case when new.duyet then coalesce(new.nha_xe_chon, new.nha_xe_goi_y) end;
  v_cu  := case when old.duyet then coalesce(old.nha_xe_chon, old.nha_xe_goi_y) end;
  -- Bỏ duyệt, hoặc đổi sang nhà xe khác / đơn rỗng khác: gỡ nhà xe cũ (đơn chưa chạy)
  if old.id_cont_rong is not null and v_cu is not null
     and (v_moi is null or v_moi is distinct from v_cu or new.id_cont_rong is distinct from old.id_cont_rong) then
    update public.cont set nha_xe = null
     where id = old.id_cont_rong and trang_thai = '1' and nha_xe = v_cu;
  end if;
  -- Duyệt (hoặc đổi nhà xe khi đã duyệt): gán nhà xe vào đơn rỗng đang chờ cắt rỗng
  if new.id_cont_rong is not null and v_moi is not null then
    update public.cont set nha_xe = v_moi
     where id = new.id_cont_rong and trang_thai = '1' and nha_xe is distinct from v_moi
       and exists (select 1 from public.nha_xe n where n.ma = v_moi);  -- nhà xe phải có trong Danh mục (khoá ngoại)
  end if;
  return null;
end;
$function$;
revoke execute on function private.goi_y_gan_nha_xe() from public, anon, authenticated;
drop trigger if exists goi_y_gan_nha_xe on public.goi_y;
create trigger goi_y_gan_nha_xe after update of duyet, nha_xe_chon, id_cont_rong on public.goi_y
  for each row execute function private.goi_y_gan_nha_xe();

-- Gợi ý ĐÃ duyệt từ trước (chưa chạy): gán luôn cho đơn rỗng đang chờ cắt rỗng mà chưa có nhà xe
update public.cont c
   set nha_xe = coalesce(g.nha_xe_chon, g.nha_xe_goi_y)
  from public.goi_y g
 where g.duyet and not g.da_ap_dung and g.id_cont_rong = c.id
   and c.trang_thai = '1' and c.nha_xe is null
   and exists (select 1 from public.nha_xe n where n.ma = coalesce(g.nha_xe_chon, g.nha_xe_goi_y));
