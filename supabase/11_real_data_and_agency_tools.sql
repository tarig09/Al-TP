-- =====================================================================
-- AL-MAHATTA | ملف 11: بيانات حقيقية فقط + أدوات المشرف
--  1) حذف البيانات التجريبية (التطبيق يبدأ فارغاً حتى يضيف المشرفون بياناتهم)
--  2) تعديل بيانات المكتب والأسعار (شحن/تحويل) من المشرف
--  3) وسائل دفع لكل مكتب يديرها مشرفه
--  4) تحويلات بمسار دفع (قبول ← دفع ← مراجعة ← تنفيذ)
--  5) تتبع الإرسالية بالرقم، رفع شعار/صور المكتب، رموز الإشعارات
-- شغّله مرة واحدة بعد 09 و 10. آمن لو أُعيد تشغيله.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) حذف البيانات التجريبية (بحسب قيمها الأصلية فقط؛ ما أضفته أنت لا يُمس)
-- ---------------------------------------------------------------------
delete from public.offers;                       -- العروض يضيفها المشرفون فقط

-- الرحلات: ما عليه حجوزات يُخفى، والباقي يُحذف
update public.trips t set active = false
 where exists (select 1 from public.bookings b where b.trip_id = t.id)
   and (t.from_city, t.to_city, t.price) in
       (('الخرطوم','بورتسودان',45000),('الخرطوم','مدني',15000),('الخرطوم','القضارف',25000),
        ('الخرطوم','كسلا',35000),('الخرطوم','الأبيض',30000),('بورتسودان','الخرطوم',45000));
delete from public.trips t
 where (t.from_city, t.to_city, t.price) in
       (('الخرطوم','بورتسودان',45000),('الخرطوم','مدني',15000),('الخرطوم','القضارف',25000),
        ('الخرطوم','كسلا',35000),('الخرطوم','الأبيض',30000),('بورتسودان','الخرطوم',45000))
   and not exists (select 1 from public.bookings b where b.trip_id = t.id);

delete from public.properties
 where title in ('شقة حديثة في الرياض','فيلا فاخرة بحديقة','منزل عائلي');

delete from public.banners
 where title in ('كل خدماتك في محطة واحدة','عروض نهاية الأسبوع','أرسل طردك الآن');

delete from public.services s
 where (s.office_slug, s.name) in (
  ('travel','حجز مقعد على الباص'),('travel','ترحيل الأمتعة الإضافية'),('parcels','إرسال طرد صغير'),('parcels','إرسال طرد كبير'),
  ('realestate','طلب معاينة عقار'),('realestate','تسويق عقارك'),('transfers','تحويل داخلي'),('transfers','تحويل خارجي'),
  ('security','تصريح سفر'),('security','موافقة أمنية لنشاط تجاري'),('security','تجديد تصريح'),
  ('tourism','رحلة سياحية يوم واحد'),('tourism','برنامج سياحي متعدد الأيام'),('gov','استخراج مستند حكومي'),('gov','متابعة معاملة'),
  ('shipping','شحن بضائع بين المدن'),('shipping','توصيل داخل المدينة'),('hotels','حجز غرفة فندقية'),('hotels','حجز شقة مفروشة'),
  ('market','عرض منتج للبيع'),('market','طلب شراء'),('cars','فحص شامل للسيارة'),('cars','تغيير زيت وفلاتر'),
  ('ads','إعلان في الصفحة الرئيسية'),('ads','إعلان داخل مكتب'));

-- المكاتب التجريبية التي لم يُعيَّن لها مشرف تُحذف؛ ما له مشرف يبقى (أنت اخترته)
delete from public.agencies a
 where a.name in ('أبو محمد للسفريات','المعلم','النورس','الأمين للإرساليات','سريع إكسبريس','الفرسان للعقارات',
                  'المدينة للعقارات','الأمان للتحويلات','الثقة للصرافة','مكتب الإنجاز','مكتب الوفاء للخدمات')
   and not exists (select 1 from public.agency_staff s where s.agency_id = a.id);

-- أرقام الهواتف الوهمية في الأقسام
update public.offices set phone = null, whatsapp = null where phone = '+249900000000';
delete from public.app_settings where key = 'support_phone' and value = '+249900000000';
delete from public.app_settings where key = 'payment_info' and value like 'حوّل المبلغ إلى حساب المحطة%';

-- ---------------------------------------------------------------------
-- 2) أسعار المكتب وملفه (يعدّلها المشرف)
-- ---------------------------------------------------------------------
alter table public.agencies add column if not exists ship_base       numeric(14,2);   -- أجرة الإرسالية الثابتة
alter table public.agencies add column if not exists ship_per_kg     numeric(14,2);   -- لكل كجم
alter table public.agencies add column if not exists transfer_pct    numeric(6,3);    -- نسبة رسوم التحويل %
alter table public.agencies add column if not exists transfer_min    numeric(14,2);   -- أدنى رسوم

