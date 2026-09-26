-- Migration: sửa hàm bat_tat_ai_duoc_luu (bản tạo tay trên Supabase kiểm tra quyền QL sai
-- -> chặn cả Quản lý). Thay bằng cách kiểm tra chuẩn qua private.vai_tro_hien_tai().
drop function if exists public.bat_tat_ai_duoc_luu(text, boolean);
create or replace function public.bat_tat_ai_duoc_luu(p_email text, p_bat boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được đổi quyền AI';
  end if;
  update public.nhan_vien set ai_duoc_luu = p_bat where email = lower(p_email);
end;
$$;
revoke execute on function public.bat_tat_ai_duoc_luu(text, boolean) from public, anon;
grant execute on function public.bat_tat_ai_duoc_luu(text, boolean) to authenticated;
