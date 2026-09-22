-- ============================================================
-- KIỂM THỬ QUY TRÌNH KIỂM DỊCH → KÉO → HẠ CẢNG + GỢI Ý (chạy trên Supabase thật)
-- Cách chạy: dán cả file vào SQL Editor → Run.
-- Toàn bộ là MỘT khối DO: tạo lô thử 123T…130T, kho "KHO THỬ A/B", chạy từng tình huống,
-- cuối cùng CỐ Ý báo lỗi để HUỶ TOÀN BỘ giao dịch → không để lại dữ liệu, nhật ký hay gợi ý nào.
-- Kết quả nằm trong thông báo lỗi: mỗi dòng "ĐẠT" / "HỎNG" + chi tiết.
-- Vai trò giả lập bằng request.jwt.claims (email có trong bảng nhan_vien):
--   Quản lý tinbui403@gmail.com · Điều độ tinbui402@gmail.com · CSKH tinbui404@gmail.com
-- ============================================================
do $test$
declare
  QL constant text := 'tinbui403@gmail.com';
  DD constant text := 'tinbui402@gmail.com';
  CS constant text := 'tinbui404@gmail.com';
  r record; v text; v_n int; v_bao text;
begin
  create temp table kq (stt serial, ten text, ok boolean, ct text) on commit drop;

  execute $f$create function pg_temp.vai(p_email text) returns void language sql as $$
    select set_config('request.jwt.claims',
      case when p_email is null then '' else json_build_object('sub', '00000000-0000-0000-0000-0000000000' || right(md5(p_email), 2),
        'email', p_email, 'role', 'authenticated')::text end, true) $$$f$;
  execute $f$create function pg_temp.thu(p_ten text, p_sql text, p_loi text default null) returns void language plpgsql as $$
  begin
    begin
      execute p_sql;
      if p_loi is null then insert into kq (ten, ok, ct) values (p_ten, true, 'OK');
      else insert into kq (ten, ok, ct) values (p_ten, false, 'KHÔNG báo lỗi — mong đợi lỗi: ' || p_loi); end if;
    exception when others then
      if p_loi is not null and position(lower(p_loi) in lower(sqlerrm)) > 0 then
        insert into kq (ten, ok, ct) values (p_ten, true, 'Chặn đúng: ' || sqlerrm);
      else insert into kq (ten, ok, ct) values (p_ten, false, 'Lỗi ngoài dự kiến: ' || sqlerrm); end if;
    end;
  end $$$f$;
  execute $f$create function pg_temp.kt(p_ten text, p_dung boolean, p_ct text) returns void language sql as $$
    insert into kq (ten, ok, ct) values (p_ten, coalesce(p_dung, false), coalesce(p_ct, '—')) $$$f$;

  -- ---------- Dữ liệu thử ----------
  perform pg_temp.vai(null);
  insert into public.kho (ten, khu_vuc, hoat_dong) values ('KHO THỬ A', 'KV THỬ', true), ('KHO THỬ B', 'KV THỬ', true);
  insert into public.lo (lo, booking, closing) values
    ('123T', 'BK123T', now() + interval '5 days'),
    ('124T', 'BK124T', now() - interval '51 hours'),   -- giống lô 595: quá CLS, chưa KD
    ('125T', 'BK125T', now() + interval '6 days'),     -- đơn cần 2 rỗng ở KHO THỬ A (giống lô 999)
    ('126T', 'BK126T', now() + interval '58 hours'),   -- cont KD gấp ở KHO THỬ B
    ('127T', 'BK127T', now() + interval '30 hours'),   -- lô đã KD, CLS 30h → hạ thẳng cảng
    ('128T', 'BK128T', now() + interval '4 days'),     -- lô đã KD, CLS 4 ngày → hạ bãi
    ('129T', 'BK129T', now() + interval '6 days'),     -- xoá thử
    ('130T', 'BK130T', now() + interval '6 days');     -- đơn cần 3 rỗng ở KHO THỬ B
  insert into public.cont (id, lo, so_cont, kho, trang_thai, nha_xe, cont_kiem_dich, ngay_den_kho) values
    ('TSTA0000001-123T', '123T', 'TSTA0000001', 'KHO THỬ A', '3', 'HLS', true,  current_date - 1),
    ('TSTB0000002-123T', '123T', 'TSTB0000002', 'KHO THỬ A', '3', 'HLS', false, current_date - 1),
    ('TSTC0000003-123T', '123T', 'TSTC0000003', 'KHO THỬ A', '3', 'HLS', false, current_date - 1),
    ('TSTD0000004-123T', '123T', 'TSTD0000004', 'KHO THỬ A', '3', 'HLS', false, current_date - 1),
    ('TSTE0000005-124T', '124T', 'TSTE0000005', 'KHO THỬ A', '3', 'VTL', false, current_date - 11),
    ('TSTE0000006-124T', '124T', 'TSTE0000006', 'KHO THỬ A', '3', 'HLS', false, current_date - 11),
    ('TSTE0000007-126T', '126T', 'TSTE0000007', 'KHO THỬ B', '3', 'HLS', true,  current_date - 5),
    ('TSTE0000008-127T', '127T', 'TSTE0000008', 'KHO THỬ B', '3', 'VTL', false, current_date - 3),
    ('TSTE0000009-128T', '128T', 'TSTE0000009', 'KHO THỬ B', '3', 'HLS', false, current_date - 3),
    ('TSTE0000010-129T', '129T', 'TSTE0000010', 'KHO THỬ A', '3', 'HLS', false, current_date - 1);
  insert into public.cont (id, lo, so_cont, kho, trang_thai, nha_xe, cont_kiem_dich, bai_tam, gio_vao_bai) values
    ('TSTK0000011-124T', '124T', 'TSTK0000011', 'KHO THỬ A', '4', 'HLS', true, 'HLS', now() - interval '1 day'),
    ('TSTK0000012-127T', '127T', 'TSTK0000012', 'KHO THỬ A', '4', 'VTL', true, 'PD', now() - interval '1 day'),
    ('TSTK0000013-128T', '128T', 'TSTK0000013', 'KHO THỬ A', '4', 'HLS', true, 'HT', now() - interval '1 day');
  insert into public.cont (id, lo, ma_don, kho, trang_thai, ngay_can_len_kho) values
    ('D125T-1', '125T', 'D125T-1', 'KHO THỬ A', '1', now() + interval '10 hours'),
    ('D125T-2', '125T', 'D125T-2', 'KHO THỬ A', '1', now() + interval '11 hours'),
    ('D130T-1', '130T', 'D130T-1', 'KHO THỬ B', '1', now() + interval '10 hours'),
    ('D130T-2', '130T', 'D130T-2', 'KHO THỬ B', '1', now() + interval '11 hours'),
    ('D130T-3', '130T', 'D130T-3', 'KHO THỬ B', '1', now() + interval '12 hours');
  update public.lo set ma_don_kdtv = 'TV-THU-127' where lo = '127T';
  update public.lo set ma_don_kdtv = 'TV-THU-128' where lo = '128T';
  update public.lo set da_kiem_dich = true where lo in ('127T', '128T');

  -- ---------- 1. Tích "Lô đã kiểm dịch" ----------
  perform pg_temp.vai(CS);
  perform pg_temp.thu('01 CSKH tích lô đã KD → bị chặn', $$update public.lo set da_kiem_dich = true where lo = '123T'$$, 'Chỉ Điều độ hoặc Quản lý');
  perform pg_temp.vai(DD);
  perform pg_temp.thu('02 Cont KD còn ở kho → không tích KD được', $$update public.lo set da_kiem_dich = true where lo = '123T'$$, 'phải về bãi');
  perform pg_temp.thu('03 Về bãi mà không chọn bãi → bị chặn', $$update public.cont set trang_thai = '4' where id = 'TSTB0000002-123T'$$, 'phải chọn bãi');
  perform pg_temp.thu('04 B về bãi HLS', $$update public.cont set trang_thai = '4', bai_tam = 'HLS' where id = 'TSTB0000002-123T'$$);
  perform pg_temp.thu('05 B hạ cảng khi A chưa KD → bị chặn', $$update public.cont set trang_thai = '5' where id = 'TSTB0000002-123T'$$, 'chưa kiểm dịch');
  perform pg_temp.thu('06 Đánh dấu cont KD thứ 2 trong lô → bị chặn', $$update public.cont set cont_kiem_dich = true where id = 'TSTB0000002-123T'$$, 'đã có cont kiểm dịch');
  perform pg_temp.thu('07 A về bãi DCL', $$update public.cont set trang_thai = '4', bai_tam = 'DCL' where id = 'TSTA0000001-123T'$$);
  perform pg_temp.thu('08 A ở DCL → không tích KD được', $$update public.lo set da_kiem_dich = true where lo = '123T'$$, 'chỉ kiểm dịch ở bãi HLS, PD, HT');
  perform pg_temp.thu('09 Chuyển A sang bãi HLS', $$update public.cont set bai_tam = 'HLS' where id = 'TSTA0000001-123T'$$);
  perform pg_temp.thu('10 Chưa có mã KDTV → không tích KD được', $$update public.lo set da_kiem_dich = true where lo = '123T'$$, 'chưa có Mã KDTV');
  perform pg_temp.thu('11 Có mã KDTV + A ở HLS → Điều độ tích KD được', $$update public.lo set ma_don_kdtv = 'TV-THU-123', da_kiem_dich = true where lo = '123T'$$);
  perform pg_temp.kt('12 "Cho kéo hạ cảng" tự bật theo KD', (select cho_keo_ha_cang from public.lo where lo = '123T'), 'cho_keo_ha_cang = ' || (select cho_keo_ha_cang::text from public.lo where lo = '123T'));

  -- ---------- 2. Hạ cảng khi lô đã KD ----------
  perform pg_temp.thu('13 C ở kho, CLS còn 5 ngày → không hạ thẳng cảng', $$update public.cont set trang_thai = '5' where id = 'TSTC0000003-123T'$$, 'phải hạ bãi');
  update public.lo set closing = now() + interval '30 hours' where lo = '123T';
  perform pg_temp.thu('14 C ở kho, CLS còn 30h → hạ thẳng cảng được', $$update public.cont set trang_thai = '5' where id = 'TSTC0000003-123T'$$);
  perform pg_temp.thu('15 B từ bãi hạ cảng (lô đã KD)', $$update public.cont set trang_thai = '5', gio_ra_bai = now() where id = 'TSTB0000002-123T'$$);
  perform pg_temp.thu('16 Bỏ tích KD khi đã có cont ở cảng → bị chặn', $$update public.lo set da_kiem_dich = false where lo = '123T'$$, 'không bỏ tích kiểm dịch được');

  -- ---------- 3. Lùi trạng thái ----------
  perform pg_temp.vai(CS);
  perform pg_temp.thu('17 CSKH lùi C cảng → bãi → bị chặn', $$update public.cont set trang_thai = '4', bai_tam = 'HLS' where id = 'TSTC0000003-123T'$$, 'Chỉ Quản lý hoặc Điều độ được lùi');
  perform pg_temp.vai(DD);
  perform pg_temp.thu('18 Điều độ lùi C cảng → bãi', $$update public.cont set trang_thai = '4', bai_tam = 'HLS' where id = 'TSTC0000003-123T'$$);
  perform pg_temp.thu('19 Điều độ lùi B cảng → bãi', $$update public.cont set trang_thai = '4' where id = 'TSTB0000002-123T'$$);
  perform pg_temp.thu('20 Hết cont ở cảng → Điều độ bỏ tích KD được', $$update public.lo set da_kiem_dich = false where lo = '123T'$$);
  perform pg_temp.kt('21 "Cho kéo hạ cảng" tự tắt', not (select cho_keo_ha_cang from public.lo where lo = '123T'), 'cho_keo_ha_cang = ' || (select cho_keo_ha_cang::text from public.lo where lo = '123T'));

  -- ---------- 4. Cont KD bị hủy / đổi ----------
  perform pg_temp.thu('22 Tích KD lại', $$update public.lo set da_kiem_dich = true where lo = '123T'$$);
  perform pg_temp.thu('23 Cont KD A bị Hủy (9)', $$update public.cont set trang_thai = '9' where id = 'TSTA0000001-123T'$$);
  perform pg_temp.kt('24 → lô tự về chưa KD, A bỏ dấu KD',
    not (select da_kiem_dich from public.lo where lo = '123T') and not (select cont_kiem_dich from public.cont where id = 'TSTA0000001-123T'),
    'lô KD = ' || (select da_kiem_dich::text from public.lo where lo = '123T') || ', A KD = ' || (select cont_kiem_dich::text from public.cont where id = 'TSTA0000001-123T'));
  perform pg_temp.thu('25 Lô chưa có cont KD → không tích KD được', $$update public.lo set da_kiem_dich = true where lo = '123T'$$, 'chưa chọn cont kiểm dịch');
  perform pg_temp.thu('26 Lô chưa có cont KD → không hạ cảng được', $$update public.cont set trang_thai = '5' where id = 'TSTC0000003-123T'$$, 'chưa kiểm dịch');
  perform pg_temp.thu('27 D về bãi PD + đánh dấu D là cont KD', $$update public.cont set trang_thai = '4', bai_tam = 'PD', cont_kiem_dich = true where id = 'TSTD0000004-123T'$$);
  perform pg_temp.thu('28 D ở PD → tích KD được', $$update public.lo set da_kiem_dich = true where lo = '123T'$$);
  perform pg_temp.thu('29 Bỏ dấu KD của D (đổi cont KD)', $$update public.cont set cont_kiem_dich = false where id = 'TSTD0000004-123T'$$);
  perform pg_temp.kt('30 → lô tự về chưa KD', not (select da_kiem_dich from public.lo where lo = '123T'), 'lô KD = ' || (select da_kiem_dich::text from public.lo where lo = '123T'));
  perform pg_temp.thu('31 Lô mới tạo sẵn "đã KD" → bị chặn', $$insert into public.lo (lo, da_kiem_dich) values ('131T', true)$$, 'Lô mới chưa có cont kiểm dịch');
  perform pg_temp.thu('32 Lô 124T chưa KD: cont KD lên tàu → bị chặn', $$update public.cont set trang_thai = '6' where id = 'TSTK0000011-124T'$$, 'chưa kiểm dịch');

  -- ---------- 5. Xoá thử (Quản lý) ----------
  perform pg_temp.vai(QL);
  update public.cau_hinh set gia_tri = 'Tắt' where tham_so = 'Chế độ thử: cho xoá dữ liệu đã chạy';
  perform pg_temp.thu('33 Chế độ thử TẮT: xoá lô đã chạy → bị chặn', $$select public.xoa_lo('129T')$$, 'không xoá được');
  update public.cau_hinh set gia_tri = 'Bật' where tham_so = 'Chế độ thử: cho xoá dữ liệu đã chạy';
  perform pg_temp.thu('34 Chế độ thử BẬT: Quản lý xoá lô đã chạy', $$select public.xoa_lo('129T')$$);
  perform pg_temp.vai(DD);
  perform pg_temp.thu('35 Điều độ xoá cont → bị chặn', $$select public.xoa_cont('TSTB0000002-123T')$$, 'Chỉ Quản lý');

  -- ---------- 6. Gợi ý kế hoạch ----------
  perform pg_temp.vai(null);
  perform public.tao_goi_y();
  -- 6a. Tình huống lô 595 / YUEJIA: 2 rỗng lên KHO THỬ A phải kéo 2 cont QUÁ CLS cùng kho
  select string_agg(g.id_cont_day || '←' || g.id_cont_rong || ' [' || g.muc_uu_tien || ' | ' || g.noi_ha || ']', '; ' order by g.id_cont_rong) into v
    from public.goi_y g where g.id_cont_rong like 'D125T-%';
  perform pg_temp.kt('36 Rỗng lô 125T ghép đúng 2 cont quá CLS cùng kho (124T)',
    (select count(*) from public.goi_y g where g.id_cont_rong like 'D125T-%' and g.id_cont_day like '%-124T' and g.loai_lenh like 'Đổi rỗng%') = 2, v);
  perform pg_temp.kt('37 Cont quá CLS gắn mức "Quá CLS", nơi hạ bãi tạm (lô chưa KD)',
    (select bool_and(g.muc_uu_tien = 'Quá CLS' and g.noi_ha like 'Seal tạm%') from public.goi_y g where g.id_cont_day like '%-124T'), v);
  perform pg_temp.kt('38 Không còn Rút mooc cho 2 cont 124T',
    not exists (select 1 from public.goi_y g where g.id_cont_day like '%-124T' and g.loai_lenh like 'Rút%'),
    (select string_agg(id_cont_day || ':' || loai_lenh, '; ') from public.goi_y where id_cont_day like '%-124T'));
  -- 6b. KHO THỬ B: 3 rỗng ghép theo mức gấp; nơi hạ theo kiểm dịch + 48h
  select string_agg(g.id_cont_day || '←' || g.id_cont_rong || ' [' || g.muc_uu_tien || ' | ' || g.noi_ha || ']', '; ' order by g.id_cont_rong) into v
    from public.goi_y g where g.id_cont_rong like 'D130T-%';
  perform pg_temp.kt('39 Cont KD gấp lô 126T (chưa KD) → về bãi HLS/PD/HT, không hạ cảng',
    exists (select 1 from public.goi_y g where g.id_cont_day = 'TSTE0000007-126T' and g.muc_uu_tien = 'KD gấp' and g.noi_ha ~ '^Seal tạm (HLS|PD|HT) '), v);
  perform pg_temp.kt('40 Lô 127T đã KD, CLS 30h → Seal chính hạ cảng',
    exists (select 1 from public.goi_y g where g.id_cont_day = 'TSTE0000008-127T' and g.noi_ha like 'Seal chính%'), v);
  perform pg_temp.kt('41 Lô 128T đã KD, CLS 4 ngày → hạ bãi (không hạ thẳng cảng)',
    exists (select 1 from public.goi_y g where g.id_cont_day = 'TSTE0000009-128T' and g.noi_ha like 'Seal tạm%' and g.ly_do like '%hạ bãi%'), v);
  perform pg_temp.kt('42 Không gợi ý nào "Seal chính hạ cảng" cho lô chưa kiểm dịch (toàn bộ dữ liệu)',
    not exists (select 1 from public.goi_y g join public.cont c on c.id = coalesce(g.id_cont_day, g.id_cont_rong) join public.lo l on l.lo = c.lo
                where not g.duyet and g.noi_ha like 'Seal chính%' and not coalesce(l.da_kiem_dich, false)),
    (select string_agg(g.id, ', ') from public.goi_y g join public.cont c on c.id = coalesce(g.id_cont_day, g.id_cont_rong) join public.lo l on l.lo = c.lo
      where not g.duyet and g.noi_ha like 'Seal chính%' and not coalesce(l.da_kiem_dich, false)));
  perform pg_temp.kt('43 Cont KD của lô chưa KD không bao giờ về DCL / cảng (toàn bộ dữ liệu)',
    not exists (select 1 from public.goi_y g join public.cont c on c.id = g.id_cont_day join public.lo l on l.lo = c.lo
                where not g.duyet and c.cont_kiem_dich and not coalesce(l.da_kiem_dich, false) and g.noi_ha !~ '^Seal tạm (HLS|PD|HT) '), null);

  -- ---------- Báo cáo + HUỶ giao dịch ----------
  select string_agg(case when ok then 'ĐẠT ' else 'HỎNG ' end || ten || ' — ' || ct, E'\n' order by stt) into v_bao from kq;
  raise exception E'KẾT QUẢ KIỂM THỬ: % / % ĐẠT (đã huỷ toàn bộ dữ liệu thử)\n%',
    (select count(*) filter (where ok) from kq), (select count(*) from kq), v_bao;
end
$test$;
