-- ===== الملف 2 من 3: المشغّلات والدوال والصلاحيات =====
-- شغّله بعد 01 وقبل 03.


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

