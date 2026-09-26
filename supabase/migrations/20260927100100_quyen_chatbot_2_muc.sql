-- Migration: phân quyền chatbot 2 mức per-account
--   1) ai_hoi_dap  = được dùng chatbot để HỎI ĐÁP / tra cứu (đọc)
--   2) ai_thao_tac = được ra lệnh chatbot GHI dữ liệu (tạo/sửa booking, lô, cont, đổi trạng thái, kéo cont)
-- Tái dùng cột ai_duoc_luu (đã có) làm nền quyền thao tác; thêm cột ai_hoi_dap.
-- An toàn / idempotent: ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE. KHÔNG đụng toi_la_ai (giữ nguyên).

alter table public.nhan_vien add column if not exists ai_hoi_dap boolean;

-- Trả về quyền chatbot của user hiện tại.
--   ai_hoi_dap : nếu QL đã set cột thì theo cột; chưa set thì mặc định theo vai trò (QL/ĐĐ/CSKH = true).
--   ai_thao_tac: ai_duoc_luu = true VÀ vai trò thuộc QL/ĐĐ (chốt: chỉ QL + ĐĐ được thao tác).
create or replace function public.quyen_chatbot()
returns table (ai_hoi_dap boolean, ai_thao_tac boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(nv.ai_hoi_dap, nv.vai_tro in ('Quản lý', 'Điều độ', 'CSKH')) as ai_hoi_dap,
    (coalesce(nv.ai_duoc_luu, false) and nv.vai_tro in ('Quản lý', 'Điều độ')) as ai_thao_tac
  from public.nhan_vien nv
  where nv.email = lower(coalesce(auth.jwt() ->> 'email', '')) and nv.hoat_dong
$$;
revoke execute on function public.quyen_chatbot() from public, anon;
grant execute on function public.quyen_chatbot() to authenticated;

-- QL bật/tắt quyền HỎI ĐÁP cho một tài khoản.
create or replace function public.bat_tat_ai_hoi_dap(p_email text, p_bat boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được đổi quyền chatbot';
  end if;
  update public.nhan_vien set ai_hoi_dap = p_bat where email = lower(p_email);
end;
$$;
revoke execute on function public.bat_tat_ai_hoi_dap(text, boolean) from public, anon;
grant execute on function public.bat_tat_ai_hoi_dap(text, boolean) to authenticated;
