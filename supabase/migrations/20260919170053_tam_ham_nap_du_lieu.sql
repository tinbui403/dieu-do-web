create table public._nap_tu_dien (loai text not null, so int not null, gia_tri text not null, primary key (loai, so));
alter table public._nap_tu_dien enable row level security;

create or replace function public._nap_d(x text) returns date
language sql immutable set search_path = '' as $$
  select case when x is null or x = '' then null
    else make_date(2000 + substr(x,1,2)::int, substr(x,3,2)::int, substr(x,5,2)::int) end
$$;

create or replace function public._nap_ts(x text) returns timestamptz
language sql immutable set search_path = '' as $$
  select case when x is null or x = '' then null
    else (('20' || substr(x,1,2) || '-' || substr(x,3,2) || '-' || substr(x,5,2) || ' '
          || coalesce(nullif(substr(x,7,2),''),'00') || ':' || coalesce(nullif(substr(x,9,2),''),'00') || ':00+07')::timestamptz) end
$$;

create or replace function public._nap_tu(l text, s text) returns text
language sql stable set search_path = '' as $$
  select case when s is null or s = '' then null
    else (select t.gia_tri from public._nap_tu_dien t where t.loai = l and t.so = s::int) end
$$;
