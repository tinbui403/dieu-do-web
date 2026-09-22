-- Cổng sao lưu: Google Apps Script gọi mỗi ngày để lưu toàn bộ dữ liệu ra Google Drive.
-- Chỉ trả dữ liệu khi đưa đúng mã bí mật (lưu dạng băm SHA-256, không lưu mã gốc).
create table if not exists private.bi_mat (
  ten text primary key,
  bam text not null,
  ghi_chu text,
  tao_luc timestamptz not null default now()
);
revoke all on private.bi_mat from public, anon, authenticated;

-- Khi cài lại: thay <SHA256_CUA_MA_SAO_LUU> bằng mã băm SHA-256 (hex) của mã bí mật đặt trong Apps Script.
insert into private.bi_mat (ten, bam, ghi_chu)
values ('sao_luu', '<SHA256_CUA_MA_SAO_LUU>', 'Mã cho Apps Script sao lưu hằng ngày ra Google Drive')
on conflict (ten) do update set bam = excluded.bam, tao_luc = now();

create or replace function public.sao_luu_du_lieu(p_ma text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_ma is null or encode(extensions.digest(p_ma, 'sha256'), 'hex')
       is distinct from (select b.bam from private.bi_mat b where b.ten = 'sao_luu') then
    raise exception 'Sai mã sao lưu' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'thoi_diem', now(),
    'lo',          coalesce((select jsonb_agg(t order by t.lo) from public.lo t), '[]'),
    'cont',        coalesce((select jsonb_agg(t order by t.id) from public.cont t), '[]'),
    'goi_y',       coalesce((select jsonb_agg(t order by t.id) from public.goi_y t), '[]'),
    'nhat_ky',     coalesce((select jsonb_agg(t order by t.id) from public.nhat_ky t), '[]'),
    'kho',         coalesce((select jsonb_agg(t order by t.ten) from public.kho t), '[]'),
    'nha_xe',      coalesce((select jsonb_agg(t order by t.ma) from public.nha_xe t), '[]'),
    'khach_hang',  coalesce((select jsonb_agg(t order by t.ten) from public.khach_hang t), '[]'),
    'bai_tam',     coalesce((select jsonb_agg(t order by t.ma) from public.bai_tam t), '[]'),
    'hang_tau',    coalesce((select jsonb_agg(t order by t.ma) from public.hang_tau t), '[]'),
    'cang_den',    coalesce((select jsonb_agg(t order by t.ma) from public.cang_den t), '[]'),
    'cang_ha',     coalesce((select jsonb_agg(t order by t.ten) from public.cang_ha t), '[]'),
    'trang_thai',  coalesce((select jsonb_agg(t order by t.thu_tu) from public.trang_thai t), '[]'),
    'nhan_vien',   coalesce((select jsonb_agg(t order by t.email) from public.nhan_vien t), '[]'),
    'cau_hinh',    coalesce((select jsonb_agg(t order by t.tham_so) from public.cau_hinh t), '[]')
  );
end;
$$;
revoke execute on function public.sao_luu_du_lieu(text) from public;
grant execute on function public.sao_luu_du_lieu(text) to anon, authenticated;
