# AL-MAHATTA – المحطة
تطبيق ويب (PWA) عربي RTL متصل بـ Supabase. بدون لوحة إدارة (ستكون موقعاً مستقلاً).

## الإعداد (مرة واحدة)
1. Supabase → SQL Editor → الصق محتوى `supabase/schema.sql` → Run.
2. Supabase → Authentication → Providers → Email (للتجربة السريعة يمكن إيقاف "Confirm email").
3. GitHub → Settings → Secrets and variables → Actions: `SUPABASE_URL` و `SUPABASE_ANON_KEY`.
4. GitHub → Settings → Pages → Source = **GitHub Actions**.
5. الرابط: https://tarig09.github.io/Al-TP/

> استخدم مفتاح `anon` فقط (وليس service_role). الأمان مضمون عبر RLS في ملف SQL.
