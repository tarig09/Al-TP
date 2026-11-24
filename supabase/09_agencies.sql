-- =====================================================================
-- AL-MAHATTA | ملف 09: نظام المكاتب المتعددة داخل كل قسم
--   القسم (offices) ← عدة مكاتب (agencies) ← مشرفان لكل مكتب (agency_staff)
--   العميل يختار المكتب، والطلب يصل لمشرفي المكتب، والأول يستلمه ويتابعه.
-- شغّله مرة واحدة بعد الملفات 01–08. آمن لإعادة التشغيل.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) الجداول
-- ---------------------------------------------------------------------
create table if not exists public.agencies (
  id           uuid primary key default gen_random_uuid(),
  section_slug text not null references public.offices(slug) on update cascade on delete cascade,
  name         text not null,
  logo_url     text,
  description  text,
  phone        text,
  whatsapp     text,
  is_open      boolean not null default true,
  rating_avg   numeric(3,2) not null default 0,
  rating_count int not null default 0,
  sort         int not null default 0,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists idx_agencies_section on public.agencies(section_slug, active);

create table if not exists public.agency_staff (
  agency_id  uuid not null references public.agencies(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  full_name  text,
  email      text,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (agency_id, user_id)
);
create index if not exists idx_agency_staff_user on public.agency_staff(user_id);

create table if not exists public.agency_ratings (
  id         uuid primary key default gen_random_uuid(),
  agency_id  uuid not null references public.agencies(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  stars      int  not null check (stars between 1 and 5),
  comment    text,
  created_at timestamptz not null default now(),
  unique (agency_id, user_id)
);

-- ربط المحتوى بالمكتب
alter table public.trips           add column if not exists agency_id uuid references public.agencies(id) on delete set null;
alter table public.offers          add column if not exists agency_id uuid references public.agencies(id) on delete cascade;
alter table public.properties      add column if not exists agency_id uuid references public.agencies(id) on delete set null;
alter table public.payment_methods add column if not exists agency_id uuid references public.agencies(id) on delete cascade;
create index if not exists idx_trips_agency on public.trips(agency_id);

-- ربط الطلبات بالمكتب + المشرف المستلم
do $$
declare t text;
begin
  foreach t in array array['bookings','shipments','transfers','security_requests','property_requests'] loop
    execute format('alter table public.%I add column if not exists agency_id uuid references public.agencies(id) on delete set null', t);
    execute format('alter table public.%I add column if not exists handled_by uuid references auth.users(id) on delete set null', t);
    execute format('alter table public.%I add column if not exists handled_at timestamptz', t);
    execute format('alter table public.%I add column if not exists handler_name text', t);
    execute format('alter table public.%I add column if not exists handler_phone text', t);
    execute format('create index if not exists %I on public.%I(agency_id, status)', 'idx_' || t || '_agency', t);
  end loop;
end $$;

-- حالة جديدة للحجز: accepted = قبله المشرف وينتظر الدفع
alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check
  check (status in ('pending','accepted','payment_review','confirmed','cancelled'));

create or replace function public.status_ar(s text)
returns text language sql immutable as $$
  select case s
    when 'pending'        then 'قيد المراجعة'
    when 'accepted'       then 'تم قبول طلبك — بانتظار الدفع'
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
-- 2) دوال الصلاحيات
-- ---------------------------------------------------------------------
create or replace function public.is_supervisor_of(p_agency uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_agency is not null and exists (
    select 1 from public.agency_staff
     where agency_id = p_agency and user_id = auth.uid() and active);
$$;

create or replace function public.is_supervisor()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.agency_staff where user_id = auth.uid() and active);
$$;

create or replace function public.my_agencies()
returns setof uuid language sql stable security definer set search_path = public as $$
  select agency_id from public.agency_staff where user_id = auth.uid() and active;
$$;

-- ---------------------------------------------------------------------
-- 3) استلام الطلب وتغيير حالته (المشرف فقط، والأول يستلم)
-- ---------------------------------------------------------------------
create or replace function public.agency_claim(p_table text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare ag uuid; hb uuid; nm text; ph text; n int;
begin
  if p_table not in ('bookings','shipments','transfers','security_requests','property_requests') then
    raise exception 'bad_table';
  end if;
  execute format('select agency_id, handled_by from public.%I where id = $1 for update', p_table)
    into ag, hb using p_id;
  get diagnostics n = row_count;
  if n = 0 or ag is null then raise exception 'not_found'; end if;
  if not (public.is_supervisor_of(ag) or public.is_admin()) then raise exception 'forbidden'; end if;
  if hb is not null and hb <> auth.uid() then raise exception 'already_taken'; end if;
  select full_name, phone into nm, ph from public.profiles where id = auth.uid();
  execute format('update public.%I set handled_by = $2, handled_at = coalesce(handled_at, now()), handler_name = $3, handler_phone = $4 where id = $1', p_table)
    using p_id, auth.uid(), nm, ph;
end $$;

create or replace function public.agency_set_status(
  p_table text, p_id uuid, p_status text, p_lat double precision default null, p_lng double precision default null
) returns void language plpgsql security definer set search_path = public as $$
declare ag uuid; hb uuid; cur text; n int; admin boolean := public.is_admin();
begin
  if p_table not in ('bookings','shipments','transfers','security_requests','property_requests') then
    raise exception 'bad_table';
  end if;
  execute format('select agency_id, handled_by, status from public.%I where id = $1 for update', p_table)
    into ag, hb, cur using p_id;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_found'; end if;
  if not (admin or public.is_supervisor_of(ag)) then raise exception 'forbidden'; end if;
  if not admin and hb is distinct from auth.uid() then raise exception 'not_handler'; end if;

  if p_table = 'bookings' and not admin then
    -- ضوابط مسار الحجز
    if not ((cur = 'pending'        and p_status in ('accepted','cancelled'))
         or (cur = 'accepted'       and p_status = 'cancelled')
         or (cur = 'payment_review' and p_status in ('confirmed','accepted','cancelled'))) then
      raise exception 'bad_transition';
    end if;
    if cur = 'payment_review' and p_status = 'accepted' then
      update public.bookings set payment_proof_path = null where id = p_id;   -- رفض الإثبات ليعيد العميل الرفع
    end if;
  end if;

  if p_table = 'shipments' then
    update public.shipments set status = p_status, lat = coalesce(p_lat, lat), lng = coalesce(p_lng, lng) where id = p_id;
  else
    execute format('update public.%I set status = $2 where id = $1', p_table) using p_id, p_status;
  end if;
end $$;

create or replace function public.agency_set_open(p_agency uuid, p_open boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_supervisor_of(p_agency) or public.is_super()) then raise exception 'forbidden'; end if;
  update public.agencies set is_open = p_open where id = p_agency;
end $$;

-- تعيين مشرف لمكتب بالبريد (للمدير العام؛ يجب أن يكون للشخص حساب في التطبيق)
create or replace function public.admin_add_supervisor(p_email text, p_agency uuid)
returns void language plpgsql security definer set search_path = public as $$
declare u record;
begin
  if not public.is_super() then raise exception 'forbidden'; end if;
  select id, email into u from auth.users where lower(email) = lower(trim(p_email));
  if not found then raise exception 'user_not_found'; end if;
  insert into public.agency_staff (agency_id, user_id, full_name, email)
  values (p_agency, u.id, (select full_name from public.profiles where id = u.id), u.email)
  on conflict (agency_id, user_id) do update set active = true;
  insert into public.notifications (user_id, title, body)
  values (u.id, 'تم تعيينك مشرفاً', 'أصبحت مشرفاً على مكتب. ادخل لوحة الإدارة لمتابعة الطلبات.');
end $$;

-- التقييم: بعد اكتمال طلب فعلي مع هذا المكتب
create or replace function public.rate_agency(p_agency uuid, p_stars int, p_comment text default null)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if p_stars is null or p_stars not between 1 and 5 then raise exception 'bad_stars'; end if;
  if not (
       exists (select 1 from public.bookings           where user_id = me and agency_id = p_agency and status = 'confirmed')
    or exists (select 1 from public.shipments          where user_id = me and agency_id = p_agency and status = 'delivered')
    or exists (select 1 from public.transfers          where user_id = me and agency_id = p_agency and status = 'completed')
    or exists (select 1 from public.security_requests  where user_id = me and agency_id = p_agency and status = 'approved')
    or exists (select 1 from public.property_requests  where user_id = me and agency_id = p_agency and status = 'completed')
  ) then raise exception 'not_eligible'; end if;

  insert into public.agency_ratings (agency_id, user_id, stars, comment)
  values (p_agency, me, p_stars, nullif(trim(p_comment), ''))
  on conflict (agency_id, user_id) do update
    set stars = excluded.stars, comment = excluded.comment, created_at = now();

  update public.agencies a set
    rating_avg   = coalesce((select round(avg(stars)::numeric, 2) from public.agency_ratings where agency_id = p_agency), 0),
    rating_count = (select count(*) from public.agency_ratings where agency_id = p_agency)
  where a.id = p_agency;
end $$;

grant execute on function public.is_supervisor_of(uuid)                                   to authenticated;
grant execute on function public.is_supervisor()                                          to authenticated;
grant execute on function public.my_agencies()                                            to authenticated;
grant execute on function public.agency_claim(text, uuid)                                 to authenticated;
grant execute on function public.agency_set_status(text, uuid, text, double precision, double precision) to authenticated;
grant execute on function public.agency_set_open(uuid, boolean)                           to authenticated;
grant execute on function public.admin_add_supervisor(text, uuid)                         to authenticated;
grant execute on function public.rate_agency(uuid, int, text)                             to authenticated;

-- ---------------------------------------------------------------------
-- 4) الحجز: يرتبط بمكتب الرحلة، ولا يُقبل على مكتب مغلق
-- ---------------------------------------------------------------------
drop function if exists public.create_booking(uuid, int[], text, text, text, text);
create or replace function public.create_booking(
  p_trip uuid, p_seats int[], p_name text, p_phone text, p_id_no text, p_whatsapp text default null
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  t public.trips; b public.bookings; ag public.agencies; s int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  select * into t from public.trips where id = p_trip and active and depart_at > now();
  if not found then raise exception 'trip_unavailable'; end if;

  select * into ag from public.agencies where id = t.agency_id and active;
  if not found then raise exception 'trip_unavailable'; end if;
  if not ag.is_open then raise exception 'agency_closed'; end if;

  if p_seats is null or coalesce(array_length(p_seats, 1), 0) = 0 or array_length(p_seats, 1) > 6 then
    raise exception 'bad_seats';
  end if;

  insert into public.bookings(user_id, trip_id, agency_id, passenger_name, passenger_phone, passenger_whatsapp, passenger_id_no, seats, total)
  values (auth.uid(), p_trip, t.agency_id, p_name, p_phone, nullif(trim(p_whatsapp), ''), p_id_no, p_seats, t.price * array_length(p_seats, 1))
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
grant execute on function public.create_booking(uuid, int[], text, text, text, text) to authenticated;

create or replace function public.cancel_booking(p_booking uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.bookings set status = 'cancelled'
   where id = p_booking and user_id = auth.uid() and status in ('pending','accepted','payment_review');
  if not found then raise exception 'cannot_cancel'; end if;
  delete from public.booking_seats where booking_id = p_booking;
end $$;

-- رفع إثبات الدفع لا يكون إلا بعد قبول المشرف للطلب
create or replace function public.submit_payment_proof(p_booking uuid, p_path text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_path is null or split_part(p_path, '/', 1) <> auth.uid()::text then
    raise exception 'bad_path';
  end if;
  update public.bookings set payment_proof_path = p_path, status = 'payment_review'
   where id = p_booking and user_id = auth.uid() and status = 'accepted';
  if not found then raise exception 'cannot_submit'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 5) المشغّلات: توجيه الطلب للمشرفين، وإشعار العميل عند الاستلام
-- ---------------------------------------------------------------------
create or replace function public.notify_supervisors()
returns trigger language plpgsql security definer set search_path = public as $$
declare ag uuid := (to_jsonb(new) ->> 'agency_id')::uuid;
begin
  if ag is null then return null; end if;
  insert into public.notifications (user_id, title, body)
  select user_id, 'طلب جديد: ' || tg_argv[0], 'وصل طلب جديد إلى مكتبك. أول مشرف يستلمه يتابعه مع العميل.'
    from public.agency_staff where agency_id = ag and active;
  return null;
end $$;

create or replace function public.notify_claim()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.handled_by is not null and new.handled_by is distinct from old.handled_by then
    insert into public.notifications (user_id, title, body)
    values (new.user_id, 'تم استلام طلبك',
            'المشرف ' || coalesce(nullif(new.handler_name, ''), '') || ' سيتابع طلبك معك.');
  end if;
  return null;
end $$;

do $$
declare r record;
begin
  for r in select * from (values
    ('bookings','حجز'),('shipments','إرسالية'),('transfers','تحويل'),
    ('security_requests','موافقة أمنية'),('property_requests','عقار')
  ) as v(tbl, lbl) loop
    execute format('drop trigger if exists trg_notify_sup on public.%I', r.tbl);
    execute format('create trigger trg_notify_sup after insert on public.%I for each row execute function public.notify_supervisors(%L)', r.tbl, r.lbl);
    execute format('drop trigger if exists trg_notify_claim on public.%I', r.tbl);
    execute format('create trigger trg_notify_claim after update of handled_by on public.%I for each row execute function public.notify_claim()', r.tbl);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 6) الأمان (RLS)
-- ---------------------------------------------------------------------
alter table public.agencies       enable row level security;
alter table public.agency_staff   enable row level security;
alter table public.agency_ratings enable row level security;

drop policy if exists agencies_read on public.agencies;
create policy agencies_read on public.agencies for select to authenticated
  using (active or public.is_admin() or public.is_supervisor_of(id));
drop policy if exists agencies_super on public.agencies;
create policy agencies_super on public.agencies for all to authenticated
  using (public.is_super()) with check (public.is_super());

drop policy if exists agency_staff_read on public.agency_staff;
create policy agency_staff_read on public.agency_staff for select to authenticated
  using (user_id = auth.uid() or public.is_admin() or public.is_supervisor_of(agency_id));
drop policy if exists agency_staff_super on public.agency_staff;
create policy agency_staff_super on public.agency_staff for all to authenticated
  using (public.is_super()) with check (public.is_super());

drop policy if exists ratings_read on public.agency_ratings;
create policy ratings_read on public.agency_ratings for select to authenticated using (true);
drop policy if exists ratings_admin on public.agency_ratings;
create policy ratings_admin on public.agency_ratings for delete to authenticated using (public.is_admin());

-- الطلبات: العميل ومشرفو المكتب والإدارة يقرؤون
do $$
declare t text;
begin
  foreach t in array array['bookings','shipments','transfers','security_requests','property_requests'] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid() or public.is_admin() or public.is_supervisor_of(agency_id))', t || '_select', t);
  end loop;

  -- الإنشاء المباشر مشروط بمكتب نشط ومفتوح
  foreach t in array array['shipments','transfers','security_requests','property_requests'] loop
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (user_id = auth.uid() and exists (select 1 from public.agencies a where a.id = agency_id and a.active and a.is_open))', t || '_insert', t);
  end loop;
end $$;

-- مشرف المكتب يدير رحلات وعروض وعقارات مكتبه فقط
do $$
declare t text;
begin
  foreach t in array array['trips','offers','properties'] loop
    execute format('drop policy if exists %I on public.%I', t || '_sup', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.is_supervisor_of(agency_id)) with check (public.is_supervisor_of(agency_id))', t || '_sup', t);
  end loop;
end $$;

-- مشرف المكتب يرى إثباتات الدفع ومستندات طلبات مكتبه
drop policy if exists "mahatta_read_sup" on storage.objects;
create policy "mahatta_read_sup" on storage.objects for select to authenticated
  using (
    (bucket_id = 'payment-proofs' and exists (
        select 1 from public.bookings b where b.payment_proof_path = name and public.is_supervisor_of(b.agency_id)))
    or
    (bucket_id = 'documents' and exists (
        select 1 from public.security_requests s where name = any (s.docs) and public.is_supervisor_of(s.agency_id)))
  );

-- ---------------------------------------------------------------------
-- 7) بيانات تجريبية (عدّلها من لوحة الإدارة)
-- ---------------------------------------------------------------------
insert into public.agencies (section_slug, name, description, phone, whatsapp, sort)
select v.section_slug, v.name, v.description, '+249900000000', '249900000000', v.sort
from (values
  ('travel',     'أبو محمد للسفريات',    'رحلات يومية بأسعار مناسبة وباصات نظيفة.',          1),
  ('travel',     'المعلم',               'خبرة طويلة في خطوط الشرق والوسط.',                  2),
  ('travel',     'النورس',               'باصات سياحية مكيّفة ومواعيد دقيقة.',                3),
  ('parcels',    'الأمين للإرساليات',    'استلام وتوصيل الطرود بين المدن.',                   1),
  ('parcels',    'سريع إكسبريس',         'إرساليات سريعة مع تتبع لحظي.',                      2),
  ('realestate', 'الفرسان للعقارات',     'بيع وإيجار الشقق والفلل.',                          1),
  ('realestate', 'المدينة للعقارات',     'أراضٍ ومنازل في الخرطوم وأم درمان.',                2),
  ('transfers',  'الأمان للتحويلات',     'تحويلات داخلية وخارجية بأمان.',                     1),
  ('transfers',  'الثقة للصرافة',        'أسعار منافسة ورسوم واضحة.',                         2),
  ('security',   'مكتب الإنجاز',         'متابعة الموافقات والتصاريح الأمنية.',               1),
  ('security',   'مكتب الوفاء للخدمات',  'إنجاز سريع للمعاملات الأمنية.',                     2)
) as v(section_slug, name, description, sort)
where not exists (select 1 from public.agencies a where a.section_slug = v.section_slug and a.name = v.name);

