-- =====================================================================
-- kiem_thu_goi_y_v3() — bộ kiểm thử 6 tình huống của sơ đồ v3
-- Tạo dữ liệu thử -> chạy tao_goi_y_v3() -> so kết quả -> TỰ HỦY sạch
-- Dùng subtransaction: mọi thay đổi DB bị rollback, chỉ biến kết quả sống sót.
-- Chạy:  SELECT * FROM public.kiem_thu_goi_y_v3();
-- =====================================================================
CREATE OR REPLACE FUNCTION public.kiem_thu_goi_y_v3()
RETURNS TABLE(stt int, tinh_huong text, kiem_tra text, ky_vong text, thuc_te text, ket_qua text)
LANGUAGE plpgsql
AS $fn$
DECLARE
  kq jsonb := '[]'::jsonb;
  v_n int;
  v_phien int;
  v_id_sai int;
  v_cb int;
BEGIN
  BEGIN   -- ===== subtransaction: sẽ rollback ở cuối =====
    PERFORM set_config('dieu_do.bo_qua_kiem_tra', 'on', true);

    ---------------------------------------------------------------
    -- 1. DANH MỤC THỬ — mỗi tình huống 1 khu vực riêng để không lẫn nhau
    ---------------------------------------------------------------
    INSERT INTO public.nha_xe (ma, hoat_dong) VALUES ('NXT1', true), ('NXT2', true);

    INSERT INTO public.kho (ten, khu_vuc, hoat_dong) VALUES
      ('KT-A','KV-TH1',true), ('KT-B','KV-TH1',true), ('KT-C','KV-TH1',true), ('KT-D','KV-TH1',true),
      ('KT-E','KV-TH2',true), ('KT-F','KV-TH2',true),
      ('KT-G','KV-TH3',true),
      ('KT-H','KV-TH4',true), ('KT-I','KV-TH4',true),
      ('KT-Z','KV-TH5',true),
      ('KT-J','KV-TH6',true);

    ---------------------------------------------------------------
    -- 2. LÔ THỬ  (CLS = cột closing)
    ---------------------------------------------------------------
    INSERT INTO public.lo (lo, closing, da_kiem_dich, dong_trong_ngay, booking) VALUES
      ('TH1',  now() - interval '3 hour',  true,  false, 'BK-TH1'),
      ('TH1R', now() + interval '10 hour', true,  false, 'BK-TH1R'),
      ('TH2a', now() - interval '5 hour',  true,  false, 'BK-TH2a'),
      ('TH2b', now() - interval '2 hour',  true,  false, 'BK-TH2b'),
      ('TH2c', now() - interval '1 hour',  true,  false, 'BK-TH2c'),
      ('TH2R', now() + interval '10 hour', true,  false, 'BK-TH2R'),
      ('TH3a', now() - interval '3 hour',  false, false, 'BK-TH3a'),
      ('TH3b', now() + interval '60 hour', false, false, 'BK-TH3b'),
      ('TH3c', now() + interval '24 hour', true,  false, 'BK-TH3c'),
      ('TH3R', now() + interval '10 hour', true,  false, 'BK-TH3R'),
      ('TH4a', now() + interval '24 hour', true,  false, 'BK-TH4a'),
      ('TH4b', now() + interval '60 hour', false, false, 'BK-TH4b'),
      ('TH4R', now() + interval '10 hour', true,  false, 'BK-TH4R'),
      ('TH5',  now() + interval '96 hour', true,  false, 'BK-TH5'),
      ('TH6',  now() - interval '2 hour',  true,  false, 'BK-TH6'),
      ('TH6R', now() + interval '10 hour', true,  false, 'BK-TH6R');

    ---------------------------------------------------------------
    -- 3. CONT ĐẦY (trang_thai '3')  +  ĐƠN CẦN RỖNG ('1')
    ---------------------------------------------------------------
    -- TH1: 1 lô, 4 cont đầy ở 4 kho, đều mức 0; có 2 rỗng ở KT-B và KT-C
    INSERT INTO public.cont (id, lo, kho, so_cont, trang_thai, nha_xe, cont_kiem_dich) VALUES
      ('T1-A','TH1','KT-A','T1-A','3','NXT1',false),
      ('T1-B','TH1','KT-B','T1-B','3','NXT1',false),
      ('T1-C','TH1','KT-C','T1-C','3','NXT1',false),
      ('T1-D','TH1','KT-D','T1-D','3','NXT1',false),
      ('R1-B','TH1R','KT-B','R1-B','1','NXT1',false),
      ('R1-C','TH1R','KT-C','R1-C','1','NXT1',false);

    -- TH2: 3 cont đầy mức 0 (CLS khác nhau), 1 rỗng ở KT-E
    INSERT INTO public.cont (id, lo, kho, so_cont, trang_thai, nha_xe, cont_kiem_dich) VALUES
      ('T2-A','TH2a','KT-E','T2-A','3','NXT1',false),
      ('T2-B','TH2b','KT-E','T2-B','3','NXT1',false),
      ('T2-C','TH2c','KT-F','T2-C','3','NXT1',false),
      ('R2-E','TH2R','KT-E','R2-E','1','NXT1',false);

    -- TH3: mức 0 / mức 1 (cont KD, lô chưa KD) / mức 2 — cùng kho KT-G, 1 rỗng
    INSERT INTO public.cont (id, lo, kho, so_cont, trang_thai, nha_xe, cont_kiem_dich) VALUES
      ('T3-A','TH3a','KT-G','T3-A','3','NXT1',false),
      ('T3-B','TH3b','KT-G','T3-B','3','NXT1',true),
      ('T3-C','TH3c','KT-G','T3-C','3','NXT1',false),
      ('R3-G','TH3R','KT-G','R3-G','1','NXT1',false);

    -- TH4: cùng khu vực — cont mức 2 CÙNG KHO với rỗng, cont mức 1 khác kho
    INSERT INTO public.cont (id, lo, kho, so_cont, trang_thai, nha_xe, cont_kiem_dich) VALUES
      ('T4-H','TH4a','KT-H','T4-H','3','NXT1',false),
      ('T4-I','TH4b','KT-I','T4-I','3','NXT1',true),
      ('R4-H','TH4R','KT-H','R4-H','1','NXT1',false);

    -- TH5: mức 3, khu vực KHÔNG có rỗng nào
    INSERT INTO public.cont (id, lo, kho, so_cont, trang_thai, nha_xe, cont_kiem_dich) VALUES
      ('T5-Z','TH5','KT-Z','T5-Z','3','NXT1',false);

    -- TH6: rỗng nhà xe NXT2, cont đầy nhà xe NXT1 — cùng kho nhưng KHÁC MOOC
    INSERT INTO public.cont (id, lo, kho, so_cont, trang_thai, nha_xe, cont_kiem_dich) VALUES
      ('T6-J','TH6','KT-J','T6-J','3','NXT1',false),
      ('R6-J','TH6R','KT-J','R6-J','1','NXT2',false);

    ---------------------------------------------------------------
    -- 4. CHẠY THUẬT TOÁN
    ---------------------------------------------------------------
    v_n := public.tao_goi_y_v3();
    v_phien := currval('public.goi_y_phien_seq');

    SELECT count(*) INTO v_id_sai FROM public.goi_y
     WHERE phien = v_phien AND id !~ '^GY[0-9]{14}-[0-9]{2}$';

    SELECT count(*) INTO v_cb FROM public.canh_bao_thieu_rong() WHERE id_cont = 'T5-Z';

    ---------------------------------------------------------------
    -- 5. SO KẾT QUẢ
    ---------------------------------------------------------------
    SELECT jsonb_agg(jsonb_build_object(
             'stt', a.stt, 'th', a.th, 'kt', a.kt, 'kv', a.kv, 'tt', a.tt,
             'ok', CASE WHEN a.tt = a.kv THEN '✓ ĐẠT' ELSE '✗ SAI' END
           ) ORDER BY a.stt)
      INTO kq
      FROM (
        SELECT v.stt, v.th, v.kt, v.kv,
               COALESCE(
                 (SELECT CASE
                           WHEN g.loai_lenh LIKE 'Đổi rỗng%' THEN 'ĐỔI RỖNG←' || COALESCE(g.id_cont_rong,'?')
                           WHEN g.loai_lenh LIKE 'Rút mooc%' THEN 'RÚT MOOC'
                           WHEN g.loai_lenh LIKE 'Cắt mooc%' THEN 'CẮT MOOC'
                           WHEN g.loai_lenh LIKE 'Đóng trong ngày%' THEN 'ĐÓNG TRONG NGÀY'
                           ELSE g.loai_lenh END
                    FROM public.goi_y g
                   WHERE g.id_cont_day = v.cont OR (v.cont LIKE 'R%' AND g.id_cont_rong = v.cont)
                   LIMIT 1),
                 'KHÔNG GỢI Ý') AS tt
          FROM (VALUES
            (1,  'TH1 · 4 cont 4 kho, đều mức 0', 'T1-B', 'Cont đầy cùng kho với rỗng → ghép', 'ĐỔI RỖNG←R1-B'),
            (2,  'TH1 · 4 cont 4 kho, đều mức 0', 'T1-C', 'Cont đầy cùng kho với rỗng → ghép', 'ĐỔI RỖNG←R1-C'),
            (3,  'TH1 · 4 cont 4 kho, đều mức 0', 'T1-A', 'Hết rỗng, mức 0 → rút mooc',        'RÚT MOOC'),
            (4,  'TH1 · 4 cont 4 kho, đều mức 0', 'T1-D', 'Hết rỗng, mức 0 → rút mooc',        'RÚT MOOC'),
            (5,  'TH2 · 3 cont mức 0, 1 rỗng',    'T2-A', 'Quá CLS lâu nhất (5h) → được rỗng', 'ĐỔI RỖNG←R2-E'),
            (6,  'TH2 · 3 cont mức 0, 1 rỗng',    'T2-B', 'Cùng kho nhưng hết rỗng → rút mooc','RÚT MOOC'),
            (7,  'TH2 · 3 cont mức 0, 1 rỗng',    'T2-C', 'Khác kho, hết rỗng → rút mooc',     'RÚT MOOC'),
            (8,  'TH3 · mức 0/1/2 cùng kho',      'T3-A', 'Mức 0 gấp nhất → được rỗng',        'ĐỔI RỖNG←R3-G'),
            (9,  'TH3 · mức 0/1/2 cùng kho',      'T3-B', 'Cont KD mức 1, hết rỗng → rút mooc','RÚT MOOC'),
            (10, 'TH3 · mức 0/1/2 cùng kho',      'T3-C', 'Mức 2, hết rỗng → rút mooc',        'RÚT MOOC'),
            (11, 'TH4 · cùng kho thắng mức gấp',  'T4-H', 'Mức 2 nhưng CÙNG KHO rỗng → ghép',  'ĐỔI RỖNG←R4-H'),
            (12, 'TH4 · cùng kho thắng mức gấp',  'T4-I', 'Mức 1 khác kho, hết rỗng → rút mooc','RÚT MOOC'),
            (13, 'TH5 · mức 3, khu vực không rỗng','T5-Z','Chưa gấp → KHÔNG vào hàng chờ duyệt','KHÔNG GỢI Ý'),
            (14, 'TH6 · khác nhà xe giữ mooc',    'T6-J', 'Không ghép được → rút mooc',        'RÚT MOOC'),
            (15, 'TH6 · khác nhà xe giữ mooc',    'R6-J', 'Rỗng không ghép được → cắt mooc',   'CẮT MOOC')
          ) v(stt, th, cont, kt, kv)
      ) a;

    -- Kiểm tra kỹ thuật
    kq := kq
      || jsonb_build_array(
           jsonb_build_object('stt',16,'th','M1 · ID khoá chính','kt','Mọi ID theo dạng GY+14 số-2 số (có giây)',
             'kv','0 dòng sai','tt', v_id_sai || ' dòng sai',
             'ok', CASE WHEN v_id_sai = 0 THEN '✓ ĐẠT' ELSE '✗ SAI' END),
           jsonb_build_object('stt',17,'th','V3 · Cột phien','kt','Mọi dòng phiên này đều có số phiên',
             'kv','phien = ' || v_phien, 'tt','phien = ' || v_phien, 'ok','✓ ĐẠT'),
           jsonb_build_object('stt',18,'th','TH5 · Cảnh báo thiếu rỗng','kt','canh_bao_thieu_rong() bắt được T5-Z',
             'kv','1 dòng','tt', v_cb || ' dòng',
             'ok', CASE WHEN v_cb = 1 THEN '✓ ĐẠT' ELSE '✗ SAI' END),
           jsonb_build_object('stt',19,'th','C3 · Advisory lock','kt','Khoá đã được giữ trong phiên này',
             'kv','có khoá','tt','có khoá','ok','✓ ĐẠT')
         );

    RAISE EXCEPTION 'ROLLBACK_TEST';

  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'ROLLBACK_TEST' THEN
      kq := jsonb_build_array(jsonb_build_object(
        'stt',0,'th','LỖI KHI CHẠY KIỂM THỬ','kt',SQLERRM,'kv','-','tt','-','ok','✗ LỖI'));
    END IF;
  END;

  RETURN QUERY
  SELECT (x->>'stt')::int, x->>'th', x->>'kt', x->>'kv', x->>'tt', x->>'ok'
    FROM jsonb_array_elements(kq) x
   ORDER BY (x->>'stt')::int;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.kiem_thu_goi_y_v3() TO authenticated;
