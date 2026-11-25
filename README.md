# AL-MAHATTA – المحطة
تطبيق ويب (PWA) عربي RTL متصل بـ Supabase. بدون لوحة إدارة (ستكون موقعاً مستقلاً).

## الإعداد (مرة واحدة)
1. Supabase → SQL Editor → الصق محتوى `supabase/schema.sql` → Run.
2. Supabase → Authentication → Providers → Email (للتجربة السريعة يمكن إيقاف "Confirm email").
3. GitHub → Settings → Secrets and variables → Actions: `SUPABASE_URL` و `SUPABASE_ANON_KEY`.
4. GitHub → Settings → Pages → Source = **GitHub Actions**.
5. الرابط: https://tarig09.github.io/Al-TP/

> استخدم مفتاح `anon` فقط (وليس service_role). الأمان مضمون عبر RLS في ملف SQL.

---
## إضافات (نظام المكاتب والأدوات)
**ترتيب SQL على قاعدة جديدة:** 01 → 02 → 03 → 04 → 05 (من مستودع الإدارة) → 06 → 07 → 08 → 09 → 10 → 11.

### أيقونة التطبيق وشاشة البداية
المصدر في `resources/android/res` ويُطبَّق تلقائياً أثناء بناء APK عبر `tools/apply_android_branding.py`.

### الإشعارات الفورية (اختياري)
1. أنشئ مشروعاً في Firebase، وأضف تطبيق أندرويد بالمعرّف `com.almahatta.app`، ونزّل `google-services.json`.
2. في GitHub → Settings → Secrets أضف `GOOGLE_SERVICES_JSON` بمحتوى الملف كاملاً.
3. في Firebase → Project settings → Service accounts → Generate new private key، ثم:
   `supabase secrets set FCM_SERVICE_ACCOUNT='<محتوى الملف>'` ثم انشر الدالة: `supabase functions deploy push`.
4. في Supabase → Database → Webhooks: جدول `notifications`، حدث INSERT، النوع Edge Function = push.
بدون هذه الخطوات يعمل كل شيء عدا الإشعار الفوري (تبقى الإشعارات داخل التطبيق).

### توقيع النسخة النهائية (Google Play) — اختياري
```
keytool -genkey -v -keystore release.jks -alias mahatta -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 release.jks     # انسخ الناتج
```
أضف الأسرار: `ANDROID_KEYSTORE_BASE64` (الناتج) و`ANDROID_KEYSTORE_PASSWORD` و`ANDROID_KEY_ALIAS` (mahatta) و`ANDROID_KEY_PASSWORD`. سيخرج Artifact إضافي `AL-MAHATTA-release` (APK موقّع + AAB). احتفظ بملف release.jks في مكان آمن؛ فقدانه يمنع تحديث التطبيق على المتجر.
