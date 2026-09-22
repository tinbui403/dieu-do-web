-- Chuyển hàm kiểm tra quyền ra khỏi API công khai (chính sách RLS vẫn dùng được)
create schema if not exists private;
grant usage on schema private to authenticated;
alter function public.vai_tro_hien_tai() set schema private;

-- Điều độ được xoá gợi ý CHƯA duyệt (để chạy lại gợi ý)
create policy "dieu do xoa goi y chua duyet" on public.goi_y for delete to authenticated
  using ((select private.vai_tro_hien_tai()) in ('Quản lý','Điều độ') and not duyet);

-- Người dùng đọc vai trò của chính mình qua hàm công khai an toàn (chỉ trả về vai trò của chính họ)
create or replace function public.toi_la_ai()
returns table (email text, ho_ten text, vai_tro text, ngon_ngu text, nha_xe text)
language sql
stable
security invoker
set search_path = ''
as $$
  select nv.email, nv.ho_ten, nv.vai_tro, nv.ngon_ngu, nv.nha_xe
  from public.nhan_vien nv
  where nv.email = lower(coalesce(auth.jwt() ->> 'email', '')) and nv.hoat_dong
$$;
revoke execute on function public.toi_la_ai() from public, anon;
grant execute on function public.toi_la_ai() to authenticated;

-- ===== HÀM GỢI Ý KẾ HOẠCH =====
create or replace function public.tao_goi_y()
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_bai text;
  v_gio_ha numeric;
  v_khung numeric;
  v_gio_dong numeric;
  v_giu int;
  v_quen int;
  v_prefix text := 'GY' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYYMMDDHH24MI') || '-';
  v_id text;
  v_n int;
  e record;
  used_f text[] := '{}';
  used_e text[] := '{}';
