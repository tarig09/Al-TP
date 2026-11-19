-- =====================================================================
-- AL-MAHATTA | ملف 06: إبقاء 5 مكاتب + رقم واتساب المسافر في الحجز
-- شغّله مرة واحدة بعد الملفات 01–05.
-- =====================================================================

-- 1) حذف المكاتب السبعة (وخدماتها وعروضها ونسب عمولتها تُحذف تلقائياً)
--    ويُحذف معها أي طلبات خدمة تجريبية مرتبطة بها.
delete from public.service_requests
 where office_slug in ('tourism','gov','shipping','hotels','market','cars','ads');

delete from public.offices
 where slug in ('tourism','gov','shipping','hotels','market','cars','ads');

-- 2) رقم واتساب المسافر
alter table public.bookings add column if not exists passenger_whatsapp text;

-- 3) إعادة تعريف دالة الحجز بمعامل واتساب (الدالة القديمة تُحذف لتفادي التعارض)
drop function if exists public.create_booking(uuid, int[], text, text, text);

create or replace function public.create_booking(
  p_trip uuid, p_seats int[], p_name text, p_phone text, p_id_no text,
  p_whatsapp text default null
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

  insert into public.bookings(user_id, trip_id, passenger_name, passenger_phone, passenger_whatsapp, passenger_id_no, seats, total)
  values (auth.uid(), p_trip, p_name, p_phone, nullif(trim(p_whatsapp), ''), p_id_no, p_seats, t.price * array_length(p_seats, 1))
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
