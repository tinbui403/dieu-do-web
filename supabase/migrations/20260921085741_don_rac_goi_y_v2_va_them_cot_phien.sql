-- =====================================================================
-- Dọn bản v2 sai nghiệp vụ + thêm cột phien cho goi_y
-- =====================================================================

-- 1) Gỡ bỏ toàn bộ đối tượng của bản v2
DROP TRIGGER IF EXISTS trig_cont_kd_huy_goi_y ON public.cont;
DROP FUNCTION IF EXISTS public.trig_huy_goi_y_khi_kd();
DROP FUNCTION IF EXISTS public.tao_goi_y_v2();
DROP FUNCTION IF EXISTS public.tinh_level_goi_y(timestamptz, boolean, boolean);

-- Xoá các dòng gợi ý sai định dạng do v2 tạo
DELETE FROM public.goi_y WHERE loai_lenh IN ('DOI_RONG', 'RUT_MOOC');

-- 2) Cột phien: truy vết dòng gợi ý sinh ra ở lần chạy nào
CREATE SEQUENCE IF NOT EXISTS public.goi_y_phien_seq;
ALTER TABLE public.goi_y ADD COLUMN IF NOT EXISTS phien integer;
COMMENT ON COLUMN public.goi_y.phien IS 'So phien chay tao_goi_y_v3 sinh ra dong nay (truy vet)';

CREATE INDEX IF NOT EXISTS goi_y_phien_idx ON public.goi_y (phien DESC);
