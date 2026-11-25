// Supabase Edge Function: يرسل إشعار Push (FCM) عند إضافة صف جديد في جدول notifications.
// الإعداد: Database → Webhooks → جدول notifications، حدث INSERT، نوع Supabase Edge Functions → push
// الأسرار: supabase secrets set FCM_SERVICE_ACCOUNT='{...محتوى ملف الخدمة JSON...}'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const sa = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT') ?? '{}');
const b64u = (b: ArrayBuffer | string) =>
  btoa(typeof b === 'string' ? b : String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const head = b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64u(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 }));
  const pem = sa.private_key.replace(/-----[^-]+-----|\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${head}.${claim}`));
  const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${head}.${claim}.${b64u(sig)}` });
  return (await r.json()).access_token;
}

Deno.serve(async (req) => {
  const { record } = await req.json();
  if (!record?.user_id) return new Response('no record');
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: toks } = await db.from('device_tokens').select('token').eq('user_id', record.user_id);
  if (!toks?.length) return new Response('no tokens');
  const at = await accessToken();
  for (const { token } of toks) {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: 'POST', headers: { Authorization: `Bearer ${at}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: { token, notification: { title: record.title, body: record.body ?? '' }, android: { priority: 'HIGH' } } }),
    });
    if (r.status === 404 || r.status === 400) await db.from('device_tokens').delete().eq('token', token); // رمز منتهي
  }
  return new Response('ok');
});