create or replace function public.calc_shipment()
returns trigger language plpgsql as $$
declare b numeric; k numeric;
begin
  select ship_base, ship_per_kg into b, k from public.agencies where id = new.agency_id;
  new.cost := case when b is null then 0 else b + coalesce(k, 0) * new.weight_kg end;
  return new;
end $$;

create or replace function public.calc_transfer()
returns trigger language plpgsql as $$
declare p numeric; m numeric;
begin
  select transfer_pct, transfer_min into p, m from public.agencies where id = new.agency_id;
  new.fee   := case when p is null and m is null then 0
                    else greatest(round(new.amount * coalesce(p, 0) / 100), coalesce(m, 0)) end;
  new.total := new.amount + new.fee;
  return new;
end $$;

-- يعدّل المشرف ملف مكتبه (الاسم، الشعار، النبذة، التواصل، الأسعار)
create or replace function public.agency_update_profile(
  p_agency uuid, p_name text, p_logo text, p_desc text, p_phone text, p_whatsapp text,
  p_ship_base numeric default null, p_ship_per_kg numeric default null,
  p_transfer_pct numeric default null, p_transfer_min numeric default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_supervisor_of(p_agency) or public.is_super()) then raise exception 'forbidden'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'name_required'; end if;
  update public.agencies set
    name = trim(p_name), logo_url = nullif(trim(coalesce(p_logo, '')), ''), description = nullif(trim(coalesce(p_desc, '')), ''),
    phone = nullif(trim(coalesce(p_phone, '')), ''), whatsapp = nullif(trim(coalesce(p_whatsapp, '')), ''),
    ship_base = p_ship_base, ship_per_kg = p_ship_per_kg, transfer_pct = p_transfer_pct, transfer_min = p_transfer_min
  where id = p_agency;
end $$;

-- المشرف المتابع يحدد تكلفة إرسالية (عند عدم ضبط أسعار ثابتة)
create or replace function public.agency_set_cost(p_shipment uuid, p_cost numeric)
returns void language plpgsql security definer set search_path = public as $$
declare ag uuid; hb uuid; n int;
begin
  select agency_id, handled_by into ag, hb from public.shipments where id = p_shipment;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_found'; end if;
  if not (public.is_super() or public.is_admin() or (public.is_supervisor_of(ag) and hb = auth.uid())) then raise exception 'not_handler'; end if;
  if p_cost is null or p_cost < 0 then raise exception 'bad_amount'; end if;
  update public.shipments set cost = p_cost where id = p_shipment;
end $$;

grant execute on function public.agency_update_profile(uuid, text, text, text, text, text, numeric, numeric, numeric, numeric) to authenticated;
grant execute on function public.agency_set_cost(uuid, numeric) to authenticated;

-- ---------------------------------------------------------------------
-- 3) وسائل الدفع: لكل مكتب وسائله ويديرها مشرفه
-- ---------------------------------------------------------------------
drop policy if exists paymethods_sup on public.payment_methods;
create policy paymethods_sup on public.payment_methods for all to authenticated
  using (public.is_supervisor_of(agency_id)) with check (public.is_supervisor_of(agency_id));

-- ---------------------------------------------------------------------
-- 4) التحويلات: قبول ← دفع ← مراجعة ← تنفيذ
-- ---------------------------------------------------------------------
alter table public.transfers drop constraint if exists transfers_status_check;
alter table public.transfers add constraint transfers_status_check
  check (status in ('pending','accepted','payment_review','processing','completed','rejected','cancelled'));
alter table public.transfers add column if not exists payment_proof_path text;

create or replace function public.submit_transfer_proof(p_transfer uuid, p_path text)
returns void language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if split_part(p_path, '/', 1) <> auth.uid()::text then raise exception 'forbidden'; end if;
  update public.transfers set payment_proof_path = p_path, status = 'payment_review'
   where id = p_transfer and user_id = auth.uid() and status = 'accepted';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'bad_transition'; end if;
end $$;
grant execute on function public.submit_transfer_proof(uuid, text) to authenticated;

create or replace function public.cancel_transfer(p_transfer uuid)
returns void language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.transfers set status = 'cancelled'
   where id = p_transfer and user_id = auth.uid() and status in ('pending','accepted','payment_review');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'bad_transition'; end if;
