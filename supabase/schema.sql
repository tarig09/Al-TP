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
returns text language sql volatile as $$
  select prefix || '-' || upper(substr(encode(gen_random_bytes(5), 'hex'), 1, 7));
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

-- ---------------------------------------------------------------------
-- 11) المشغّلات (Triggers)
-- ---------------------------------------------------------------------

-- تثبيت المالك والحالة الأولية (لا يمكن للعميل التلاعب بها)
create or replace function public.set_initial()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    new.user_id := auth.uid();
  end if;
  new.status := tg_argv[0];
  return new;
end $$;

-- حساب رسوم التحويل: 2% بحد أدنى 500
create or replace function public.calc_transfer()
returns trigger language plpgsql as $$
begin
  new.fee   := greatest(round(new.amount * 0.02), 500);
  new.total := new.amount + new.fee;
  return new;
end $$;

-- حساب تكلفة الإرسالية: 3000 + 1500 لكل كجم
create or replace function public.calc_shipment()
returns trigger language plpgsql as $$
begin
  new.cost := 3000 + 1500 * new.weight_kg;
  return new;
end $$;

-- سجل حالات الإرسالية
create or replace function public.log_shipment_event()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.shipment_events(shipment_id, status, note)
    values (new.id, new.status, 'تم استلام الإرسالية وتسجيلها');
  elsif new.status is distinct from old.status then
    insert into public.shipment_events(shipment_id, status, note)
    values (new.id, new.status, public.status_ar(new.status));
  end if;
  return null;
end $$;

-- الإشعارات التلقائية
create or replace function public.notify_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications(user_id, title, body)
    values (new.user_id, 'تم استلام ' || tg_argv[0], 'تم تسجيل طلبك بنجاح وسنوافيك بالمستجدات.');
  elsif new.status is distinct from old.status then
    insert into public.notifications(user_id, title, body)
    values (new.user_id, 'تحديث على ' || tg_argv[0], 'أصبحت الحالة: ' || public.status_ar(new.status));
  end if;
  return null;
end $$;

do $$
declare r record;
begin
  -- الحالة الأولية
  for r in select * from (values
    ('bookings','pending'),('shipments','received'),('transfers','pending'),
    ('security_requests','pending'),('property_requests','pending'),('service_requests','pending')
  ) as t(tbl, st) loop
    execute format('drop trigger if exists trg_initial on public.%I', r.tbl);
    execute format('create trigger trg_initial before insert on public.%I for each row execute function public.set_initial(%L)', r.tbl, r.st);
  end loop;

  -- الإشعارات
  for r in select * from (values
    ('bookings','الحجز'),('shipments','الإرسالية'),('transfers','التحويل'),
    ('security_requests','الطلب الأمني'),('property_requests','طلب العقار'),('service_requests','الطلب')
  ) as t(tbl, lbl) loop
    execute format('drop trigger if exists trg_notify on public.%I', r.tbl);
    execute format('create trigger trg_notify after insert or update of status on public.%I for each row execute function public.notify_status(%L)', r.tbl, r.lbl);
  end loop;
end $$;

drop trigger if exists trg_calc_transfer on public.transfers;
create trigger trg_calc_transfer before insert on public.transfers
  for each row execute function public.calc_transfer();

drop trigger if exists trg_calc_shipment on public.shipments;
create trigger trg_calc_shipment before insert on public.shipments
  for each row execute function public.calc_shipment();

drop trigger if exists trg_shipment_events on public.shipments;
create trigger trg_shipment_events after insert or update of status on public.shipments
  for each row execute function public.log_shipment_event();

