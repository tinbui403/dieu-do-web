create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
select cron.schedule('goi-y-ke-hoach-moi-gio', '5 * * * *', $$select public.tao_goi_y();$$);
