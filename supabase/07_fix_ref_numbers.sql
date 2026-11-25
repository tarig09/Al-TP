-- =====================================================================
-- AL-MAHATTA | ملف 07: إصلاح خطأ gen_random_bytes does not exist
-- يجعل توليد أرقام الحجز والتتبع لا يعتمد على pgcrypto. شغّله مرة واحدة.
-- =====================================================================
create or replace function public.gen_ref(prefix text)
returns text language sql volatile set search_path = public, pg_catalog as $$
  select prefix || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 7));
$$;
