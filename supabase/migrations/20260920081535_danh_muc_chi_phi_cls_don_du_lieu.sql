-- ===== 1. QUYỀN DANH MỤC =====
-- Nhà xe: Quản lý, Điều độ, CSKH được thêm / sửa / xoá
drop policy "quan ly xoa" on public.nha_xe;
create policy "ql dd cskh xoa" on public.nha_xe for delete to authenticated
  using ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ', 'CSKH'));
-- Kho: Quản lý, CSKH được thêm / xoá (Điều độ vẫn được sửa thông tin kho)
drop policy "nhan vien them" on public.kho;
create policy "ql cskh them" on public.kho for insert to authenticated
  with check ((select private.vai_tro_hien_tai()) in ('Quản lý', 'CSKH'));
drop policy "quan ly xoa" on public.kho;
create policy "ql cskh xoa" on public.kho for delete to authenticated
  using ((select private.vai_tro_hien_tai()) in ('Quản lý', 'CSKH'));
-- Bãi tạm: giá do Quản lý (Admin) nhập
drop policy "nhan vien them" on public.bai_tam;
drop policy "nhan vien sua" on public.bai_tam;
create policy "quan ly them" on public.bai_tam for insert to authenticated
  with check ((select private.vai_tro_hien_tai()) = 'Quản lý');
create policy "quan ly sua" on public.bai_tam for update to authenticated
  using ((select private.vai_tro_hien_tai()) = 'Quản lý') with check ((select private.vai_tro_hien_tai()) = 'Quản lý');

alter table public.nha_xe add column hoat_dong boolean not null default true;
alter table public.kho add column hoat_dong boolean not null default true;
comment on column public.bai_tam.dien_moi_gio is 'Tiền điện mỗi giờ (tính theo giờ thực tế vào → ra bãi)';
comment on column public.bai_tam.nang_ha is 'Phí nâng hạ, tính 1 lần khi hạ vào bãi';
comment on column public.bai_tam.trucking is 'Tiền vận chuyển hạ cảng (bãi → cảng), mỗi bãi 1 giá';

-- Xoá nhà xe: chưa từng dùng thì xoá hẳn; đã có cont / nhân viên / gợi ý dùng thì chuyển "ngưng" để giữ lịch sử
create or replace function public.xoa_nha_xe(p_ma text)
returns text language plpgsql security invoker set search_path = '' as $$
begin
  if coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ', 'CSKH') then
    raise exception 'Bạn không có quyền xoá nhà xe';
  end if;
  if exists (select 1 from public.cont where nha_xe = p_ma)
     or exists (select 1 from public.nhan_vien where nha_xe = p_ma)
     or exists (select 1 from public.goi_y where nha_xe_chon = p_ma) then
    update public.nha_xe set hoat_dong = false where ma = p_ma;
    return 'ngung';
  end if;
  delete from public.nha_xe where ma = p_ma;
  return 'xoa';
end; $$;
revoke execute on function public.xoa_nha_xe(text) from public, anon;
grant execute on function public.xoa_nha_xe(text) to authenticated;

create or replace function public.xoa_kho(p_ten text)
returns text language plpgsql security invoker set search_path = '' as $$
begin
  if coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'CSKH') then
    raise exception 'Chỉ Quản lý hoặc CSKH được xoá kho';
  end if;
  if exists (select 1 from public.cont where kho = p_ten) then
    update public.kho set hoat_dong = false where ten = p_ten;
    return 'ngung';
  end if;
  delete from public.kho where ten = p_ten;
  return 'xoa';
end; $$;
revoke execute on function public.xoa_kho(text) from public, anon;
grant execute on function public.xoa_kho(text) to authenticated;

