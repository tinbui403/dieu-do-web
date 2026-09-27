-- Migration: Nhà xe kiêm bãi tạm (vd HLS) được xem THÊM cont đang ở bãi của mình
-- Yêu cầu anh Hi 27/09: nhà xe HLS vừa là nhà xe vừa là bãi tạm → ngoài cont của nhà xe HLS,
-- còn xem được các cont đang Ở BÃI HLS (dù do nhà xe khác kéo về).
-- Mở rộng RPC cont_cua_toi(): thêm điều kiện bãi + cột "thuoc" ('xe' | 'bai') để web tách 2 nhóm.
-- Linh hoạt: khớp khi nha_xe của tài khoản = mã/tên bãi (bao cả trường hợp lưu 'HLS' hoặc 'Hoàng Liên Sơn').
-- Nhà xe không kiêm bãi thì không có cont nhóm 'bai' → không ảnh hưởng.

drop function if exists public.cont_cua_toi();
create function public.cont_cua_toi()
returns table (
  so_cont text, lo text, trang_thai text, trang_thai_ten text,
  kho text, bai_tam text, ngay_den_kho date, ngay_can_len_kho timestamptz,
  gio_vao_bai timestamptz, cap_nhat_luc timestamptz, thuoc text
)
language sql stable security definer set search_path = '' as $$
  with me as (select (select private.nha_xe_hien_tai()) as nx)
  select c.so_cont, c.lo, c.trang_thai,
    case c.trang_thai
      when '1' then 'Đơn chờ lên' when '2' then 'Đang đóng hàng' when '3' then 'Đầy chờ kéo'
      when '4' then 'Ở bãi tạm'  when '5' then 'Đã hạ cảng'     when '6' then 'Đã lên tàu'
      when '9' then 'Hủy/đổi cont' else c.trang_thai end,
    c.kho, c.bai_tam, c.ngay_den_kho, c.ngay_can_len_kho, c.gio_vao_bai, c.cap_nhat_luc,
    case when c.nha_xe = (select nx from me) then 'xe' else 'bai' end as thuoc
  from public.cont c, me
  where me.nx is not null
    and c.trang_thai <> '9'
    and (
      c.nha_xe = me.nx
      or (
        c.trang_thai = '4' and c.bai_tam is not null and (
          upper(c.bai_tam) = upper(me.nx)
          or exists (
            select 1 from public.bai_tam b
            where b.ma = c.bai_tam and (upper(b.ma) = upper(me.nx) or upper(b.ten) = upper(me.nx))
          )
        )
      )
    )
  order by (c.nha_xe = (select nx from me)) desc, c.trang_thai, c.so_cont
$$;
revoke execute on function public.cont_cua_toi() from public, anon;
grant execute on function public.cont_cua_toi() to authenticated;