end $$;
grant execute on function public.cancel_transfer(uuid) to authenticated;

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
    if not ((cur = 'pending'        and p_status in ('accepted','cancelled'))
         or (cur = 'accepted'       and p_status = 'cancelled')
         or (cur = 'payment_review' and p_status in ('confirmed','accepted','cancelled'))) then
      raise exception 'bad_transition';
    end if;
    if cur = 'payment_review' and p_status = 'accepted' then
      update public.bookings set payment_proof_path = null where id = p_id;
    end if;
  end if;

  if p_table = 'transfers' and not admin then
    if not ((cur = 'pending'        and p_status in ('accepted','rejected','cancelled'))
         or (cur = 'accepted'       and p_status in ('rejected','cancelled'))
         or (cur = 'payment_review' and p_status in ('processing','completed','accepted','rejected'))
         or (cur = 'processing'     and p_status in ('completed','rejected'))) then
      raise exception 'bad_transition';
    end if;
    if cur = 'payment_review' and p_status = 'accepted' then
      update public.transfers set payment_proof_path = null where id = p_id;
    end if;
  end if;

  if p_table = 'shipments' then
    update public.shipments set status = p_status, lat = coalesce(p_lat, lat), lng = coalesce(p_lng, lng) where id = p_id;
  else
    execute format('update public.%I set status = $2 where id = $1', p_table) using p_id, p_status;
  end if;
end $$;
grant execute on function public.agency_set_status(text, uuid, text, double precision, double precision) to authenticated;

-- المشرف يرى إثباتات دفع التحويلات أيضاً
drop policy if exists "mahatta_read_sup" on storage.objects;
create policy "mahatta_read_sup" on storage.objects for select to authenticated
  using (
    (bucket_id = 'payment-proofs' and (
        exists (select 1 from public.bookings b where b.payment_proof_path = name and public.is_supervisor_of(b.agency_id))
     or exists (select 1 from public.transfers t where t.payment_proof_path = name and public.is_supervisor_of(t.agency_id))))
    or
    (bucket_id = 'documents' and exists (
        select 1 from public.security_requests s where name = any (s.docs) and public.is_supervisor_of(s.agency_id)))
  );

-- ---------------------------------------------------------------------
-- 5) تتبع إرسالية بالرقم (لأي مستخدم مسجّل) بدون كشف بيانات خاصة
-- ---------------------------------------------------------------------
create or replace function public.track_shipment(p_no text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s record; ev jsonb;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select sh.*, a.name as agency_name into s
    from public.shipments sh left join public.agencies a on a.id = sh.agency_id
   where sh.tracking_no = upper(trim(p_no));
  if not found then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('status', e.status, 'created_at', e.created_at) order by e.created_at), '[]'::jsonb)
    into ev from public.shipment_events e where e.shipment_id = s.id;
  return jsonb_build_object('tracking_no', s.tracking_no, 'status', s.status, 'from_place', s.from_place, 'to_place', s.to_place,
                            'weight_kg', s.weight_kg, 'lat', s.lat, 'lng', s.lng, 'agency_name', s.agency_name,
                            'created_at', s.created_at, 'events', ev);
end $$;
grant execute on function public.track_shipment(text) to authenticated;

-- ---------------------------------------------------------------------
-- 6) شعارات وصور المكاتب (عامة للقراءة، والرفع لمشرف المكتب داخل مجلد باسم المكتب)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('agency-assets', 'agency-assets', true, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists "agency_assets_read" on storage.objects;
create policy "agency_assets_read" on storage.objects for select to public using (bucket_id = 'agency-assets');
drop policy if exists "agency_assets_write" on storage.objects;
create policy "agency_assets_write" on storage.objects for insert to authenticated
  with check (bucket_id = 'agency-assets'
    and (public.is_super() or public.is_supervisor_of(nullif((storage.foldername(name))[1], '')::uuid)));
drop policy if exists "agency_assets_update" on storage.objects;
create policy "agency_assets_update" on storage.objects for update to authenticated
  using (bucket_id = 'agency-assets'
    and (public.is_super() or public.is_supervisor_of(nullif((storage.foldername(name))[1], '')::uuid)));
drop policy if exists "agency_assets_delete" on storage.objects;
create policy "agency_assets_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'agency-assets'
    and (public.is_super() or public.is_supervisor_of(nullif((storage.foldername(name))[1], '')::uuid)));

-- ---------------------------------------------------------------------
-- 7) رموز أجهزة الإشعارات الفورية (Push)
-- ---------------------------------------------------------------------
create table if not exists public.device_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  platform   text not null default 'android',
  updated_at timestamptz not null default now()
);
alter table public.device_tokens enable row level security;
drop policy if exists device_tokens_own on public.device_tokens;
create policy device_tokens_own on public.device_tokens for select to authenticated using (user_id = auth.uid());

create or replace function public.register_device(p_token text, p_platform text default 'android')
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into public.device_tokens(token, user_id, platform) values (p_token, auth.uid(), coalesce(p_platform, 'android'))
  on conflict (token) do update set user_id = auth.uid(), updated_at = now();
end $$;
grant execute on function public.register_device(text, text) to authenticated;
