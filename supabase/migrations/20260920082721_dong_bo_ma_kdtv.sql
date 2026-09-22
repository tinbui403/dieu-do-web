-- Apps Script đọc file PQS NEW (trang QUẢN LÝ TỔNG: cột A = lô, cột B = mã TV) và đẩy mã KDTV vào lô
create or replace function public.cap_nhat_ma_kdtv(p_ma text, p_ds jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  if p_ma is null or encode(extensions.digest(p_ma, 'sha256'), 'hex')
       is distinct from (select b.bam from private.bi_mat b where b.ten = 'sao_luu') then
    raise exception 'Sai mã' using errcode = '42501';
  end if;
  with src as (
    select distinct on (upper(trim(e ->> 'lo'))) upper(trim(e ->> 'lo')) as lo, nullif(trim(e ->> 'ma'), '') as ma
    from jsonb_array_elements(coalesce(p_ds, '[]'::jsonb)) e
    where nullif(trim(e ->> 'lo'), '') is not null
    order by upper(trim(e ->> 'lo'))
  )
  update public.lo l set ma_don_kdtv = s.ma
  from src s
  where upper(trim(l.lo)) = s.lo and s.ma is not null and l.ma_don_kdtv is distinct from s.ma;
  get diagnostics v_n = row_count;
  return v_n;
end; $$;
revoke execute on function public.cap_nhat_ma_kdtv(text, jsonb) from public;
grant execute on function public.cap_nhat_ma_kdtv(text, jsonb) to anon, authenticated;
