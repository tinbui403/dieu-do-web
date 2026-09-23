-- ============================================================
-- ĐỔI MÃ LÔ (anh Hi chốt 23/09/2026): đổi mã lô đã tạo, cont đi theo, chỉ Quản lý.
--  - cont.lo khai báo "references lo(lo) on update cascade" → đổi lo.lo là mọi cont tự đổi theo.
--  - Gợi ý (goi_y) nối với cont bằng id cont, không chứa mã lô → không cần đổi.
--  - Tạm bỏ qua trigger kiểm dịch trong lúc đổi (dieu_do.bo_qua_kiem_tra), vì trigger cont_sau_kd
--    thấy cont kiểm dịch "đổi lô" sẽ tự bỏ tích "Lô đã kiểm dịch" của lô → đổi tên không được làm mất tích KD.
--  - Nhật ký giữ nguyên (không sửa): trigger nk_lo tự ghi 1 dòng "lo: cũ → mới" dưới mã mới;
--    web tự nối lịch sử của mã cũ theo dòng này.
-- ============================================================
create or replace function public.doi_ma_lo(p_cu text, p_moi text)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare v_moi text := trim(coalesce(p_moi, '')); v_n int;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được đổi mã lô';
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
revoke execute on function public.doi_ma_lo(text, text) from public, anon;
grant execute on function public.doi_ma_lo(text, text) to authenticated;