-- ---------------------------------------------------------------------
-- 12) دوال الحجز (RPC)
-- ---------------------------------------------------------------------
create or replace function public.create_booking(
  p_trip uuid, p_seats int[], p_name text, p_phone text, p_id_no text
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  t public.trips;
  b public.bookings;
  s int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  select * into t from public.trips where id = p_trip and active and depart_at > now();
  if not found then raise exception 'trip_unavailable'; end if;

  if p_seats is null or coalesce(array_length(p_seats, 1), 0) = 0
     or array_length(p_seats, 1) > 6 then
    raise exception 'bad_seats';
  end if;

  insert into public.bookings(user_id, trip_id, passenger_name, passenger_phone, passenger_id_no, seats, total)
  values (auth.uid(), p_trip, p_name, p_phone, p_id_no, p_seats, t.price * array_length(p_seats, 1))
  returning * into b;

  foreach s in array p_seats loop
    if s < 1 or s > t.seats_total then raise exception 'bad_seat'; end if;
    begin
      insert into public.booking_seats(trip_id, seat_no, booking_id) values (p_trip, s, b.id);
    exception when unique_violation then
      raise exception 'seat_taken';
    end;
  end loop;

  return b;
end $$;

create or replace function public.cancel_booking(p_booking uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.bookings set status = 'cancelled'
   where id = p_booking and user_id = auth.uid() and status in ('pending','payment_review');
  if not found then raise exception 'cannot_cancel'; end if;
  delete from public.booking_seats where booking_id = p_booking;
end $$;

create or replace function public.submit_payment_proof(p_booking uuid, p_path text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_path is null or split_part(p_path, '/', 1) <> auth.uid()::text then
    raise exception 'bad_path';
  end if;
  update public.bookings
     set payment_proof_path = p_path, status = 'payment_review'
   where id = p_booking and user_id = auth.uid() and status = 'pending';
  if not found then raise exception 'cannot_submit'; end if;
end $$;

grant execute on function public.create_booking(uuid, int[], text, text, text) to authenticated;
grant execute on function public.cancel_booking(uuid)                          to authenticated;
grant execute on function public.submit_payment_proof(uuid, text)              to authenticated;

-- ---------------------------------------------------------------------
-- 13) الصلاحيات الدقيقة على مستوى الأعمدة
-- ---------------------------------------------------------------------
revoke update on public.profiles from authenticated;
grant  update (full_name, phone, city) on public.profiles to authenticated;

revoke insert, update on public.notifications from authenticated;
grant  update (read) on public.notifications to authenticated;

-- ---------------------------------------------------------------------
-- 14) Row Level Security
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','offices','services','offers','banners','app_settings','trips','bookings',
    'booking_seats','shipments','shipment_events','properties','property_requests',
    'transfers','security_requests','service_requests','notifications'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ملفات شخصية
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = auth.uid());

-- محتوى عام: قراءة للجميع، تعديل للإدارة
do $$
declare t text;
begin
  foreach t in array array['offices','services','offers','banners','app_settings','trips','properties'] loop
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
    execute format('drop policy if exists %I on public.%I', t || '_admin', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t || '_admin', t);
  end loop;
end $$;

-- المقاعد المحجوزة (أرقام فقط) مرئية للجميع لعرض الخريطة
drop policy if exists booking_seats_read on public.booking_seats;
create policy booking_seats_read on public.booking_seats for select to authenticated using (true);

-- جداول المستخدم: يرى ويُنشئ ما يخصه، والإدارة ترى وتعدّل الكل
do $$
declare t text;
begin
  foreach t in array array[
    'bookings','shipments','property_requests','transfers','security_requests','service_requests'
  ] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid() or public.is_admin())', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_admin', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.is_admin()) with check (public.is_admin())', t || '_admin', t);
  end loop;

  foreach t in array array['shipments','property_requests','transfers','security_requests','service_requests'] loop
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (user_id = auth.uid())', t || '_insert', t);
  end loop;
end $$;

-- الحجوزات تُنشأ عبر دالة create_booking فقط (لا توجد سياسة insert للعملاء)،
-- والمقاعد يديرها المسؤول فقط
drop policy if exists booking_seats_admin on public.booking_seats;
create policy booking_seats_admin on public.booking_seats for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- أحداث الإرسالية
drop policy if exists events_select on public.shipment_events;
create policy events_select on public.shipment_events for select to authenticated
  using (exists (select 1 from public.shipments s
                  where s.id = shipment_id and (s.user_id = auth.uid() or public.is_admin())));
drop policy if exists events_admin on public.shipment_events;
create policy events_admin on public.shipment_events for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- الإشعارات
drop policy if exists notif_select on public.notifications;
create policy notif_select on public.notifications for select to authenticated
  using (user_id = auth.uid());
