-- ===== DANH MỤC =====
create table public.trang_thai (
  ma text primary key,
  ten_vi text not null,
  ten_zh text,
  thu_tu int not null,
  y_nghia text
);

create table public.khach_hang (
  ten text primary key,
  ma text,
  ten_tq text,
  ten_vn text,
  ghi_chu text
);

create table public.kho (
  ten text primary key,
  khu_vuc text,
  khach_hang_chinh text,
  ten_tq text,
  nguoi_lien_he text,
  sdt text,
  toa_do text,
  google_map text,
  dia_chi text,
  nhom_wechat text,
  ghi_chu text
);

create table public.nha_xe (
  ma text primary key,
  ten_day_du text,
  nguoi_dieu_phoi text,
  sdt_zalo text,
  ghi_chu text
);

create table public.bai_tam (
  ma text primary key,
  ten text,
  dien_moi_gio numeric,
  nang_ha numeric,
  trucking numeric,
  ghi_chu text
);

create table public.cang_den (
  ma text primary key,
  ten_vn text,
  ten_tq text
);

create table public.cang_ha (
  ten text primary key,
  ghi_chu text
);

create table public.hang_tau (
  ma text primary key,
  ghi_chu text
);

create table public.nhan_vien (
  email text primary key check (email = lower(email)),
  ho_ten text,
  vai_tro text not null default 'Điều độ' check (vai_tro in ('Quản lý', 'Điều độ', 'CSKH', 'Nhà xe', 'Chỉ xem')),
  ngon_ngu text not null default 'vi' check (ngon_ngu in ('vi', 'zh', 'both')),
  nha_xe text references public.nha_xe(ma) on update cascade,
  hoat_dong boolean not null default true,
  ghi_chu text
);

create table public.cau_hinh (
  tham_so text primary key,
  gia_tri text,
  giai_thich text
);

-- ===== LÔ (mỗi bill 1 dòng) =====
create table public.lo (
  lo text primary key,
  booking text,
  hang_tau text references public.hang_tau(ma) on update cascade,
  ten_tau text,
  cang_den text references public.cang_den(ma) on update cascade,
  etd_kho date,
  etd date,
  eta date,
  closing timestamptz,
  closing_mail timestamptz,
  cang_ha text references public.cang_ha(ten) on update cascade,
  da_kiem_dich boolean not null default false,
  da_khai_eport boolean not null default false,
  thanh_ly boolean not null default false,
  cho_keo_ha_cang boolean not null default false,
  ma_don_kdtv text,
  so_to_khai text,
  cskh text,
  ghi_chu text,
  cap_nhat_luc timestamptz not null default now(),
  nguoi_cap_nhat text
);