begin
  if auth.uid() is not null and coalesce(private.vai_tro_hien_tai(), '') not in ('Quản lý', 'Điều độ') then
    raise exception 'Bạn không có quyền chạy gợi ý kế hoạch';
  end if;

  select
    coalesce(max(gia_tri) filter (where tham_so = 'Bãi tạm mặc định'), 'HLS'),
    coalesce(max(gia_tri) filter (where tham_so = 'Giờ trước closing hạ thẳng cảng'), '36')::numeric,
    coalesce(max(gia_tri) filter (where tham_so = 'Khung kế hoạch (giờ tới)'), '36')::numeric,
    coalesce(max(gia_tri) filter (where tham_so = 'Giờ đóng hàng ước tính'), '24')::numeric,
    coalesce(max(gia_tri) filter (where tham_so = 'Số ngày giữ gợi ý đã duyệt'), '3')::int,
    coalesce(max(gia_tri) filter (where tham_so = 'Số ngày tính nhà xe quen'), '45')::int
  into v_bai, v_gio_ha, v_khung, v_gio_dong, v_giu, v_quen
  from public.cau_hinh;

  delete from public.goi_y where not duyet;

  -- Cont đầy / sắp đầy trong khung giờ
  create temp table _day on commit drop as
  select c.id, c.so_cont, c.lo, c.kho, c.nha_xe, c.cont_kiem_dich, c.du_kien_day, k.khu_vuc,
    coalesce(c.du_kien_day, (c.ngay_den_kho::timestamp at time zone 'Asia/Ho_Chi_Minh') + make_interval(hours => v_gio_dong::int)) as du_kien,
    coalesce(l.closing, ((coalesce(l.etd, l.etd_kho) - 1)::timestamp at time zone 'Asia/Ho_Chi_Minh')) as closing,
    (l.closing is null and coalesce(l.etd, l.etd_kho) is not null) as closing_uoc,
    coalesce(l.da_kiem_dich, false) as lo_kd
  from public.cont c
  left join public.lo l on l.lo = c.lo
  left join public.kho k on k.ten = c.kho
  where c.trang_thai in ('2', '3') and c.so_cont is not null
    and (c.trang_thai = '3'
         or coalesce(c.du_kien_day, (c.ngay_den_kho::timestamp at time zone 'Asia/Ho_Chi_Minh') + make_interval(hours => v_gio_dong::int)) is null
         or coalesce(c.du_kien_day, (c.ngay_den_kho::timestamp at time zone 'Asia/Ho_Chi_Minh') + make_interval(hours => v_gio_dong::int)) <= v_now + make_interval(hours => v_khung::int))
    and not exists (select 1 from public.goi_y g where g.duyet and g.id_cont_day = c.id and g.ngay_kh >= v_today - v_giu);

  -- Đơn cần cont rỗng trong khung giờ
  create temp table _rong on commit drop as
  select c.id, c.ma_don, c.lo, c.kho, c.nha_xe, k.khu_vuc, l.booking, l.hang_tau, c.ngay_can_len_kho as can,
    coalesce(l.closing, ((coalesce(l.etd, l.etd_kho) - 1)::timestamp at time zone 'Asia/Ho_Chi_Minh')) as closing
  from public.cont c
  left join public.lo l on l.lo = c.lo
  left join public.kho k on k.ten = c.kho
  where c.trang_thai = '1'
    and (c.ngay_can_len_kho is null or c.ngay_can_len_kho <= v_now + make_interval(hours => v_khung::int))
    and not exists (select 1 from public.goi_y g where g.duyet and g.id_cont_rong = c.id and g.ngay_kh >= v_today - v_giu);

  create temp table _cap (stt serial, loai text, id_rong text, id_day text) on commit drop;

  -- 1. Đổi rỗng: cùng kho vừa cần rỗng vừa có cont đầy
  for e in select id, kho from _rong order by can nulls first, id loop
    select d.id into v_id from _day d
      where d.kho = e.kho and not (d.id = any(used_f))
      order by d.closing nulls last, d.id limit 1;
    if v_id is not null then
      insert into _cap (loai, id_rong, id_day) values ('doi', e.id, v_id);
      used_f := used_f || v_id; used_e := used_e || e.id;
    end if;
  end loop;

  -- 2. Cắt rỗng kho A + kéo đầy kho B cùng khu vực
  for e in select id, kho, khu_vuc from _rong where khu_vuc is not null and not (id = any(used_e)) order by can nulls first, id loop
    select d.id into v_id from _day d
      where d.khu_vuc = e.khu_vuc and d.kho <> e.kho and not (d.id = any(used_f))
      order by d.closing nulls last, d.id limit 1;
    if v_id is not null then
      insert into _cap (loai, id_rong, id_day) values ('catkeo', e.id, v_id);
      used_f := used_f || v_id; used_e := used_e || e.id;
    end if;
  end loop;

  -- 3. Rút mooc kéo đầy (không có rỗng đi kèm)
  insert into _cap (loai, id_rong, id_day)
  select 'rut', null, d.id from _day d where not (d.id = any(used_f)) order by d.closing nulls last, d.id;

  -- 4. Cắt rỗng (chỉ đưa rỗng tới kho)
  insert into _cap (loai, id_rong, id_day)
  select 'cat', r.id, null from _rong r where not (r.id = any(used_e)) order by r.can nulls first, r.id;

  insert into public.goi_y (id, ngay_kh, uu_tien, loai_lenh, booking_lay_rong, hang_tau, kho_cat_rong, id_cont_rong, ma_don_rong,
    cont_day, id_cont_day, kho_day, du_kien_day, noi_ha, closing, con_lai_gio, nha_xe_goi_y, ly_do, noi_dung_lenh)
  select v_prefix || lpad((row_number() over (order by x.uu_tien, x.closing nulls last, x.stt))::text, 2, '0'),
    v_today, x.uu_tien, x.loai_lenh, x.booking, x.hang_tau, x.kho_rong, x.id_rong, x.ma_don_rong,
    x.so_cont, x.id_day, x.kho_day, x.du_kien, x.noi_ha, x.closing, round(x.h_cl), x.nha_xe,
    nullif(concat_ws('; ',
      case when x.id_rong is not null and x.can is not null then 'Kho cần rỗng ' || to_char(x.can at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') end,
      case when x.id_day is not null and x.du_kien_day is null then 'Chưa nhập Dự kiến đầy - máy coi như đã/sắp đầy' end,
      case when x.closing_uoc then 'Closing ước tính = ETD - 1 ngày' end,
      case when x.kd_chua then 'Cont kiểm dịch chưa kiểm → về bãi'
           when x.id_day is not null and x.h_cl < v_gio_ha then 'Gần closing (' || round(x.h_cl) || 'h) → hạ thẳng cảng' end,
      case when x.h_cl < 0 then '⚠ ĐÃ QUÁ CLOSING' end,
      case when x.loai = 'catkeo' then 'Cùng khu vực ' || x.khu_vuc_rong end,
      case when x.id_rong is not null and x.booking is null then '⚠ Đơn chưa có booking' end
    ), ''),
    concat_ws(E'\n',
      case x.loai when 'doi' then 'LỆNH ĐỔI RỖNG 换空柜' when 'catkeo' then 'LỆNH CẮT RỖNG + KÉO ĐẦY 甩空拉满'
                  when 'rut' then 'LỆNH RÚT MOOC KÉO ĐẦY 拉满柜' else 'LỆNH CẮT RỖNG 送空柜' end,
      case when x.id_rong is not null then 'Số Booking 订舱号: ' || coalesce(x.booking, '⚠ chưa có 无') end,
      case when x.id_rong is not null then 'Cắt rỗng tại 提空点: ' || coalesce(x.kho_rong, '—') || coalesce(' (đơn ' || x.ma_don_rong || ')', '') end,
      case when x.id_day is not null then 'Cont đầy 满柜: ' || x.so_cont || coalesce(' (lô ' || x.lo_day || ')', '') end,
      case when x.id_day is not null then 'Kho đầy 装货点: ' || coalesce(x.kho_day, '—') end,
      case when x.id_day is not null then 'Nơi hạ 还柜点: ' || x.noi_ha end,
      'CUT-OFF 截关: ' || coalesce(to_char(x.closing at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM/YYYY'), '—'),
      'Nhà xe 车队: ' || coalesce(x.nha_xe, '—'))
  from (
    select y.*,
      case when y.h_ref is null then 3 when y.h_ref < 24 then 1 when y.h_ref < 48 then 2 else 3 end as uu_tien,
      case when y.id_day is null then null
           when y.kd_chua then 'Seal tạm ' || v_bai || ' 临时封条'
           when y.h_cl < v_gio_ha then 'Seal chính hạ cảng 正封还码头'
           else 'Seal tạm ' || v_bai || ' 临时封条' end as noi_ha,
      coalesce(
        (select c2.nha_xe from public.cont c2
          where c2.kho = coalesce(y.kho_day, y.kho_rong) and c2.nha_xe is not null
            and c2.ngay_goi_cont >= v_today - v_quen
          group by c2.nha_xe order by count(*) desc, c2.nha_xe limit 1),
        y.nx_day, y.nx_rong) as nha_xe
    from (
      select cap.stt, cap.loai, cap.id_rong, cap.id_day,
        case cap.loai when 'doi' then 'Đổi rỗng 换空柜' when 'catkeo' then 'Cắt rỗng + kéo đầy 甩空拉满'
                      when 'rut' then 'Rút mooc kéo đầy 拉满柜' else 'Cắt rỗng 送空柜' end as loai_lenh,
        r.booking, r.hang_tau, r.kho as kho_rong, r.ma_don as ma_don_rong, r.can, r.khu_vuc as khu_vuc_rong, r.nha_xe as nx_rong,
        d.so_cont, d.lo as lo_day, d.kho as kho_day, d.du_kien, d.du_kien_day, d.nha_xe as nx_day, d.closing_uoc,
        coalesce(d.closing, r.closing) as closing,
        extract(epoch from (coalesce(d.closing, r.closing) - v_now)) / 3600 as h_cl,
        extract(epoch from ((case when cap.loai = 'cat' then coalesce(r.can, v_now) else coalesce(d.closing, r.closing) end) - v_now)) / 3600 as h_ref,
        (d.id is not null and d.cont_kiem_dich and not d.lo_kd) as kd_chua
      from _cap cap
      left join _rong r on r.id = cap.id_rong
      left join _day d on d.id = cap.id_day
    ) y
  ) x;

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke execute on function public.tao_goi_y() from public, anon;
grant execute on function public.tao_goi_y() to authenticated;