-- Xoá nhân viên nghỉ việc: bỏ khỏi danh sách + xoá luôn tài khoản đăng nhập (chỉ Quản lý, không tự xoá mình)
create or replace function public.xoa_nhan_vien(p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_email text := lower(trim(p_email));
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được xoá nhân viên';
  end if;
  if v_email = lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'Không thể tự xoá tài khoản của chính mình';
  end if;
  delete from public.nhan_vien where email = v_email;
  delete from auth.users where lower(email) = v_email;
end; $$;
revoke execute on function public.xoa_nhan_vien(text) from public, anon;
grant execute on function public.xoa_nhan_vien(text) to authenticated;

-- ===== 2. CHI PHÍ PHÁT SINH THEO CONT =====
create table public.chi_phi_cont (
  id bigint generated always as identity primary key,
  cont_id text not null references public.cont(id) on update cascade on delete cascade,
  loai text not null check (loai in ('PTI', 'Đổi seal', 'Sửa chữa', 'Lưu bãi', 'Lưu cont', 'Khác')),
  so_tien numeric not null check (so_tien >= 0),
  ghi_chu text,
  tao_boi text default (auth.jwt() ->> 'email'),
  tao_luc timestamptz not null default now()
);
create index chi_phi_cont_cont_idx on public.chi_phi_cont (cont_id);
alter table public.chi_phi_cont enable row level security;
create policy "nhan vien doc" on public.chi_phi_cont for select to authenticated using ((select private.vai_tro_hien_tai()) is not null);
create policy "nhan vien them" on public.chi_phi_cont for insert to authenticated with check ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ', 'CSKH'));
create policy "nhan vien sua" on public.chi_phi_cont for update to authenticated using ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ', 'CSKH')) with check ((select private.vai_tro_hien_tai()) in ('Quản lý', 'Điều độ', 'CSKH'));
create policy "quan ly xoa" on public.chi_phi_cont for delete to authenticated using ((select private.vai_tro_hien_tai()) = 'Quản lý');

-- ===== 3. BẢNG GIÁ CƯỚC NHÀ XE (để ước tính chi phí, chọn nhà xe rẻ nhất) =====
create table public.bang_gia_xe (
  nha_xe text not null references public.nha_xe(ma) on update cascade on delete cascade,
  khu_vuc text not null,           -- khu vực kho; 'Tất cả' = giá chung khi chưa có giá riêng khu vực
  loai text not null check (loai in ('dong_trong_ngay', 'cat_mooc', 'rut_mooc', 'doi_rong')),
  gia numeric not null check (gia >= 0),
  ghi_chu text,
  cap_nhat_luc timestamptz not null default now(),
  khoa text generated always as (nha_xe || ' · ' || khu_vuc || ' · ' || loai) stored,
  primary key (nha_xe, khu_vuc, loai)
);
alter table public.bang_gia_xe enable row level security;
create policy "nhan vien doc" on public.bang_gia_xe for select to authenticated using ((select private.vai_tro_hien_tai()) is not null);
create policy "quan ly them" on public.bang_gia_xe for insert to authenticated with check ((select private.vai_tro_hien_tai()) = 'Quản lý');
create policy "quan ly sua" on public.bang_gia_xe for update to authenticated using ((select private.vai_tro_hien_tai()) = 'Quản lý') with check ((select private.vai_tro_hien_tai()) = 'Quản lý');
create policy "quan ly xoa" on public.bang_gia_xe for delete to authenticated using ((select private.vai_tro_hien_tai()) = 'Quản lý');

-- ===== 4. LÔ: CLS ePort, CLS dùng để lập kế hoạch (mail → ePort → tay), đóng trong ngày =====
alter table public.lo
  add column closing_eport timestamptz,
  add column eport_tau text,
  add column eport_chuyen text,
  add column eport_ghi_chu text,
  add column eport_luc timestamptz,
  add column dong_trong_ngay boolean not null default false,
  add column cls timestamptz generated always as (coalesce(closing_mail, closing_eport, closing)) stored;
comment on column public.lo.cls is 'CLS máy dùng để lập kế hoạch: ưu tiên CLS mail, rồi CLS ePort, cuối cùng CLS nhập tay';

drop view public.lo_tong_hop;
create view public.lo_tong_hop with (security_invoker = true) as
select l.*,
  count(c.id) as so_cont,
  count(c.id) filter (where c.trang_thai in ('1','2','3','4','5')) as so_cont_dang_chay
from public.lo l
left join public.cont c on c.lo = l.lo
group by l.lo;

-- ===== 5. GHI NHẬN SAO LƯU + DỌN DỮ LIỆU CŨ =====
create table public.sao_luu_nhat_ky (
  id bigint generated always as identity primary key,
  ten text not null,
  url text,
  so_dong jsonb,
  luc timestamptz not null default now()
);
alter table public.sao_luu_nhat_ky enable row level security;
create policy "nhan vien doc" on public.sao_luu_nhat_ky for select to authenticated using ((select private.vai_tro_hien_tai()) is not null);

create or replace function public.ghi_nhan_sao_luu(p_ma text, p_ten text, p_url text, p_so_dong jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_ma is null or encode(extensions.digest(p_ma, 'sha256'), 'hex')
       is distinct from (select b.bam from private.bi_mat b where b.ten = 'sao_luu') then
    raise exception 'Sai mã sao lưu' using errcode = '42501';
  end if;
  insert into public.sao_luu_nhat_ky (ten, url, so_dong) values (p_ten, p_url, p_so_dong);
end; $$;
revoke execute on function public.ghi_nhan_sao_luu(text, text, text, jsonb) from public;
grant execute on function public.ghi_nhan_sao_luu(text, text, text, jsonb) to anon, authenticated;

create table public.lo_da_don (
  lo text primary key,
  booking text,
  ten_tau text,
  etd date,
  so_cont int,
  ban_sao_luu text,
  don_luc timestamptz not null default now(),
  don_boi text
);
alter table public.lo_da_don enable row level security;
create policy "nhan vien doc" on public.lo_da_don for select to authenticated using ((select private.vai_tro_hien_tai()) is not null);

-- Lô có thể dọn: mọi cont đã lên tàu / hủy, ETD quá N ngày (mặc định 90), và đã có bản sao lưu sau lần sửa cuối
insert into public.cau_hinh (tham_so, gia_tri, giai_thich) values
  ('Số ngày sau ETD được dọn dữ liệu', '90', 'Lô đã lên tàu hết, ETD quá bấy nhiêu ngày và đã sao lưu thì được gợi ý xoá khỏi Supabase')
on conflict (tham_so) do nothing;

create or replace function public.lo_co_the_don()
returns table (lo text, booking text, ten_tau text, etd date, so_cont bigint, sua_cuoi timestamptz, ban_sao_luu text, sao_luu_luc timestamptz)
language sql stable security invoker set search_path = '' as $$
  with ng as (select coalesce((select gia_tri::int from public.cau_hinh where tham_so = 'Số ngày sau ETD được dọn dữ liệu'), 90) as n),
  x as (
    select l.lo, l.booking, l.ten_tau, coalesce(l.etd, l.etd_kho) as etd, count(c.id) as so_cont,
      greatest(l.cap_nhat_luc, max(c.cap_nhat_luc)) as sua_cuoi
    from public.lo l left join public.cont c on c.lo = l.lo
    group by l.lo
    having coalesce(bool_and(c.trang_thai in ('6', '9')), true)
  )
  select x.lo, x.booking, x.ten_tau, x.etd, x.so_cont, x.sua_cuoi, s.ten, s.luc
  from x
  cross join ng
  cross join lateral (select sl.ten, sl.luc from public.sao_luu_nhat_ky sl where sl.luc > x.sua_cuoi order by sl.luc desc limit 1) s
  where x.etd is not null and x.etd < (now() at time zone 'Asia/Ho_Chi_Minh')::date - ng.n
  order by x.etd, x.lo
$$;
revoke execute on function public.lo_co_the_don() from public, anon;
grant execute on function public.lo_co_the_don() to authenticated;

-- Nhật ký: bỏ cột tính tự động, và cho phép tắt ghi khi dọn dữ liệu hàng loạt (đã có bản sao lưu + bảng lo_da_don)
create or replace function private.ghi_nhat_ky()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := tg_argv[0];
  v_old jsonb; v_new jsonb; v_diff jsonb;
  v_who text := coalesce(auth.jwt() ->> 'email', 'hệ thống');
begin
  if current_setting('dieu_do.bo_qua_nhat_ky', true) = 'on' then
    return coalesce(new, old);
  end if;
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new);
    insert into public.nhat_ky (bang, khoa, hanh_dong, thay_doi, nguoi)
    values (tg_table_name, v_new ->> v_key, 'them', jsonb_strip_nulls(v_new), v_who);
    return new;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new);
    select jsonb_object_agg(e.key, jsonb_build_array(v_old -> e.key, e.value)) into v_diff
    from jsonb_each(v_new) e
    where e.value is distinct from (v_old -> e.key)
      and e.key not in ('cap_nhat_luc', 'nguoi_cap_nhat', 'duyet_luc', 'duyet_boi', 'cls', 'tong_tien', 'khoa', 'eport_luc');
    if v_diff is not null then
      insert into public.nhat_ky (bang, khoa, hanh_dong, thay_doi, nguoi)
      values (tg_table_name, coalesce(v_new ->> v_key, v_old ->> v_key), 'sua', v_diff, v_who);
    end if;
    return new;
  else
    v_old := to_jsonb(old);
    insert into public.nhat_ky (bang, khoa, hanh_dong, thay_doi, nguoi)
    values (tg_table_name, v_old ->> v_key, 'xoa', jsonb_strip_nulls(v_old), v_who);
    return old;
  end if;