-- ===== CONT (mỗi cont 1 dòng) =====
create table public.cont (
  id text primary key default ('C' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYMMDDHH24MISS') || '-' || substr(md5(random()::text), 1, 4)),
  lo text references public.lo(lo) on update cascade,
  ma_don text,
  khach_hang text references public.khach_hang(ten) on update cascade,
  kho text references public.kho(ten) on update cascade,
  so_cont text,
  so_seal text,
  trang_thai text not null default '1' references public.trang_thai(ma),
  ngay_goi_cont date,
  ngay_can_len_kho timestamptz,
  gio_len_kho_ghi_chu text,
  ngay_den_kho date,
  du_kien_day timestamptz,
  can_tem boolean not null default false,
  cont_kiem_dich boolean not null default false,
  nha_xe text references public.nha_xe(ma) on update cascade,
  so_xe text,
  bai_tam text references public.bai_tam(ma) on update cascade,
  gio_vao_bai timestamptz,
  gio_ra_bai timestamptz,
  gia_bao numeric,
  phu_phi_xe numeric,
  tong_tien numeric generated always as (
    case when gia_bao is null and phu_phi_xe is null then null
         else coalesce(gia_bao, 0) + coalesce(phu_phi_xe, 0) end
  ) stored,
  phi_phat_sinh numeric,
  ghi_chu text,
  cskh text,
  kho_goc text,
  hien_trang_goc text,
  nguon text,
  cap_nhat_luc timestamptz not null default now(),
  nguoi_cap_nhat text
);

create index cont_trang_thai_idx on public.cont (trang_thai);
create index cont_lo_idx on public.cont (lo);
create index cont_kho_idx on public.cont (kho);
create index cont_so_cont_idx on public.cont (upper(so_cont));

-- ===== GỢI Ý KẾ HOẠCH =====
create table public.goi_y (
  id text primary key,
  ngay_kh date not null,
  uu_tien int not null default 3,
  loai_lenh text not null,
  booking_lay_rong text,
  hang_tau text,
  kho_cat_rong text,
  id_cont_rong text references public.cont(id) on update cascade on delete set null,
  ma_don_rong text,
  cont_day text,
  id_cont_day text references public.cont(id) on update cascade on delete set null,
  kho_day text,
  du_kien_day timestamptz,
  noi_ha text,
  closing timestamptz,
  con_lai_gio numeric,
  nha_xe_goi_y text,
  ly_do text,
  noi_dung_lenh text,
  duyet boolean not null default false,
  nha_xe_chon text references public.nha_xe(ma) on update cascade,
  da_ap_dung boolean not null default false,
  tao_luc timestamptz not null default now(),
  duyet_boi text,
  duyet_luc timestamptz
);
create index goi_y_ngay_idx on public.goi_y (ngay_kh);
create index goi_y_cont_rong_idx on public.goi_y (id_cont_rong);
create index goi_y_cont_day_idx on public.goi_y (id_cont_day);
create index cont_nha_xe_idx on public.cont (nha_xe);
create index cont_bai_tam_idx on public.cont (bai_tam);
create index cont_khach_hang_idx on public.cont (khach_hang);
create index lo_hang_tau_idx on public.lo (hang_tau);
create index lo_cang_den_idx on public.lo (cang_den);
create index lo_cang_ha_idx on public.lo (cang_ha);
create index nhan_vien_nha_xe_idx on public.nhan_vien (nha_xe);
create index goi_y_nha_xe_chon_idx on public.goi_y (nha_xe_chon);

-- ===== TỰ GHI NGƯỜI/GIỜ CẬP NHẬT =====
create or replace function public.dat_nguoi_cap_nhat()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.cap_nhat_luc := now();
  new.nguoi_cap_nhat := coalesce(auth.jwt() ->> 'email', new.nguoi_cap_nhat);
  return new;
end;
$$;

create trigger cont_cap_nhat before insert or update on public.cont
  for each row execute function public.dat_nguoi_cap_nhat();
create trigger lo_cap_nhat before insert or update on public.lo
  for each row execute function public.dat_nguoi_cap_nhat();

create or replace function public.dat_nguoi_duyet()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.duyet and not coalesce(old.duyet, false) then
    new.duyet_luc := now();
    new.duyet_boi := auth.jwt() ->> 'email';
  elsif not new.duyet then
    new.duyet_luc := null;
    new.duyet_boi := null;
  end if;
  return new;
end;
$$;
create trigger goi_y_duyet before update on public.goi_y
  for each row execute function public.dat_nguoi_duyet();

-- ===== QUYỀN: chỉ email có trong bảng nhan_vien mới đọc/ghi =====
create or replace function public.vai_tro_hien_tai()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select nv.vai_tro from public.nhan_vien nv
  where nv.email = lower(coalesce(auth.jwt() ->> 'email', '')) and nv.hoat_dong
$$;
revoke execute on function public.vai_tro_hien_tai() from public, anon;
grant execute on function public.vai_tro_hien_tai() to authenticated;

do $$
declare t text;
begin
  foreach t in array array['trang_thai','khach_hang','kho','nha_xe','bai_tam','cang_den','cang_ha','hang_tau','lo','cont','goi_y'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "nhan vien doc" on public.%I for select to authenticated using ((select public.vai_tro_hien_tai()) is not null)', t);
    execute format('create policy "nhan vien them" on public.%I for insert to authenticated with check ((select public.vai_tro_hien_tai()) in (''Quản lý'',''Điều độ'',''CSKH''))', t);
    execute format('create policy "nhan vien sua" on public.%I for update to authenticated using ((select public.vai_tro_hien_tai()) in (''Quản lý'',''Điều độ'',''CSKH'')) with check ((select public.vai_tro_hien_tai()) in (''Quản lý'',''Điều độ'',''CSKH''))', t);
    execute format('create policy "quan ly xoa" on public.%I for delete to authenticated using ((select public.vai_tro_hien_tai()) = ''Quản lý'')', t);
  end loop;
  foreach t in array array['nhan_vien','cau_hinh'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "nhan vien doc" on public.%I for select to authenticated using ((select public.vai_tro_hien_tai()) is not null)', t);
    execute format('create policy "quan ly them" on public.%I for insert to authenticated with check ((select public.vai_tro_hien_tai()) = ''Quản lý'')', t);
    execute format('create policy "quan ly sua" on public.%I for update to authenticated using ((select public.vai_tro_hien_tai()) = ''Quản lý'') with check ((select public.vai_tro_hien_tai()) = ''Quản lý'')', t);
    execute format('create policy "quan ly xoa" on public.%I for delete to authenticated using ((select public.vai_tro_hien_tai()) = ''Quản lý'')', t);
  end loop;
end $$;

-- ===== VIEW tổng hợp lô =====
create view public.lo_tong_hop with (security_invoker = true) as
select l.*,
  count(c.id) as so_cont,
  count(c.id) filter (where c.trang_thai in ('1','2','3','4','5')) as so_cont_dang_chay
from public.lo l
left join public.cont c on c.lo = l.lo
group by l.lo;

-- ===== REALTIME: nhiều người cùng thấy thay đổi ngay =====
alter publication supabase_realtime add table public.cont, public.lo, public.goi_y;
