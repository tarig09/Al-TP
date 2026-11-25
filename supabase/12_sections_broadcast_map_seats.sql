-- =====================================================================
-- AL-MAHATTA | ملف 12
--  1) نظام المكاتب والمشرفين للسفريات فقط؛ باقي الأقسام مباشرة (الإدارة تفعّل المكاتب لأي قسم متى شاءت)
--  2) أسعار الأقسام المباشرة (شحن / رسوم تحويل) تضبطها الإدارة
--  3) نشر إشعار لكل المستخدمين
--  4) موقع الرحلة الحالي (للخريطة)
--  5) عدد مقاعد الرحلة يعدّله المشرف/المدير (حتى 100) مع حماية المقاعد المحجوزة
-- شغّله بعد 11. آمن لو أُعيد تشغيله.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) تفعيل المكاتب لكل قسم
-- ---------------------------------------------------------------------
alter table public.offices add column if not exists use_agencies boolean not null default false;
update public.offices set use_agencies = true where slug = 'travel';

-- ---------------------------------------------------------------------
-- 2) أسعار الأقسام المباشرة (عند عدم وجود مكتب)
-- ---------------------------------------------------------------------
alter table public.offices add column if not exists ship_base    numeric(14,2);
alter table public.offices add column if not exists ship_per_kg  numeric(14,2);
alter table public.offices add column if not exists transfer_pct numeric(6,3);
alter table public.offices add column if not exists transfer_min numeric(14,2);

create or replace function public.calc_shipment()
returns trigger language plpgsql as $$
declare b numeric; k numeric;
begin
  if new.agency_id is not null then
    select ship_base, ship_per_kg into b, k from public.agencies where id = new.agency_id;
  else
    select ship_base, ship_per_kg into b, k from public.offices where slug = 'parcels';
  end if;
  new.cost := case when b is null then 0 else b + coalesce(k, 0) * new.weight_kg end;
  return new;
end $$;

create or replace function public.calc_transfer()
returns trigger language plpgsql as $$
declare p numeric; m numeric;
begin
  if new.agency_id is not null then
    select transfer_pct, transfer_min into p, m from public.agencies where id = new.agency_id;
  else
    select transfer_pct, transfer_min into p, m from public.offices where slug = 'transfers';
  end if;
  new.fee   := case when p is null and m is null then 0
                    else greatest(round(new.amount * coalesce(p, 0) / 100), coalesce(m, 0)) end;
  new.total := new.amount + new.fee;
  return new;
end $$;

-- الإنشاء: بمكتب نشط ومفتوح، أو بدون مكتب إذا كان القسم مباشراً (use_agencies = false)
do $$
declare r record;
begin
  for r in select * from (values ('shipments','parcels'),('transfers','transfers'),('security_requests','security'),('property_requests','realestate')) v(tbl, sec) loop
    execute format('drop policy if exists %I on public.%I', r.tbl || '_insert', r.tbl);
    execute format($p$create policy %I on public.%I for insert to authenticated with check (
        user_id = auth.uid() and (
          (agency_id is null and not coalesce((select o.use_agencies from public.offices o where o.slug = %L), false))
          or exists (select 1 from public.agencies a where a.id = agency_id and a.active and a.is_open)))$p$,
      r.tbl || '_insert', r.tbl, r.sec);
  end loop;
end $$;

-- طلب بلا مكتب: يصل الإشعار لمديري الإدارة
create or replace function public.notify_supervisors()
returns trigger language plpgsql security definer set search_path = public as $$
declare ag uuid := (to_jsonb(new) ->> 'agency_id')::uuid;
begin
  if ag is null then
    insert into public.notifications (user_id, title, body)
    select u, 'طلب جديد: ' || tg_argv[0], 'وصل طلب جديد بانتظار المتابعة.'
      from (select id as u from public.profiles where is_admin
            union select user_id from public.staff where active) s;
  else
    insert into public.notifications (user_id, title, body)
    select user_id, 'طلب جديد: ' || tg_argv[0], 'وصل طلب جديد إلى مكتبك. أول مشرف يستلمه يتابعه مع العميل.'
      from public.agency_staff where agency_id = ag and active;
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- 3) نشر إشعار لكل المستخدمين
-- ---------------------------------------------------------------------
create table if not exists public.broadcasts (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  body       text,
  recipients int  not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.broadcasts enable row level security;
drop policy if exists broadcasts_admin on public.broadcasts;
create policy broadcasts_admin on public.broadcasts for select to authenticated using (public.is_admin());

create or replace function public.admin_broadcast(p_title text, p_body text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'title_required'; end if;
  insert into public.notifications (user_id, title, body)
    select id, trim(p_title), nullif(trim(coalesce(p_body, '')), '') from public.profiles;
  get diagnostics n = row_count;
  insert into public.broadcasts (title, body, recipients, created_by) values (trim(p_title), nullif(trim(coalesce(p_body, '')), ''), n, auth.uid());
  return n;
end $$;
grant execute on function public.admin_broadcast(text, text) to authenticated;

-- العميل يعلّم إشعاراته كمقروءة دفعة واحدة
create or replace function public.mark_all_read()
returns void language sql security definer set search_path = public as $$
  update public.notifications set read = true where user_id = auth.uid() and not read;
$$;
grant execute on function public.mark_all_read() to authenticated;

-- ---------------------------------------------------------------------
-- 4) موقع الرحلة الحالي
-- ---------------------------------------------------------------------
alter table public.trips add column if not exists lat double precision;
alter table public.trips add column if not exists lng double precision;
alter table public.trips add column if not exists loc_updated_at timestamptz;

create or replace function public.trip_loc_stamp()
returns trigger language plpgsql as $$
begin
  if new.lat is distinct from old.lat or new.lng is distinct from old.lng then new.loc_updated_at := now(); end if;
  return new;
end $$;
drop trigger if exists trg_trip_loc on public.trips;
create trigger trg_trip_loc before update on public.trips for each row execute function public.trip_loc_stamp();

-- ---------------------------------------------------------------------
-- 5) عدد المقاعد: من 1 إلى 100، ولا يقل عن أعلى مقعد محجوز
-- ---------------------------------------------------------------------
alter table public.trips drop constraint if exists trips_seats_total_check;
alter table public.trips add constraint trips_seats_total_check check (seats_total between 1 and 100);

create or replace function public.trip_seats_guard()
returns trigger language plpgsql as $$
declare mx int;
begin
  if new.seats_total < old.seats_total then
    select max(seat_no) into mx from public.booking_seats where trip_id = new.id;
    if mx is not null and new.seats_total < mx then raise exception 'seats_in_use'; end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_trip_seats on public.trips;
create trigger trg_trip_seats before update of seats_total on public.trips for each row execute function public.trip_seats_guard();

-- حجز رحلة بلا مكتب مسموح إذا كان قسم السفر مباشراً (use_agencies = false)
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

  if t.agency_id is not null then
    select * into ag from public.agencies where id = t.agency_id and active;
    if not found then raise exception 'trip_unavailable'; end if;
    if not ag.is_open then raise exception 'agency_closed'; end if;
  elsif coalesce((select o.use_agencies from public.offices o where o.slug = 'travel'), false) then
    raise exception 'trip_unavailable';
  end if;

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
