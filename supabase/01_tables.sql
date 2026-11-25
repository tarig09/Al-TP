-- ===== الملف 1 من 3: الجداول والدوال المساعدة =====
-- شغّله أولاً. ثم شغّل 02 ثم 03.

-- =====================================================================
-- AL-MAHATTA | المحطة — Supabase schema
-- الصقه كاملاً في: Supabase Dashboard → SQL Editor → New query → Run
-- آمن لإعادة التشغيل (idempotent) قدر الإمكان.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1) الدوال المساعدة
-- ---------------------------------------------------------------------
create or replace function public.gen_ref(prefix text)
returns text language sql volatile set search_path = public, pg_catalog as $$
  select prefix || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 7));
$$;

create or replace function public.status_ar(s text)
returns text language sql immutable as $$
  select case s
    when 'pending'        then 'قيد المراجعة'
    when 'payment_review' then 'مراجعة الدفع'
    when 'confirmed'      then 'مؤكد'
    when 'cancelled'      then 'ملغي'
    when 'received'       then 'تم الاستلام'
    when 'in_transit'     then 'في الطريق'
    when 'arrived'        then 'وصلت للوجهة'
    when 'delivered'      then 'تم التسليم'
    when 'processing'     then 'قيد التنفيذ'
    when 'completed'      then 'مكتمل'
    when 'approved'       then 'تمت الموافقة'
    when 'rejected'       then 'مرفوض'
    else s end;
$$;

-- ---------------------------------------------------------------------
-- 2) الملفات الشخصية
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  phone      text,
  city       text,
  is_admin   boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'full_name', ''),
          coalesce(new.raw_user_meta_data->>'phone', ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- 3) جداول المحتوى العام (المكاتب، الخدمات، العروض، البانرات)
-- ---------------------------------------------------------------------
create table if not exists public.offices (
  id          uuid primary key default gen_random_uuid(),
  slug        text unique not null,
  name_ar     text not null,
  icon        text not null default '🏢',
  color       text not null default '#0B4F6C',
  description text,
  phone       text,
  whatsapp    text,
  sort        int  not null default 0,
  active      boolean not null default true
);

create table if not exists public.services (
  id          uuid primary key default gen_random_uuid(),
  office_slug text not null references public.offices(slug) on update cascade on delete cascade,
  name        text not null,
  description text,
  price_text  text,
  sort        int not null default 0,
  active      boolean not null default true
);

create table if not exists public.offers (
  id          uuid primary key default gen_random_uuid(),
  office_slug text references public.offices(slug) on update cascade on delete cascade,
  title       text not null,
  description text,
  price_text  text,
  badge       text,
  popular     boolean not null default false,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.banners (
  id       uuid primary key default gen_random_uuid(),
  title    text not null,
  subtitle text,
  color    text not null default '#0B4F6C',
  link     text,
  sort     int not null default 0,
  active   boolean not null default true
);

create table if not exists public.app_settings (
  key   text primary key,
  value text not null
);

-- ---------------------------------------------------------------------
-- 4) السفر والترحيلات
-- ---------------------------------------------------------------------
create table if not exists public.trips (
  id          uuid primary key default gen_random_uuid(),
  from_city   text not null,
  to_city     text not null,
  depart_at   timestamptz not null,
  price       numeric(12,2) not null check (price >= 0),
  seats_total int not null default 40 check (seats_total between 1 and 80),
  bus_type    text not null default 'عادي',
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.bookings (
  id                 uuid primary key default gen_random_uuid(),
  ref_no             text unique not null default public.gen_ref('BK'),
  user_id            uuid not null references auth.users(id) on delete cascade,
  trip_id            uuid not null references public.trips(id) on delete restrict,
  passenger_name     text not null,
  passenger_phone    text not null,
  passenger_id_no    text,
  seats              int[] not null,
  total              numeric(12,2) not null,
  status             text not null default 'pending'
                     check (status in ('pending','payment_review','confirmed','cancelled')),
  payment_proof_path text,
  created_at         timestamptz not null default now()
);

create table if not exists public.booking_seats (
  trip_id    uuid not null references public.trips(id) on delete cascade,
  seat_no    int  not null,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  primary key (trip_id, seat_no)
);

-- ---------------------------------------------------------------------
-- 5) الإرساليات
-- ---------------------------------------------------------------------
create table if not exists public.shipments (
  id             uuid primary key default gen_random_uuid(),
  tracking_no    text unique not null default public.gen_ref('TRK'),
  user_id        uuid not null references auth.users(id) on delete cascade,
  sender_name    text not null,
  sender_phone   text not null,
  from_place     text not null,
  receiver_name  text not null,
  receiver_phone text not null,
  to_place       text not null,
  weight_kg      numeric(8,2) not null default 1 check (weight_kg > 0),
  description    text,
  cost           numeric(12,2) not null default 0,
  status         text not null default 'received'
                 check (status in ('received','in_transit','arrived','delivered','cancelled')),
  lat            double precision,
  lng            double precision,
  created_at     timestamptz not null default now()
);

