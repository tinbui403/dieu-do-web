-- Lô: số lượng cont kế hoạch + thứ tự tự đặt
alter table public.lo
  add column so_luong_cont int check (so_luong_cont is null or so_luong_cont between 0 and 200),
  add column thu_tu int;

-- View phải tạo lại để có 2 cột mới
drop view public.lo_tong_hop;
create view public.lo_tong_hop with (security_invoker = true) as
select l.*,
  count(c.id) as so_cont,
  count(c.id) filter (where c.trang_thai in ('1','2','3','4','5')) as so_cont_dang_chay
from public.lo l
left join public.cont c on c.lo = l.lo
group by l.lo;

-- Xoá lô không dùng nữa: chỉ Quản lý; chỉ khi mọi cont của lô còn ở "Chờ cắt rỗng" (1) hoặc "Hủy" (9).
-- Xoá luôn các đơn đó và gợi ý liên quan, trong 1 lần (hoặc xoá hết, hoặc không xoá gì).
create or replace function public.xoa_lo(p_lo text)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare v_chay int; v_n int;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được xoá lô';
  end if;
  if not exists (select 1 from public.lo where lo = p_lo) then
    raise exception 'Không tìm thấy lô %', p_lo;
  end if;
  select count(*) into v_chay from public.cont where lo = p_lo and trang_thai not in ('1', '9');
  if v_chay > 0 then
    raise exception 'Lô % có % cont đã chạy thực tế (đã tới kho / bãi / cảng / lên tàu) nên không xoá được, để giữ lịch sử và tiền cước.', p_lo, v_chay;
  end if;
  delete from public.goi_y g
   where g.id_cont_rong in (select c.id from public.cont c where c.lo = p_lo)
      or g.id_cont_day in (select c.id from public.cont c where c.lo = p_lo);
  delete from public.cont where lo = p_lo;
  get diagnostics v_n = row_count;
  delete from public.lo where lo = p_lo;
  return v_n;
end;
$$;
revoke execute on function public.xoa_lo(text) from public, anon;
grant execute on function public.xoa_lo(text) to authenticated;

-- Xoá 1 đơn/cont: chỉ Quản lý; chỉ khi cont ở "Chờ cắt rỗng" (1) hoặc "Hủy" (9)
create or replace function public.xoa_cont(p_id text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare v_tt text;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được xoá cont';
  end if;
  select trang_thai into v_tt from public.cont where id = p_id;
  if not found then raise exception 'Không tìm thấy cont %', p_id; end if;
  if v_tt not in ('1', '9') then
    raise exception 'Cont đã chạy thực tế nên không xoá được. Nếu bỏ, hãy chuyển sang trạng thái "Hủy đổi cont".';
  end if;
  delete from public.goi_y where id_cont_rong = p_id or id_cont_day = p_id;
  delete from public.cont where id = p_id;
end;
$$;
revoke execute on function public.xoa_cont(text) from public, anon;
grant execute on function public.xoa_cont(text) to authenticated;
