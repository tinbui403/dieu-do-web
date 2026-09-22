
-- ============================================================
-- ePort SP-ITC: cập nhật closing_eport cho lô cảng SPITC/Hiệp Phước
-- API: POST https://eport.sp-itc.com.vn/7e47d3928bbec8c5cb9d65a600139a33/c4f822fec11066d1ed15469717e6d9e1.xc
-- Response fields: ShipName, ExVoy, YARD_CLOSE (SP-ITC COT), BTR (ICD COT), ETA, ETD
-- ============================================================
-- LƯU Ý: bản thử đầu tiên, KHÔNG còn dùng. Migration 20260920144957_eport_gop_spitc.sql
-- xoá hai hàm + hai lịch chạy dưới đây và gộp SPITC vào eport_gui_yeu_cau / eport_xu_ly_ket_qua.
-- Giữ file này để thứ tự migration khớp với database.

-- Bảng lưu request id tạm thời (private schema)
CREATE TABLE IF NOT EXISTS private.spitc_req (
  req_id  bigint PRIMARY KEY,
  goi_luc timestamptz DEFAULT now()
);

-- Hàm gọi API SPITC
CREATE OR REPLACE FUNCTION cap_nhat_eport_spitc()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_from text := to_char(now() AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD') || ' 00:00:00';
  v_to   text := to_char((now() + interval '35 days') AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD') || ' 23:59:59';
  v_req_id bigint;
BEGIN
  SELECT net.http_post(
    url     := 'https://eport.sp-itc.com.vn/7e47d3928bbec8c5cb9d65a600139a33/c4f822fec11066d1ed15469717e6d9e1.xc',
    body    := json_build_object('from_date', v_from, 'to_date', v_to)::jsonb,
    headers := '{"Content-Type":"application/json"}'::jsonb
  ) INTO v_req_id;

  -- Lưu lại req_id, giữ tối đa 5 bản ghi
  INSERT INTO private.spitc_req(req_id, goi_luc)
  VALUES (v_req_id, now())
  ON CONFLICT (req_id) DO NOTHING;

  DELETE FROM private.spitc_req
  WHERE req_id NOT IN (
    SELECT req_id FROM private.spitc_req ORDER BY goi_luc DESC LIMIT 5
  );
END;
$$;

-- Hàm xử lý response và cập nhật closing_eport
CREATE OR REPLACE FUNCTION xu_ly_eport_spitc()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_req_id  bigint;
  v_body    text;
  v_tau     jsonb;
  v_item    jsonb;
  v_ship    text;
  v_voy     text;
  v_cls     timestamptz;
  v_n       int;
  v_total   int := 0;
BEGIN
  -- Lấy req_id mới nhất
  SELECT req_id INTO v_req_id
  FROM private.spitc_req
  ORDER BY goi_luc DESC LIMIT 1;

  IF v_req_id IS NULL THEN RETURN; END IF;

  -- Đọc response (chờ pg_net xử lý xong)
  SELECT content INTO v_body
  FROM net._http_response
  WHERE id = v_req_id AND status_code = 200;

  IF v_body IS NULL OR v_body = '' THEN RETURN; END IF;

  -- Parse JSON
  v_tau := v_body::jsonb;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_tau)
  LOOP
    v_ship := upper(trim(v_item->>'ShipName'));
    v_voy  := trim(v_item->>'ExVoy');
    v_cls  := NULLIF(v_item->>'YARD_CLOSE', '')::timestamptz;

    IF v_ship IS NULL OR v_cls IS NULL THEN CONTINUE; END IF;

    UPDATE lo SET
      closing_eport = v_cls,
      eport_tau     = v_ship,
      eport_chuyen  = v_voy,
      eport_ghi_chu = 'SPITC ' || to_char(now() AT TIME ZONE 'Asia/Ho_Chi_Minh', 'DD/MM HH24:MI'),
      eport_luc     = now()
    WHERE da_huy IS NOT TRUE
      AND upper(trim(cang_ha)) IN ('SPITC', 'HIỆP PHƯỚC')
      AND (
        upper(trim(eport_tau)) = v_ship
        OR upper(trim(ten_tau)) = v_ship
      )
      AND (
        eport_chuyen IS NULL
        OR trim(eport_chuyen) = ''
        OR trim(eport_chuyen) = v_voy
      );

    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_total := v_total + v_n;
  END LOOP;

  DELETE FROM private.spitc_req WHERE req_id = v_req_id;

  RAISE LOG 'xu_ly_eport_spitc: cập nhật % lô từ % tàu', v_total, jsonb_array_length(v_tau);
END;
$$;

-- Cron: gọi API lúc :25 mỗi giờ
SELECT cron.schedule('eport-spitc-goi',    '25 * * * *', $c$SELECT cap_nhat_eport_spitc();$c$);
-- Cron: xử lý response lúc :28 mỗi giờ (3 phút sau)
SELECT cron.schedule('eport-spitc-xu-ly',  '28 * * * *', $c$SELECT xu_ly_eport_spitc();$c$);

GRANT EXECUTE ON FUNCTION cap_nhat_eport_spitc() TO postgres;
GRANT EXECUTE ON FUNCTION xu_ly_eport_spitc() TO postgres;
