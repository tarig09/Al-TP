# إعداد رسائل الرمز (6 أرقام) في Supabase

بدون هذا الإعداد سيصل **رابط** بدل الرمز. الكود في التطبيق جاهز ويستخدم الرمز فقط.

## 1) قوالب البريد
Supabase → Authentication → Emails (Email Templates):

**Confirm sign up** — Subject: `رمز تأكيد حسابك في المحطة` — Body:
```html
<div dir="rtl" style="font-family:Tahoma,Arial,sans-serif;text-align:center">
  <h2>مرحباً بك في المحطة</h2>
  <p>رمز تأكيد حسابك:</p>
  <p style="font-size:34px;font-weight:bold;letter-spacing:8px">{{ .Token }}</p>
  <p>صالح لمدة محدودة. إن لم تطلبه فتجاهل هذه الرسالة.</p>
</div>
```

**Reset password** — Subject: `رمز استعادة حسابك في المحطة` — نفس الجسم مع تغيير السطر الأول إلى "رمز استعادة كلمة المرور:".

> المهم أن يحتوي الجسم على `{{ .Token }}` ولا يحتوي `{{ .ConfirmationURL }}`.

## 2) طول الرمز
Authentication → Sign In / Providers → Email → **Email OTP Length = 6**، والصلاحية (Expiration) ما تناسبك (الافتراضي ساعة).

## 3) مهم: خدمة إرسال البريد
البريد المدمج في Supabase محدود جداً (حوالي رسالتين في الساعة) ولا يصلح للتشغيل الفعلي.
اربط SMTP حقيقياً من Authentication → Emails → SMTP Settings (مثل Resend أو Brevo أو SendGrid أو Gmail SMTP).

## 4) التأكيد
تأكد أن **Confirm email** مفعّل في Providers → Email حتى يُطلب الرمز للحسابات الجديدة.
