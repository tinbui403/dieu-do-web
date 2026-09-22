-- =====================================================================
-- Chuyển lịch chạy gợi ý mỗi giờ (phút :05) sang tao_goi_y_v3()
-- =====================================================================
SELECT cron.alter_job(
  (SELECT jobid FROM cron.job WHERE jobname = 'goi-y-ke-hoach-moi-gio'),
  command => 'select public.tao_goi_y_v3();'
);