-- ربط الرحلات والعقارات الموجودة بمكاتب (توزيع دوري) إن لم تكن مرتبطة
with ag as (select id, row_number() over (order by sort) rn, count(*) over () n from public.agencies where section_slug = 'travel'),
     tr as (select id, row_number() over (order by depart_at) rn from public.trips where agency_id is null)
update public.trips t set agency_id = (select ag.id from ag where ag.rn = ((tr.rn - 1) % (select max(n) from ag)) + 1)
from tr where t.id = tr.id;

with ag as (select id, row_number() over (order by sort) rn, count(*) over () n from public.agencies where section_slug = 'realestate'),
     pr as (select id, row_number() over (order by created_at) rn from public.properties where agency_id is null)
update public.properties p set agency_id = (select ag.id from ag where ag.rn = ((pr.rn - 1) % (select max(n) from ag)) + 1)
from pr where p.id = pr.id;

-- عروض لمكاتب السفر
insert into public.offers (office_slug, agency_id, title, description, price_text, badge, popular)
select 'travel', a.id, v.title, v.description, v.price_text, v.badge, true
from (values
  ('أبو محمد للسفريات', 'خصم 10% على رحلات نهاية الأسبوع', 'احجز مبكراً ووفّر.', 'خصم 10%', 'عرض'),
  ('المعلم',            'الطفل دون 5 سنوات مجاناً',         'على جميع الخطوط.',  'مجاناً',   'عرض'),
  ('النورس',            'مقعد VIP بسعر عادي',              'لفترة محدودة.',     'VIP',      'جديد')
) as v(agency, title, description, price_text, badge)
join public.agencies a on a.name = v.agency and a.section_slug = 'travel'
where not exists (select 1 from public.offers o where o.agency_id = a.id);

-- =====================================================================
-- بعد التشغيل: عيّن مشرفين من موقع الإدارة (صفحة المكاتب) أو بالأمر التالي:
--   select public.admin_add_supervisor('email@example.com', '<agency_id>');   -- يعمل من تطبيق الإدارة فقط
--   أو من SQL Editor مباشرة:
--   insert into public.agency_staff(agency_id, user_id, email)
--   select '<agency_id>', id, email from auth.users where email = 'email@example.com';
-- =====================================================================
