-- =====================================================================
-- AL-MAHATTA | ملف 08: وسائل الدفع (تُدار من موقع الإدارة)
-- شغّله مرة واحدة بعد الملفات السابقة.
-- =====================================================================
create table if not exists public.payment_methods (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  account_no text not null,
  holder     text,
  note       text,
  sort       int  not null default 0,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.payment_methods enable row level security;

drop policy if exists paymethods_read on public.payment_methods;
create policy paymethods_read on public.payment_methods for select to authenticated
  using (active or public.is_admin());

-- أرقام الحسابات يعدّلها المدير العام فقط
drop policy if exists paymethods_super on public.payment_methods;
create policy paymethods_super on public.payment_methods for all to authenticated
  using (public.is_super()) with check (public.is_super());