end;
$$;
revoke execute on function private.ghi_nhat_ky() from public, anon, authenticated;

create trigger nk_chi_phi_cont after insert or update or delete on public.chi_phi_cont for each row execute function private.ghi_nhat_ky('id');
create trigger nk_bang_gia_xe after insert or update or delete on public.bang_gia_xe for each row execute function private.ghi_nhat_ky('khoa');

create or replace function public.don_du_lieu(p_ds text[])
returns integer language plpgsql security invoker set search_path = '' as $$
declare r record; v_n int := 0;
begin
  if coalesce(private.vai_tro_hien_tai(), '') <> 'Quản lý' then
    raise exception 'Chỉ Quản lý mới được dọn dữ liệu';
  end if;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'on', true);
  for r in select * from public.lo_co_the_don() d where d.lo = any(p_ds) loop
    insert into public.lo_da_don (lo, booking, ten_tau, etd, so_cont, ban_sao_luu, don_boi)
    values (r.lo, r.booking, r.ten_tau, r.etd, r.so_cont, r.ban_sao_luu, auth.jwt() ->> 'email')
    on conflict (lo) do update set don_luc = now(), ban_sao_luu = excluded.ban_sao_luu, so_cont = excluded.so_cont;
    delete from public.goi_y g where g.id_cont_rong in (select c.id from public.cont c where c.lo = r.lo)
                                 or g.id_cont_day in (select c.id from public.cont c where c.lo = r.lo);
    delete from public.cont where lo = r.lo;
    delete from public.lo where lo = r.lo;
    v_n := v_n + 1;
  end loop;
  perform set_config('dieu_do.bo_qua_nhat_ky', 'off', true);
  insert into public.nhat_ky (bang, khoa, hanh_dong, thay_doi, nguoi)
  values ('lo', 'dọn dữ liệu', 'xoa', jsonb_build_object('so_lo', v_n, 'danh_sach', to_jsonb(p_ds)), coalesce(auth.jwt() ->> 'email', 'hệ thống'));
  return v_n;
end; $$;
revoke execute on function public.don_du_lieu(text[]) from public, anon;
grant execute on function public.don_du_lieu(text[]) to authenticated;
