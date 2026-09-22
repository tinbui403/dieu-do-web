-- ===== NHẬT KÝ THAY ĐỔI (audit trail) =====
create table public.nhat_ky (
  id bigint generated always as identity primary key,
  bang text not null,
  khoa text not null,
  hanh_dong text not null check (hanh_dong in ('them', 'sua', 'xoa')),
  thay_doi jsonb,
  nguoi text,
  luc timestamptz not null default now()
);
create index nhat_ky_bang_khoa_idx on public.nhat_ky (bang, khoa, luc desc);
create index nhat_ky_luc_idx on public.nhat_ky (luc desc);
alter table public.nhat_ky enable row level security;
-- Nhân viên chỉ được ĐỌC; không ai sửa/xoá được nhật ký qua web (chỉ trigger ghi vào)
create policy "nhan vien doc nhat ky" on public.nhat_ky for select to authenticated
  using ((select private.vai_tro_hien_tai()) is not null);

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
      and e.key not in ('cap_nhat_luc', 'nguoi_cap_nhat', 'duyet_luc', 'duyet_boi');
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

create trigger nk_lo after insert or update or delete on public.lo for each row execute function private.ghi_nhat_ky('lo');
create trigger nk_cont after insert or update or delete on public.cont for each row execute function private.ghi_nhat_ky('id');
create trigger nk_kho after insert or update or delete on public.kho for each row execute function private.ghi_nhat_ky('ten');
create trigger nk_nha_xe after insert or update or delete on public.nha_xe for each row execute function private.ghi_nhat_ky('ma');
create trigger nk_khach_hang after insert or update or delete on public.khach_hang for each row execute function private.ghi_nhat_ky('ten');
create trigger nk_bai_tam after insert or update or delete on public.bai_tam for each row execute function private.ghi_nhat_ky('ma');
create trigger nk_hang_tau after insert or update or delete on public.hang_tau for each row execute function private.ghi_nhat_ky('ma');
create trigger nk_cang_den after insert or update or delete on public.cang_den for each row execute function private.ghi_nhat_ky('ma');
create trigger nk_cang_ha after insert or update or delete on public.cang_ha for each row execute function private.ghi_nhat_ky('ten');
create trigger nk_nhan_vien after insert or update or delete on public.nhan_vien for each row execute function private.ghi_nhat_ky('email');
create trigger nk_cau_hinh after insert or update or delete on public.cau_hinh for each row execute function private.ghi_nhat_ky('tham_so');
-- Gợi ý: chỉ ghi khi người dùng duyệt / chọn nhà xe / đánh dấu đã chạy (không ghi việc máy tạo mỗi giờ)
create trigger nk_goi_y after update on public.goi_y for each row
  when (old.duyet is distinct from new.duyet or old.nha_xe_chon is distinct from new.nha_xe_chon or old.da_ap_dung is distinct from new.da_ap_dung)
  execute function private.ghi_nhat_ky('id');

-- ===== HỦY LÔ (có lý do, khôi phục được) =====
alter table public.lo
  add column da_huy boolean not null default false,
  add column ly_do_huy text,
  add column huy_boi text,
  add column huy_luc timestamptz;
alter table public.cont add column huy_theo_lo boolean not null default false;

drop view public.lo_tong_hop;
create view public.lo_tong_hop with (security_invoker = true) as
select l.*,
  count(c.id) as so_cont,
  count(c.id) filter (where c.trang_thai in ('1','2','3','4','5')) as so_cont_dang_chay
from public.lo l
left join public.cont c on c.lo = l.lo
group by l.lo;

create or replace function public.huy_lo(p_lo text, p_ly_do text)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare v_chay int; v_n int;
begin
  if coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ') then
    raise exception 'Chỉ Quản lý hoặc Điều độ mới được hủy lô';
  end if;
  if length(trim(coalesce(p_ly_do, ''))) < 3 then
    raise exception 'Cần ghi lý do hủy lô';
  end if;
  if not exists (select 1 from public.lo where lo = p_lo) then
    raise exception 'Không tìm thấy lô %', p_lo;
  end if;
  select count(*) into v_chay from public.cont where lo = p_lo and trang_thai not in ('1', '9');
  if v_chay > 0 then
    raise exception 'Lô % còn % cont đã chạy thực tế (tới kho / bãi / cảng / lên tàu). Xử lý các cont đó trước rồi mới hủy lô.', p_lo, v_chay;
  end if;
  -- Bỏ gợi ý của các đơn thuộc lô (bỏ duyệt trước để được xoá)
  update public.goi_y set duyet = false
   where duyet and not da_ap_dung
     and (id_cont_rong in (select id from public.cont where lo = p_lo) or id_cont_day in (select id from public.cont where lo = p_lo));
  delete from public.goi_y
   where not duyet
     and (id_cont_rong in (select id from public.cont where lo = p_lo) or id_cont_day in (select id from public.cont where lo = p_lo));
  update public.cont set trang_thai = '9', huy_theo_lo = true where lo = p_lo and trang_thai = '1';
  get diagnostics v_n = row_count;
  update public.lo set da_huy = true, ly_do_huy = trim(p_ly_do), huy_boi = auth.jwt() ->> 'email', huy_luc = now() where lo = p_lo;
  return v_n;
end;
$$;
revoke execute on function public.huy_lo(text, text) from public, anon;
grant execute on function public.huy_lo(text, text) to authenticated;

create or replace function public.khoi_phuc_lo(p_lo text)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare v_n int;
begin
  if coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ') then
    raise exception 'Chỉ Quản lý hoặc Điều độ mới được khôi phục lô';
  end if;
  update public.lo set da_huy = false, ly_do_huy = null, huy_boi = null, huy_luc = null where lo = p_lo and da_huy;
  if not found then raise exception 'Lô % không ở trạng thái đã hủy', p_lo; end if;
  update public.cont set trang_thai = '1', huy_theo_lo = false where lo = p_lo and huy_theo_lo and trang_thai = '9';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke execute on function public.khoi_phuc_lo(text) from public, anon;
grant execute on function public.khoi_phuc_lo(text) to authenticated;

-- Không cho thêm đơn mới vào lô đã hủy
create or replace function private.chan_lo_da_huy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.lo is not null and new.trang_thai <> '9'
     and (tg_op = 'INSERT' or new.lo is distinct from old.lo or new.trang_thai is distinct from old.trang_thai)
     and exists (select 1 from public.lo l where l.lo = new.lo and l.da_huy) then
    raise exception 'Lô % đã hủy — khôi phục lô trước khi thêm hoặc chạy cont', new.lo;
  end if;
  return new;
end;
$$;
revoke execute on function private.chan_lo_da_huy() from public, anon, authenticated;
create trigger cont_chan_lo_da_huy before insert or update on public.cont for each row execute function private.chan_lo_da_huy();
