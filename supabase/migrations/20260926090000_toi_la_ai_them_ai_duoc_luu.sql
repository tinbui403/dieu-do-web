-- Migration: cập nhật hàm toi_la_ai để trả về thêm cột ai_duoc_luu
-- (hàm này được tạo trực tiếp trên Supabase, không có trong migration cũ)
-- Chạy qua SQL Editor Supabase; không ảnh hưởng dữ liệu.

create or replace function public.toi_la_ai()
returns table (
  id            uuid,
  email         text,
  ho_ten        text,
  vai_tro       text,
  ngon_ngu      text,
  nha_xe        text,
  hoat_dong     boolean,
  ai_duoc_luu   boolean
)
language plpgsql security definer
set search_path = public, private
as $fn$
begin
  return query
    select
      nv.id,
      nv.email,
      nv.ho_ten,
      nv.vai_tro,
      nv.ngon_ngu,
      nv.nha_xe,
      nv.hoat_dong,
      nv.ai_duoc_luu
    from public.nhan_vien nv
    join auth.users au on lower(au.email) = nv.email
   where au.id = auth.uid()
     and nv.hoat_dong = true;
end;
$fn$;

grant execute on function public.toi_la_ai() to authenticated;
