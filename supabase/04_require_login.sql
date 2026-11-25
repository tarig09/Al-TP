-- ===== تحديث: منع القراءة بدون تسجيل دخول =====
-- شغّله مرة واحدة على قاعدتك الحالية.
do $$
declare t text;
begin
  foreach t in array array['offices','services','offers','banners','app_settings','trips','properties'] loop
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;
end $$;

drop policy if exists booking_seats_read on public.booking_seats;
create policy booking_seats_read on public.booking_seats for select to authenticated using (true);

revoke select on public.offices, public.services, public.offers, public.banners,
                 public.app_settings, public.trips, public.properties, public.booking_seats from anon;
