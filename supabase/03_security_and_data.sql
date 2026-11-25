-- ===== الملف 3 من 3: الأمان (RLS) والتخزين والبيانات الأولية =====
-- شغّله أخيراً.

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