create table if not exists public.shipment_events (
  id          uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete cascade,
  status      text not null,
  note        text,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 6) العقارات
-- ---------------------------------------------------------------------
create table if not exists public.properties (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  kind       text not null default 'شقة',
  listing    text not null default 'sale' check (listing in ('sale','rent')),
  price      numeric(14,2) not null,
  city       text not null,
  area       text,
  rooms      int,
  baths      int,
  size_m2    int,
  details    text,
  image_url  text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.property_requests (
  id          uuid primary key default gen_random_uuid(),
  ref_no      text unique not null default public.gen_ref('RE'),
  user_id     uuid not null references auth.users(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  kind        text not null check (kind in ('viewing','booking')),
  phone       text not null,
  note        text,
  status      text not null default 'pending'
              check (status in ('pending','processing','completed','rejected','cancelled')),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 7) التحويلات المالية
-- ---------------------------------------------------------------------
create table if not exists public.transfers (
  id             uuid primary key default gen_random_uuid(),
  ref_no         text unique not null default public.gen_ref('TR'),
  user_id        uuid not null references auth.users(id) on delete cascade,
  kind           text not null check (kind in ('domestic','international')),
  country        text not null,
  currency       text not null,
  amount         numeric(14,2) not null check (amount > 0),
  fee            numeric(14,2) not null default 0,
  total          numeric(14,2) not null default 0,
  sender_name    text not null,
  receiver_name  text not null,
  receiver_phone text not null,
  note           text,
  status         text not null default 'pending'
                 check (status in ('pending','processing','completed','rejected','cancelled')),
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 8) الموافقات الأمنية
-- ---------------------------------------------------------------------
create table if not exists public.security_requests (
  id         uuid primary key default gen_random_uuid(),
  ref_no     text unique not null default public.gen_ref('SC'),
  user_id    uuid not null references auth.users(id) on delete cascade,
  service    text not null,
  full_name  text not null,
  phone      text not null,
  id_no      text,
  notes      text,
  docs       text[] not null default '{}',
  status     text not null default 'pending'
             check (status in ('pending','processing','approved','rejected','cancelled')),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 9) طلبات عامة لباقي المكاتب
-- ---------------------------------------------------------------------
create table if not exists public.service_requests (
  id           uuid primary key default gen_random_uuid(),
  ref_no       text unique not null default public.gen_ref('SR'),
  user_id      uuid not null references auth.users(id) on delete cascade,
  office_slug  text not null references public.offices(slug) on update cascade,
  service_name text not null,
  details      text,
  phone        text not null,
  status       text not null default 'pending'
               check (status in ('pending','processing','completed','rejected','cancelled')),
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 10) الإشعارات
-- ---------------------------------------------------------------------
create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  title      text not null,
  body       text,
  read       boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_bookings_user      on public.bookings(user_id, created_at desc);
create index if not exists idx_shipments_user     on public.shipments(user_id, created_at desc);
create index if not exists idx_transfers_user     on public.transfers(user_id, created_at desc);
create index if not exists idx_security_user      on public.security_requests(user_id, created_at desc);
create index if not exists idx_proprequests_user  on public.property_requests(user_id, created_at desc);
create index if not exists idx_servicereq_user    on public.service_requests(user_id, created_at desc);
create index if not exists idx_notifications_user on public.notifications(user_id, created_at desc);
create index if not exists idx_trips_depart       on public.trips(depart_at);
create index if not exists idx_events_shipment    on public.shipment_events(shipment_id, created_at);