drop policy if exists notif_update on public.notifications;
create policy notif_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 15) التخزين (Storage): إثباتات الدفع والمستندات
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf']),
  ('documents',      'documents',      false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do nothing;

drop policy if exists "mahatta_upload" on storage.objects;
create policy "mahatta_upload" on storage.objects for insert to authenticated
  with check (bucket_id in ('payment-proofs','documents')
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "mahatta_read" on storage.objects;
create policy "mahatta_read" on storage.objects for select to authenticated
  using (bucket_id in ('payment-proofs','documents')
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- =====================================================================
-- 16) بيانات أولية (يمكن تعديلها لاحقاً من لوحة الإدارة)
-- =====================================================================
insert into public.offices (slug, name_ar, icon, color, description, phone, whatsapp, sort) values
  ('travel',     'السفر والترحيلات',  '🚌', '#0B4F6C', 'حجز رحلات الباصات بين المدن واختيار المقعد.', '+249900000000', '249900000000', 1),
  ('parcels',    'الإرساليات',        '📦', '#E07A1F', 'إرسال الطرود وتتبعها خطوة بخطوة.',            '+249900000000', '249900000000', 2),
  ('realestate', 'العقارات',          '🏠', '#2E7D5B', 'بيع وإيجار الشقق والمنازل والأراضي.',         '+249900000000', '249900000000', 3),
  ('transfers',  'التحويلات المالية', '💸', '#6A3FA0', 'تحويلات داخلية وخارجية بأمان.',               '+249900000000', '249900000000', 4),
  ('security',   'الموافقات الأمنية', '🛡️', '#B23A48', 'متابعة الموافقات والتصاريح الأمنية.',         '+249900000000', '249900000000', 5),
  ('tourism',    'السياحة والرحلات',  '🧭', '#0E8A9B', 'برامج سياحية ورحلات منظمة.',                  '+249900000000', '249900000000', 6),
  ('gov',        'الخدمات الحكومية',  '🏛️', '#4A5A6A', 'إنجاز المعاملات والأوراق الحكومية.',          '+249900000000', '249900000000', 7),
  ('shipping',   'الشحن والتوصيل',    '🚚', '#C9871A', 'شحن البضائع وخدمات التوصيل.',                 '+249900000000', '249900000000', 8),
  ('hotels',     'الفنادق والسكن',    '🏨', '#8A4F7D', 'حجز الفنادق والشقق المفروشة.',                '+249900000000', '249900000000', 9),
  ('market',     'سوق المحطة',        '🛍️', '#D1495B', 'بيع وشراء المنتجات والخدمات.',                '+249900000000', '249900000000', 10),
  ('cars',       'صيانة السيارات',    '🔧', '#3D6B8C', 'صيانة وفحص وقطع غيار.',                       '+249900000000', '249900000000', 11),
  ('ads',        'الإعلانات والعروض', '📣', '#F5A623', 'أعلن عن نشاطك داخل المحطة.',                  '+249900000000', '249900000000', 12)
on conflict (slug) do nothing;

insert into public.services (office_slug, name, price_text, sort)
select * from (values
  ('travel',   'حجز مقعد على الباص',          'حسب الخط', 1),
  ('travel',   'ترحيل الأمتعة الإضافية',      'من 2,000 ج.س', 2),
  ('parcels',  'إرسال طرد صغير',              'من 4,500 ج.س', 1),
  ('parcels',  'إرسال طرد كبير',              'حسب الوزن', 2),
  ('realestate','طلب معاينة عقار',            'مجاناً', 1),
  ('realestate','تسويق عقارك',                'عمولة متفق عليها', 2),
  ('transfers','تحويل داخلي',                 '2% بحد أدنى 500 ج.س', 1),
  ('transfers','تحويل خارجي',                 '2% بحد أدنى 500 ج.س', 2),
  ('security', 'تصريح سفر',                   'حسب الطلب', 1),
  ('security', 'موافقة أمنية لنشاط تجاري',    'حسب الطلب', 2),
  ('security', 'تجديد تصريح',                 'حسب الطلب', 3),
  ('tourism',  'رحلة سياحية يوم واحد',        'من 25,000 ج.س', 1),
  ('tourism',  'برنامج سياحي متعدد الأيام',   'حسب البرنامج', 2),
  ('gov',      'استخراج مستند حكومي',         'حسب المستند', 1),
  ('gov',      'متابعة معاملة',               'حسب المعاملة', 2),
  ('shipping', 'شحن بضائع بين المدن',         'حسب الحجم', 1),
  ('shipping', 'توصيل داخل المدينة',          'من 3,000 ج.س', 2),
  ('hotels',   'حجز غرفة فندقية',             'من 15,000 ج.س / ليلة', 1),
  ('hotels',   'حجز شقة مفروشة',              'من 25,000 ج.س / ليلة', 2),
  ('market',   'عرض منتج للبيع',              'مجاناً', 1),
  ('market',   'طلب شراء',                    'حسب المنتج', 2),
  ('cars',     'فحص شامل للسيارة',            'من 8,000 ج.س', 1),
  ('cars',     'تغيير زيت وفلاتر',            'من 12,000 ج.س', 2),
  ('ads',      'إعلان في الصفحة الرئيسية',    'حسب المدة', 1),
  ('ads',      'إعلان داخل مكتب',             'حسب المدة', 2)
) as v(office_slug, name, price_text, sort)
where not exists (select 1 from public.services);

insert into public.offers (office_slug, title, description, price_text, badge, popular)
select * from (values
  ('travel',   'خصم 10% على رحلات نهاية الأسبوع', 'احجز مقعدك مبكراً ووفّر.', 'خصم 10%', 'عرض', true),
  ('parcels',  'الطرد الأول بنصف التكلفة',         'للعملاء الجدد فقط.',       '-50%', 'جديد', true),
  ('hotels',   'ليلة مجانية عند حجز 3 ليالٍ',      'في الفنادق المشاركة.',     'ليلة مجانية', 'عرض', false),
  ('cars',     'فحص مجاني مع تغيير الزيت',          'لفترة محدودة.',            'فحص مجاني', 'الأكثر طلباً', true)
) as v(office_slug, title, description, price_text, badge, popular)
where not exists (select 1 from public.offers);

insert into public.banners (title, subtitle, color, link, sort)
select * from (values
  ('كل خدماتك في محطة واحدة', 'سفر · إرساليات · عقارات · تحويلات', '#0B4F6C', '#/office/travel', 1),
  ('عروض نهاية الأسبوع',      'خصم 10% على رحلات الباصات',          '#E07A1F', '#/trips', 2),
  ('أرسل طردك الآن',          'تتبع إرساليتك لحظة بلحظة',           '#2E7D5B', '#/ship/new', 3)
) as v(title, subtitle, color, link, sort)
where not exists (select 1 from public.banners);

insert into public.trips (from_city, to_city, depart_at, price, seats_total, bus_type)
select * from (values
  ('الخرطوم', 'بورتسودان', now() + interval '1 day'  + interval '6 hours',  45000, 40, 'سياحي'),
  ('الخرطوم', 'مدني',      now() + interval '1 day'  + interval '2 hours',  15000, 40, 'عادي'),
  ('الخرطوم', 'القضارف',   now() + interval '2 days' + interval '5 hours',  25000, 40, 'سياحي'),
  ('الخرطوم', 'كسلا',      now() + interval '2 days' + interval '7 hours',  35000, 40, 'سياحي'),
  ('الخرطوم', 'الأبيض',    now() + interval '3 days' + interval '4 hours',  30000, 40, 'عادي'),
  ('بورتسودان','الخرطوم',  now() + interval '3 days' + interval '8 hours',  45000, 40, 'سياحي')
) as v(from_city, to_city, depart_at, price, seats_total, bus_type)
where not exists (select 1 from public.trips);

insert into public.properties (title, kind, listing, price, city, area, rooms, baths, size_m2, details, image_url)
select * from (values
  ('شقة حديثة في الرياض', 'شقة',  'rent', 250000::numeric,  'الخرطوم', 'الرياض', 3, 2, 120, 'شقة بتشطيب حديث، طابق ثانٍ، قريبة من الخدمات.', 'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=800'),
  ('فيلا فاخرة بحديقة',   'فيلا', 'sale', 180000000::numeric, 'الخرطوم', 'المنشية', 5, 4, 420, 'فيلا واسعة بحديقة ومواقف سيارات وتشطيب راقٍ.', 'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=800'),
  ('منزل عائلي',          'منزل', 'sale', 95000000::numeric,  'أم درمان', 'الثورة', 4, 2, 300, 'منزل عائلي في حي هادئ قريب من المدارس والأسواق.', 'https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=800')
) as v(title, kind, listing, price, city, area, rooms, baths, size_m2, details, image_url)
where not exists (select 1 from public.properties);

insert into public.app_settings (key, value) values
  ('payment_info', 'حوّل المبلغ إلى حساب المحطة (يُحدَّد رقم الحساب من الإدارة)، ثم ارفع صورة إشعار التحويل هنا ليتم تأكيد حجزك.'),
  ('support_phone', '+249900000000')
on conflict (key) do nothing;

-- =====================================================================
-- لجعل حسابك مديراً لاحقاً (للموقع الإداري): بدّل البريد ثم شغّل
--   update public.profiles set is_admin = true
--   where id = (select id from auth.users where email = 'you@example.com');
-- =====================================================================
