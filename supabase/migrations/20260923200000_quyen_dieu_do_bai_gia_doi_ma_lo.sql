-- ============================================================
-- MỞ QUYỀN CHO ĐIỀU ĐỘ (anh Hi chốt 23/09/2026): Bãi tạm, Giá cước nhà xe, Đổi mã lô
-- trước đây chỉ Quản lý → nay Quản lý + Điều độ đều nhập / sửa được.
--  - bai_tam: thêm + sửa (xoá bãi vẫn chỉ Quản lý, web không có nút xoá bãi).
--  - bang_gia_xe: thêm + sửa + xoá (xoá = để trống 1 ô giá khi sửa bảng giá).
--  - doi_ma_lo: Quản lý + Điều độ.
-- ============================================================
drop policy if exists "quan ly them" on public.bai_tam;
drop policy if exists "quan ly sua" on public.bai_tam;
create policy "ql dd them" on public.bai_tam for insert to authenticated
  with check ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ'));
create policy "ql dd sua" on public.bai_tam for update to authenticated
  using ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ'))
  with check ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ'));

drop policy if exists "quan ly them" on public.bang_gia_xe;
drop policy if exists "quan ly sua" on public.bang_gia_xe;
drop policy if exists "quan ly xoa" on public.bang_gia_xe;
create policy "ql dd them" on public.bang_gia_xe for insert to authenticated
  with check ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ'));
create policy "ql dd sua" on public.bang_gia_xe for update to authenticated
  using ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ'))
  with check ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ'));
create policy "ql dd xoa" on public.bang_gia_xe for delete to authenticated
  using ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ'));

create or replace function public.doi_ma_lo(p_cu text, p_moi text)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare v_moi text := trim(coalesce(p_moi, '')); v_n int;
begin
  if coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ') then
    raise exception 'Chỉ Quản lý hoặc Điều độ được đổi mã lô';
  end if;
  if v_moi = '' then
    raise exception 'Chưa nhập mã lô mới';
  end if;
  if v_moi = p_cu then
    raise exception 'Mã lô mới trùng mã cũ';
  end if;
  if not exists (select 1 from public.lo where lo = p_cu) then
    raise exception 'Không tìm thấy lô %', p_cu;
  end if;
  if exists (select 1 from public.lo where lo = v_moi) then
    raise exception 'Mã lô % đã có — chọn mã khác', v_moi;
  end if;
  perform set_config('dieu_do.bo_qua_kiem_tra', 'on', true);
  update public.lo set lo = v_moi where lo = p_cu;
  perform set_config('dieu_do.bo_qua_kiem_tra', 'off', true);
  select count(*) into v_n from public.cont where lo = v_moi;
  return v_n;
end;
$$;
