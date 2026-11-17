/* AL-MAHATTA – المحطة | واجهة حقيقية متصلة بـ Supabase (بدون لوحة الإدارة) */
(() => {
const $app = document.getElementById('app');
const sb = (window.ENV && ENV.SUPABASE_URL) ? supabase.createClient(ENV.SUPABASE_URL, ENV.SUPABASE_ANON_KEY) : null;
let user = null, unread = 0, offices = [];

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money = n => Number(n || 0).toLocaleString('ar-EG') + ' ج.س';
const dt = d => new Date(d).toLocaleString('ar-EG', {dateStyle:'medium', timeStyle:'short'});
const ST = {pending:['قيد المراجعة','warn'],payment_review:['مراجعة الدفع','info'],confirmed:['مؤكد','ok'],cancelled:['ملغي','bad'],received:['تم الاستلام','info'],in_transit:['في الطريق','warn'],arrived:['وصلت للوجهة','info'],delivered:['تم التسليم','ok'],processing:['قيد التنفيذ','warn'],completed:['مكتمل','ok'],approved:['تمت الموافقة','ok'],rejected:['مرفوض','bad']};
const badge = s => `<span class="badge ${(ST[s]||[s,''])[1]}">${(ST[s]||[s])[0]}</span>`;
const toast = m => { const t = document.getElementById('toast'); t.textContent = m; t.classList.add('show'); clearTimeout(t._t); t._t = setTimeout(() => t.classList.remove('show'), 2800); };
const errMsg = e => ({seat_taken:'أحد المقاعد حُجز للتو، اختر مقعداً آخر.',trip_unavailable:'الرحلة غير متاحة.',bad_seats:'اختر من 1 إلى 6 مقاعد.',not_authenticated:'سجّل الدخول أولاً.'}[e?.message] || e?.message || 'حدث خطأ');
const go = h => { location.hash = h; };
const val = id => (document.getElementById(id)?.value || '').trim();
const busy = (b, on) => { b.disabled = on; };

/* ---------- القوالب العامة ---------- */
const top = (title, back = true) => `<div class="top">${back ? '<button class="back" onclick="history.back()">›</button>' : ''}<h2>${esc(title)}</h2></div>`;
const nav = on => `<nav class="nav">
  <a href="#/" class="${on==='home'?'on':''}"><span class="i">🏠</span>الرئيسية</a>
  <a href="#/orders" class="${on==='orders'?'on':''}"><span class="i">📋</span>طلباتي</a>
  <a href="#/notifs" class="${on==='notifs'?'on':''}"><span class="i">🔔</span>الإشعارات${unread?`<span class="bd">${unread}</span>`:''}</a>
  <a href="#/me" class="${on==='me'?'on':''}"><span class="i">👤</span>حسابي</a></nav>`;
const shell = (html, on, title, back = true) => { $app.innerHTML = (title ? top(title, back) : '') + `<div class="main">${html}</div>` + nav(on); window.scrollTo(0, 0); };
const loading = () => { $app.innerHTML = '<div class="spin">جارٍ التحميل…</div>'; };
const need = () => { if (!user) { go('#/auth'); return false; } return true; };

/* ---------- مصادقة ---------- */
function viewAuth() {
  let mode = 'in';
  const draw = () => {
    $app.innerHTML = `<div class="auth"><div class="logo"><img src="assets/logo.svg" alt=""><h1>المحطة</h1><div class="mut">AL-MAHATTA</div></div>
    <div class="tabs"><button class="${mode==='in'?'on':''}" id="ti">تسجيل الدخول</button><button class="${mode==='up'?'on':''}" id="tu">حساب جديد</button></div>
    <div id="msg"></div>
    ${mode==='up'?'<label>الاسم الكامل</label><input id="fn" autocomplete="name"><label>رقم الهاتف</label><input id="ph" type="tel" inputmode="tel" autocomplete="tel">':''}
    <label>البريد الإلكتروني</label><input id="em" type="email" autocomplete="email" dir="ltr">
    <label>كلمة المرور</label><input id="pw" type="password" autocomplete="${mode==='in'?'current-password':'new-password'}" dir="ltr">
    <div style="height:18px"></div><button class="btn" id="go">${mode==='in'?'دخول':'إنشاء الحساب'}</button></div>`;
    document.getElementById('ti').onclick = () => { mode='in'; draw(); };
    document.getElementById('tu').onclick = () => { mode='up'; draw(); };
    document.getElementById('go').onclick = async e => {
      const b = e.target, email = val('em'), password = document.getElementById('pw').value, m = document.getElementById('msg');
      if (!email || password.length < 6) { m.innerHTML = '<div class="err">أدخل البريد وكلمة مرور (6 أحرف على الأقل).</div>'; return; }
      busy(b, true); m.innerHTML = '';
      let r;
      if (mode === 'in') r = await sb.auth.signInWithPassword({ email, password });
      else {
        if (!val('fn') || !val('ph')) { m.innerHTML = '<div class="err">الاسم والهاتف مطلوبان.</div>'; busy(b, false); return; }
        r = await sb.auth.signUp({ email, password, options: { data: { full_name: val('fn'), phone: val('ph') } } });
        if (!r.error && !r.data.session) { m.innerHTML = '<div class="note">تم إنشاء الحساب. افتح بريدك لتأكيد الحساب ثم سجّل الدخول.</div>'; busy(b, false); return; }
      }
      busy(b, false);
      if (r.error) m.innerHTML = `<div class="err">${esc(r.error.message === 'Invalid login credentials' ? 'البريد أو كلمة المرور غير صحيحة.' : r.error.message)}</div>`;
    };
  };
  draw();
}

/* ---------- الرئيسية ---------- */
async function viewHome() {
  loading();
  const [o, b, f] = await Promise.all([
    sb.from('offices').select('*').eq('active', true).order('sort'),
    sb.from('banners').select('*').eq('active', true).order('sort'),
    sb.from('offers').select('*').eq('active', true).order('popular', { ascending: false }).limit(6)]);
  offices = o.data || [];
  $app.innerHTML = `<div class="brand"><img src="assets/logo.svg" alt=""><div><b>المحطة</b><small>AL-MAHATTA</small></div></div>
  <div class="search"><input id="q" placeholder="ابحث عن خدمة أو مكتب…" autocomplete="off"></div>
  <div class="main"><div class="banners">${(b.data||[]).map(x=>`<a class="banner" href="${esc(x.link||'#/')}" style="background:linear-gradient(135deg,${esc(x.color)},#073548)"><b>${esc(x.title)}</b><span>${esc(x.subtitle)}</span></a>`).join('')}</div>
  <h3 class="sec">المكاتب</h3><div class="grid" id="grid"></div>
  <h3 class="sec">العروض والخدمات الأكثر طلباً</h3>
  ${(f.data||[]).map(x=>`<a class="card row" href="#/office/${esc(x.office_slug)}"><div class="grow"><b>${esc(x.title)}</b><div class="mut">${esc(x.description)}</div></div>${x.badge?`<span class="badge acc">${esc(x.badge)}</span>`:''}</a>`).join('') || '<div class="empty">لا توجد عروض حالياً</div>'}</div>` + nav('home');
  const draw = list => document.getElementById('grid').innerHTML = list.map(x =>
    `<a class="tile" href="#/office/${esc(x.slug)}"><div class="ic" style="background:${esc(x.color)}22">${esc(x.icon)}</div><span>${esc(x.name_ar)}</span></a>`).join('') || '<div class="empty" style="grid-column:1/-1">لا نتائج</div>';
  draw(offices);
  document.getElementById('q').oninput = async e => {
    const q = e.target.value.trim();
    if (!q) return draw(offices);
    const { data } = await sb.from('services').select('office_slug,name').ilike('name', `%${q.replace(/[%,]/g,'')}%`);
    const slugs = new Set((data||[]).map(s => s.office_slug));
    draw(offices.filter(x => x.name_ar.includes(q) || slugs.has(x.slug)));
  };
}

/* ---------- صفحة المكتب ---------- */
const OFFICE_ACTIONS = {
  travel: [['عرض الرحلات وحجز مقعد', '#/trips']],
  parcels: [['تسجيل إرسالية جديدة', '#/ship/new'], ['تتبع إرسالية', '#/ship/track']],
  realestate: [['تصفح العقارات', '#/props']],
  transfers: [['تحويل جديد', '#/transfer/new']],
  security: [['تقديم طلب موافقة', '#/security/new']]
};
async function viewOffice(slug) {
  loading();
  const [o, s, f] = await Promise.all([
    sb.from('offices').select('*').eq('slug', slug).single(),
    sb.from('services').select('*').eq('office_slug', slug).eq('active', true).order('sort'),
    sb.from('offers').select('*').eq('office_slug', slug).eq('active', true)]);
  const of = o.data; if (!of) return shell('<div class="empty">المكتب غير موجود</div>', 'home', 'المكتب');
  const acts = OFFICE_ACTIONS[slug] || [['تقديم طلب', `#/request/${slug}`]];
  $app.innerHTML = top(of.name_ar) + `<div class="hero" style="background:linear-gradient(135deg,${esc(of.color)},#073548)"><div class="ic">${esc(of.icon)}</div><h1>${esc(of.name_ar)}</h1><p>${esc(of.description)}</p></div>
  <div class="main"><h3 class="sec" style="margin-top:4px">الخدمات والأسعار</h3>
  ${(s.data||[]).map(x=>`<div class="card row between"><div><b>${esc(x.name)}</b></div><span class="price">${esc(x.price_text)}</span></div>`).join('')}
  ${(f.data||[]).length?'<h3 class="sec">العروض المتاحة</h3>'+f.data.map(x=>`<div class="card"><div class="row between"><b>${esc(x.title)}</b><span class="badge acc">${esc(x.price_text||x.badge||'عرض')}</span></div><div class="mut">${esc(x.description)}</div></div>`).join(''):''}
  <div style="display:grid;gap:10px;margin-top:14px">${acts.map(a=>`<a class="btn" href="${a[1]}">${a[0]}</a>`).join('')}
  <a class="btn ghost" href="#/request/${slug}">طلب خدمة من المكتب</a></div>
  <h3 class="sec">التواصل</h3><div class="card"><div class="kv"><span>الهاتف</span><b dir="ltr"><a href="tel:${esc(of.phone)}">${esc(of.phone)}</a></b></div>
  <div class="kv"><span>واتساب</span><b><a href="https://wa.me/${esc(of.whatsapp)}" target="_blank" rel="noopener">فتح المحادثة</a></b></div></div></div>` + nav('home');
}

/* ---------- طلب خدمة عام ---------- */
async function viewRequest(slug) {
  if (!need()) return;
  const [o, s] = await Promise.all([sb.from('offices').select('name_ar').eq('slug', slug).single(), sb.from('services').select('name').eq('office_slug', slug).eq('active', true)]);
  shell(`<div id="msg"></div><label>الخدمة</label><select id="sv">${(s.data||[]).map(x=>`<option>${esc(x.name)}</option>`).join('')}</select>
  <label>رقم الهاتف</label><input id="ph" type="tel" dir="ltr" value="${esc(user.phone||'')}"><label>تفاصيل الطلب</label><textarea id="dt"></textarea>
  <div style="height:16px"></div><button class="btn" id="go">إرسال الطلب</button>`, 'home', o.data?.name_ar || 'طلب خدمة');
  document.getElementById('go').onclick = async e => {
    if (!val('ph')) return toast('أدخل رقم الهاتف');
    busy(e.target, true);
    const { error } = await sb.from('service_requests').insert({ office_slug: slug, service_name: val('sv'), details: val('dt'), phone: val('ph') });
    busy(e.target, false); if (error) return toast(errMsg(error));
    toast('تم إرسال طلبك'); go('#/orders');
  };
}

/* ---------- السفر ---------- */
async function viewTrips() {
  loading();
  const { data } = await sb.from('trips').select('*').eq('active', true).gt('depart_at', new Date().toISOString()).order('depart_at');
  const cities = [...new Set((data||[]).map(t => t.to_city))];
  const draw = f => shell(`<div class="chips"><button class="chip ${!f?'on':''}" data-c="">الكل</button>${cities.map(c=>`<button class="chip ${f===c?'on':''}" data-c="${esc(c)}">${esc(c)}</button>`).join('')}</div>
  ${(data||[]).filter(t=>!f||t.to_city===f).map(t=>`<div class="card"><div class="row"><svg class="bus" viewBox="0 0 64 40"><rect x="2" y="4" width="60" height="26" rx="7" fill="#0B4F6C"/><rect x="8" y="9" width="12" height="9" rx="2" fill="#bfe3f2"/><rect x="24" y="9" width="12" height="9" rx="2" fill="#bfe3f2"/><rect x="40" y="9" width="12" height="9" rx="2" fill="#bfe3f2"/><circle cx="16" cy="32" r="5" fill="#16222B"/><circle cx="48" cy="32" r="5" fill="#16222B"/></svg>
  <div class="grow"><div class="route">${esc(t.from_city)} <i>←</i> ${esc(t.to_city)}</div><div class="mut">${dt(t.depart_at)} · ${esc(t.bus_type)}</div></div></div>
  <div class="row between" style="margin-top:12px"><span class="price" style="font-size:18px">${money(t.price)}</span><a class="btn sm" href="#/seats/${t.id}">اختيار الرحلة</a></div></div>`).join('') || '<div class="empty"><div class="big">🚌</div>لا توجد رحلات متاحة حالياً</div>'}`, 'home', 'خطوط الرحلات');
  draw('');
  $app.onclick = function h(e) { const c = e.target.closest('.chip'); if (c) { draw(c.dataset.c); $app.onclick = h; } };
}

const bookingDraft = {};
async function viewSeats(id) {
  loading();
  const [t, bs] = await Promise.all([sb.from('trips').select('*').eq('id', id).single(), sb.from('booking_seats').select('seat_no').eq('trip_id', id)]);
  const trip = t.data; if (!trip) return shell('<div class="empty">الرحلة غير موجودة</div>', 'home', 'المقاعد');
  const taken = new Set((bs.data||[]).map(x => x.seat_no)); let sel = [];
  const rows = Math.ceil(trip.seats_total / 4);
  let g = ''; let n = 1;
  for (let r = 0; r < rows; r++) for (let c = 0; c < 5; c++) {
    if (c === 2) { g += '<div></div>'; continue; }
    if (n > trip.seats_total) { g += '<div></div>'; continue; }
    g += `<button class="seat ${taken.has(n)?'booked':''}" data-n="${n}" ${taken.has(n)?'disabled':''}>${n}</button>`; n++;
  }
  shell(`<div class="card"><div class="route">${esc(trip.from_city)} <i>←</i> ${esc(trip.to_city)}</div><div class="mut">${dt(trip.depart_at)}</div></div>
  <div class="legend"><span><i style="background:#e8f5ee;border:2px solid #2E7D5B"></i>متاح</span><span><i style="background:#F5A623"></i>مختار</span><span><i style="background:#e3e7eb"></i>محجوز</span></div>
  <div class="seatwrap"><div class="driver"><span>🚪 الباب</span><span>السائق 🧑‍✈️</span></div><div class="seats">${g}</div></div>
  <div class="sum"><div class="row between"><span>المقاعد</span><b id="sl">—</b></div><div class="row between"><span>الإجمالي</span><b class="price" id="tot">${money(0)}</b></div></div>
  <div style="height:14px"></div><button class="btn" id="nx" disabled>متابعة</button>`, 'home', 'اختيار المقعد');
  $app.querySelector('.seats').onclick = e => {
    const b = e.target.closest('.seat'); if (!b || b.disabled) return; const k = +b.dataset.n;
    if (sel.includes(k)) sel = sel.filter(x => x !== k); else { if (sel.length >= 6) return toast('الحد الأقصى 6 مقاعد'); sel.push(k); }
    b.classList.toggle('sel'); sel.sort((a, b) => a - b);
    document.getElementById('sl').textContent = sel.join('، ') || '—'; document.getElementById('tot').textContent = money(sel.length * trip.price); document.getElementById('nx').disabled = !sel.length;
  };
  document.getElementById('nx').onclick = () => { if (!need()) return; bookingDraft.trip = trip; bookingDraft.seats = sel; go('#/passenger'); };
}

function viewPassenger() {
  if (!need() || !bookingDraft.trip) return go('#/trips');
  const d = bookingDraft;
  shell(`<div class="card"><b>${esc(d.trip.from_city)} ← ${esc(d.trip.to_city)}</b><div class="mut">المقاعد: ${d.seats.join('، ')} · ${money(d.seats.length * d.trip.price)}</div></div>
  <div id="msg"></div><label>اسم المسافر</label><input id="pn" value="${esc(user.full_name||'')}"><label>رقم الهاتف</label><input id="pp" type="tel" dir="ltr" value="${esc(user.phone||'')}">
  <label>رقم الهوية / الجواز (اختياري)</label><input id="pi" dir="ltr"><div style="height:16px"></div><button class="btn" id="go">تأكيد الحجز</button>`, 'home', 'بيانات المسافر');
  document.getElementById('go').onclick = async e => {
    if (!val('pn') || !val('pp')) return toast('الاسم والهاتف مطلوبان');
    busy(e.target, true);
    const { data, error } = await sb.rpc('create_booking', { p_trip: d.trip.id, p_seats: d.seats, p_name: val('pn'), p_phone: val('pp'), p_id_no: val('pi') || null });
    busy(e.target, false); if (error) { toast(errMsg(error)); if (error.message === 'seat_taken') go('#/seats/' + d.trip.id); return; }
    delete bookingDraft.trip; go('#/booking/' + data.id);
  };
}

async function viewBooking(id) {
  if (!need()) return; loading();
  const { data: b } = await sb.from('bookings').select('*, trips(*)').eq('id', id).single();
  if (!b) return shell('<div class="empty">الحجز غير موجود</div>', 'orders', 'التذكرة');
  const { data: pay } = await sb.from('app_settings').select('value').eq('key', 'payment_info').maybeSingle();
  const t = b.trips;
  shell(`<div class="ticket"><div class="h"><div class="row between"><b>تذكرة سفر</b>${badge(b.status)}</div><div class="route" style="margin-top:8px">${esc(t.from_city)} <i>←</i> ${esc(t.to_city)}</div></div>
  <div class="b"><div class="kv"><span>رقم الحجز</span><b dir="ltr">${esc(b.ref_no)}</b></div><div class="kv"><span>المسافر</span><b>${esc(b.passenger_name)}</b></div>
  <div class="kv"><span>الموعد</span><b>${dt(t.depart_at)}</b></div><div class="kv"><span>المقاعد</span><b>${b.seats.join('، ')}</b></div><div class="kv"><span>الإجمالي</span><b class="price">${money(b.total)}</b></div></div></div>
  ${b.status==='pending'?`<h3 class="sec">إثبات الدفع</h3><div class="note">${esc(pay?.value||'')}</div><label>صورة إشعار الدفع</label><input type="file" id="fl" accept="image/*,application/pdf"><div style="height:12px"></div><button class="btn acc" id="up">رفع إثبات الدفع</button><div style="height:10px"></div><button class="btn ghost" id="cn">إلغاء الحجز</button>`
  : b.status==='payment_review'?'<div class="note">تم استلام إثبات الدفع وهو قيد المراجعة. سنُعلمك فور التأكيد.</div>':''}`, 'orders', 'تفاصيل الحجز');
  const up = document.getElementById('up');
  if (up) up.onclick = async () => {
    const f = document.getElementById('fl').files[0]; if (!f) return toast('اختر ملفاً أولاً'); if (f.size > 5 * 1024 * 1024) return toast('الحجم الأقصى 5 ميغابايت');
    busy(up, true);
    const path = `${user.id}/${b.id}-${Date.now()}.${(f.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '')}`;
    const u = await sb.storage.from('payment-proofs').upload(path, f, { contentType: f.type });
    if (u.error) { busy(up, false); return toast(u.error.message); }
    const r = await sb.rpc('submit_payment_proof', { p_booking: b.id, p_path: path });
    if (r.error) { busy(up, false); return toast(errMsg(r.error)); }
    toast('تم رفع الإثبات'); viewBooking(id);
  };
  const cn = document.getElementById('cn');
  if (cn) cn.onclick = async () => { if (!confirm('إلغاء هذا الحجز؟')) return; const r = await sb.rpc('cancel_booking', { p_booking: b.id }); if (r.error) return toast(errMsg(r.error)); toast('تم الإلغاء'); viewBooking(id); };
}

/* ---------- الإرساليات ---------- */
function viewShipNew() {
  if (!need()) return;
  shell(`<div id="msg"></div><h3 class="sec" style="margin-top:0">المرسل</h3><label>الاسم</label><input id="sn" value="${esc(user.full_name||'')}"><label>الهاتف</label><input id="sp" type="tel" dir="ltr" value="${esc(user.phone||'')}"><label>مكان الإرسال</label><input id="sf" placeholder="المدينة / الحي">
  <h3 class="sec">المستلم</h3><label>الاسم</label><input id="rn"><label>الهاتف</label><input id="rp" type="tel" dir="ltr"><label>مكان الاستلام</label><input id="rt" placeholder="المدينة / الحي">
  <h3 class="sec">الإرسالية</h3><label>الوزن (كجم)</label><input id="wk" type="number" min="0.5" step="0.5" value="1" inputmode="decimal"><label>الوصف</label><input id="ds">
  <div class="sum"><div class="row between"><span>التكلفة التقديرية</span><b class="price" id="cost">${money(4500)}</b></div><div class="mut">3,000 ج.س + 1,500 ج.س لكل كجم</div></div>
  <div style="height:14px"></div><button class="btn" id="go">تسجيل الإرسالية</button>`, 'home', 'إرسالية جديدة');
  const upd = () => document.getElementById('cost').textContent = money(3000 + 1500 * (+val('wk') || 0));
  document.getElementById('wk').oninput = upd;
  document.getElementById('go').onclick = async e => {
    const w = +val('wk'); if (!val('sn') || !val('sp') || !val('sf') || !val('rn') || !val('rp') || !val('rt') || !(w > 0)) return toast('أكمل جميع الحقول المطلوبة');
    busy(e.target, true);
    const { data, error } = await sb.from('shipments').insert({ sender_name: val('sn'), sender_phone: val('sp'), from_place: val('sf'), receiver_name: val('rn'), receiver_phone: val('rp'), to_place: val('rt'), weight_kg: w, description: val('ds') }).select().single();
    busy(e.target, false); if (error) return toast(errMsg(error)); toast('تم تسجيل الإرسالية'); go('#/ship/' + data.id);
  };
}
function viewShipTrack() {
  if (!need()) return;
  shell(`<div class="note">أدخل رقم التتبع الذي يبدأ بـ TRK لعرض حالة إرسالياتك.</div><label>رقم التتبع</label><input id="tn" dir="ltr" placeholder="TRK-XXXXXXX"><div style="height:14px"></div><button class="btn" id="go">بحث</button>`, 'home', 'تتبع إرسالية');
  document.getElementById('go').onclick = async () => {
    const { data } = await sb.from('shipments').select('id').eq('tracking_no', val('tn').toUpperCase()).maybeSingle();
    if (!data) return toast('لم يتم العثور على إرسالية بهذا الرقم'); go('#/ship/' + data.id);
  };
}
async function viewShip(id) {
  if (!need()) return; loading();
  const [s, e] = await Promise.all([sb.from('shipments').select('*').eq('id', id).single(), sb.from('shipment_events').select('*').eq('shipment_id', id).order('created_at')]);
  const sh = s.data; if (!sh) return shell('<div class="empty">الإرسالية غير موجودة</div>', 'orders', 'التتبع');
  const flow = ['received', 'in_transit', 'arrived', 'delivered'], idx = flow.indexOf(sh.status);
  const hist = Object.fromEntries((e.data || []).map(x => [x.status, x]));
  shell(`<div class="card"><div class="row between"><div><div class="mut">رقم التتبع</div><b dir="ltr" style="font-size:20px">${esc(sh.tracking_no)}</b></div>${badge(sh.status)}</div></div>
  <div class="card"><div class="route">${esc(sh.from_place)} <i>←</i> ${esc(sh.to_place)}</div><div class="kv"><span>المرسل</span><b>${esc(sh.sender_name)}</b></div><div class="kv"><span>المستلم</span><b>${esc(sh.receiver_name)}</b></div><div class="kv"><span>الوزن</span><b>${sh.weight_kg} كجم</b></div><div class="kv"><span>التكلفة</span><b class="price">${money(sh.cost)}</b></div></div>
  <h3 class="sec">حالة الإرسالية</h3><div class="card"><div class="tl">${flow.map((k, i) => `<div class="st ${i < idx || sh.status==='delivered' && i===idx ? 'done' : i === idx ? 'now' : ''}"><b>${ST[k][0]}</b><small>${hist[k] ? dt(hist[k].created_at) : 'بانتظار التحديث'}</small></div>`).join('')}</div></div>
  ${sh.lat && sh.lng ? `<h3 class="sec">الموقع الحالي</h3><iframe class="map" loading="lazy" src="https://www.openstreetmap.org/export/embed.html?bbox=${sh.lng-.05},${sh.lat-.03},${+sh.lng+.05},${+sh.lat+.03}&marker=${sh.lat},${sh.lng}"></iframe>` : '<div class="note">تظهر الخريطة هنا عند توفر موقع الإرسالية.</div>'}`, 'orders', 'متابعة الإرسالية');
}

/* ---------- العقارات ---------- */
async function viewProps() {
  loading();
  const { data } = await sb.from('properties').select('*').eq('active', true).order('created_at', { ascending: false });
  let f = 'all';
  const draw = () => shell(`<div class="chips">${[['all','الكل'],['sale','بيع'],['rent','إيجار']].map(c=>`<button class="chip ${f===c[0]?'on':''}" data-f="${c[0]}">${c[1]}</button>`).join('')}</div>
  ${(data||[]).filter(p=>f==='all'||p.listing===f).map(p=>`<a class="card prop" href="#/prop/${p.id}">${p.image_url?`<img src="${esc(p.image_url)}" alt="" loading="lazy">`:'<div class="ph"></div>'}<div class="row between"><b>${esc(p.title)}</b><span class="badge ${p.listing==='sale'?'info':'ok'}">${p.listing==='sale'?'بيع':'إيجار'}</span></div>
  <div class="mut">📍 ${esc(p.city)}${p.area?' - '+esc(p.area):''}</div><div style="margin:8px 0"><span class="pill">${esc(p.kind)}</span>${p.rooms?`<span class="pill">🛏 ${p.rooms}</span>`:''}${p.size_m2?`<span class="pill">${p.size_m2} م²</span>`:''}</div><div class="price" style="font-size:18px">${money(p.price)}${p.listing==='rent'?' / شهر':''}</div></a>`).join('') || '<div class="empty"><div class="big">🏠</div>لا توجد عقارات</div>'}`, 'home', 'العقارات');
  draw(); $app.onclick = e => { const c = e.target.closest('.chip'); if (c) { f = c.dataset.f; draw(); } };
}
async function viewProp(id) {
  loading();
  const { data: p } = await sb.from('properties').select('*').eq('id', id).single();
  if (!p) return shell('<div class="empty">العقار غير موجود</div>', 'home', 'العقار');
  shell(`<div class="card prop">${p.image_url?`<img src="${esc(p.image_url)}" alt="">`:'<div class="ph"></div>'}<h2 style="margin:0 0 6px">${esc(p.title)}</h2><div class="price" style="font-size:20px">${money(p.price)}${p.listing==='rent'?' / شهر':''}</div></div>
  <div class="card"><div class="kv"><span>النوع</span><b>${esc(p.kind)}</b></div><div class="kv"><span>الموقع</span><b>${esc(p.city)}${p.area?' - '+esc(p.area):''}</b></div><div class="kv"><span>الغرف</span><b>${p.rooms??'—'}</b></div><div class="kv"><span>الحمامات</span><b>${p.baths??'—'}</b></div><div class="kv"><span>المساحة</span><b>${p.size_m2?p.size_m2+' م²':'—'}</b></div></div>
  <div class="card"><b>التفاصيل</b><p class="mut" style="line-height:1.8">${esc(p.details)}</p></div>
  <div style="display:grid;gap:10px"><button class="btn" id="vw">طلب معاينة</button><button class="btn ghost" id="bk">طلب حجز</button></div>`, 'home', 'تفاصيل العقار');
  const send = kind => async e => {
    if (!need()) return; const ph = prompt('رقم هاتفك للتواصل:', user.phone || ''); if (!ph) return; busy(e.target, true);
    const { error } = await sb.from('property_requests').insert({ property_id: p.id, kind, phone: ph.trim() }); busy(e.target, false);
    if (error) return toast(errMsg(error)); toast('تم إرسال طلبك'); go('#/orders');
  };
  document.getElementById('vw').onclick = send('viewing'); document.getElementById('bk').onclick = send('booking');
}

/* ---------- التحويلات ---------- */
function viewTransfer() {
  if (!need()) return;
  let kind = 'domestic';
  const CUR = { 'السودان': 'SDG', 'مصر': 'EGP', 'السعودية': 'SAR', 'الإمارات': 'AED', 'قطر': 'QAR', 'تركيا': 'TRY', 'أمريكا': 'USD' };
  shell(`<div class="tabs"><button id="k1" class="on">تحويل داخلي</button><button id="k2">تحويل خارجي</button></div>
  <label>الدولة</label><select id="co">${Object.keys(CUR).map(c=>`<option>${c}</option>`).join('')}</select><label>العملة</label><input id="cu" value="SDG" readonly dir="ltr">
  <label>اسم المرسل</label><input id="sn" value="${esc(user.full_name||'')}"><label>اسم المستلم</label><input id="rn"><label>هاتف المستلم</label><input id="rp" type="tel" dir="ltr">
  <label>المبلغ</label><input id="am" type="number" min="1" inputmode="decimal"><label>ملاحظة</label><input id="nt">
  <div class="sum"><div class="row between"><span>الرسوم (2% بحد أدنى 500)</span><b id="fee">—</b></div><div class="row between"><span>الإجمالي</span><b class="price" id="tt">—</b></div></div>
  <div style="height:14px"></div><button class="btn" id="go">إرسال التحويل</button>`, 'home', 'تحويل مالي');
  const calc = () => { const a = +val('am') || 0, f = a ? Math.max(Math.round(a * .02), 500) : 0; document.getElementById('fee').textContent = a ? money(f) : '—'; document.getElementById('tt').textContent = a ? money(a + f) : '—'; };
  const setK = k => { kind = k; document.getElementById('k1').classList.toggle('on', k==='domestic'); document.getElementById('k2').classList.toggle('on', k==='international'); if (k==='domestic') { document.getElementById('co').value='السودان'; document.getElementById('cu').value='SDG'; } };
  document.getElementById('k1').onclick = () => setK('domestic'); document.getElementById('k2').onclick = () => setK('international');
  document.getElementById('co').onchange = e => document.getElementById('cu').value = CUR[e.target.value];
  document.getElementById('am').oninput = calc;
  document.getElementById('go').onclick = async e => {
    const a = +val('am'); if (!val('sn') || !val('rn') || !val('rp') || !(a > 0)) return toast('أكمل الحقول المطلوبة');
    busy(e.target, true);
    const { data, error } = await sb.from('transfers').insert({ kind, country: val('co'), currency: val('cu'), amount: a, sender_name: val('sn'), receiver_name: val('rn'), receiver_phone: val('rp'), note: val('nt') }).select().single();
    busy(e.target, false); if (error) return toast(errMsg(error)); toast('تم إرسال طلب التحويل'); go('#/transfer/' + data.id);
  };
}
async function viewTransferDetail(id) {
  if (!need()) return; loading();
  const { data: t } = await sb.from('transfers').select('*').eq('id', id).single();
  if (!t) return shell('<div class="empty">غير موجود</div>', 'orders', 'التحويل');
  const flow = ['pending', 'processing', 'completed'], idx = Math.max(0, flow.indexOf(t.status));
  shell(`<div class="card"><div class="row between"><b dir="ltr">${esc(t.ref_no)}</b>${badge(t.status)}</div></div>
  <div class="card"><div class="kv"><span>النوع</span><b>${t.kind==='domestic'?'داخلي':'خارجي'}</b></div><div class="kv"><span>الدولة / العملة</span><b>${esc(t.country)} · ${esc(t.currency)}</b></div><div class="kv"><span>المستلم</span><b>${esc(t.receiver_name)}</b></div><div class="kv"><span>المبلغ</span><b>${Number(t.amount).toLocaleString('ar-EG')}</b></div><div class="kv"><span>الرسوم</span><b>${Number(t.fee).toLocaleString('ar-EG')}</b></div><div class="kv"><span>الإجمالي</span><b class="price">${Number(t.total).toLocaleString('ar-EG')} ${esc(t.currency)}</b></div></div>
  <h3 class="sec">متابعة الحالة</h3><div class="card"><div class="tl">${flow.map((k,i)=>`<div class="st ${t.status==='completed'||i<idx?'done':i===idx&&!['rejected','cancelled'].includes(t.status)?'now':''}"><b>${ST[k][0]}</b></div>`).join('')}</div>${['rejected','cancelled'].includes(t.status)?badge(t.status):''}</div>`, 'orders', 'حالة التحويل');
}

/* ---------- الموافقات الأمنية ---------- */
async function viewSecurityNew() {
  if (!need()) return;
  const { data } = await sb.from('services').select('name').eq('office_slug', 'security').eq('active', true).order('sort');
  shell(`<label>الخدمة</label><select id="sv">${(data||[]).map(x=>`<option>${esc(x.name)}</option>`).join('')}</select><label>الاسم الكامل</label><input id="fn" value="${esc(user.full_name||'')}"><label>الهاتف</label><input id="ph" type="tel" dir="ltr" value="${esc(user.phone||'')}">
  <label>رقم الهوية / الجواز</label><input id="idn" dir="ltr"><label>ملاحظات</label><textarea id="nt"></textarea><label>المستندات (صور أو PDF، حتى 5 ملفات)</label><input type="file" id="fl" multiple accept="image/*,application/pdf">
  <div style="height:16px"></div><button class="btn" id="go">إرسال الطلب</button>`, 'home', 'طلب موافقة أمنية');
  document.getElementById('go').onclick = async e => {
    if (!val('fn') || !val('ph')) return toast('الاسم والهاتف مطلوبان');
    const files = [...document.getElementById('fl').files].slice(0, 5); if (files.some(f => f.size > 5 * 1024 * 1024)) return toast('الحد الأقصى لكل ملف 5 ميغابايت');
    busy(e.target, true); const paths = [];
    for (const f of files) { const p = `${user.id}/${Date.now()}-${paths.length}.${(f.name.split('.').pop()||'jpg').toLowerCase().replace(/[^a-z0-9]/g,'')}`; const u = await sb.storage.from('documents').upload(p, f, { contentType: f.type }); if (u.error) { busy(e.target, false); return toast(u.error.message); } paths.push(p); }
    const { data, error } = await sb.from('security_requests').insert({ service: val('sv'), full_name: val('fn'), phone: val('ph'), id_no: val('idn') || null, notes: val('nt'), docs: paths }).select().single();
    busy(e.target, false); if (error) return toast(errMsg(error)); toast('تم إرسال الطلب'); go('#/security/' + data.id);
  };
}
async function viewSecurity(id) {
  if (!need()) return; loading();
  const { data: r } = await sb.from('security_requests').select('*').eq('id', id).single();
  if (!r) return shell('<div class="empty">غير موجود</div>', 'orders', 'الطلب');
  const flow = ['pending', 'processing', 'approved'], idx = Math.max(0, flow.indexOf(r.status));
  shell(`<div class="card"><div class="mut">رقم الطلب</div><div class="row between"><b dir="ltr" style="font-size:20px">${esc(r.ref_no)}</b>${badge(r.status)}</div></div>
  <div class="card"><div class="kv"><span>الخدمة</span><b>${esc(r.service)}</b></div><div class="kv"><span>مقدم الطلب</span><b>${esc(r.full_name)}</b></div><div class="kv"><span>المستندات</span><b>${r.docs.length} ملف</b></div><div class="kv"><span>التاريخ</span><b>${dt(r.created_at)}</b></div></div>
  <h3 class="sec">متابعة الطلب</h3><div class="card"><div class="tl">${flow.map((k,i)=>`<div class="st ${r.status==='approved'||i<idx?'done':i===idx&&r.status!=='rejected'?'now':''}"><b>${ST[k][0]}</b></div>`).join('')}</div>${r.status==='rejected'?badge('rejected'):''}</div>`, 'orders', 'حالة الطلب');
}

/* ---------- طلباتي / إشعارات / حسابي ---------- */
async function viewOrders() {
  if (!need()) return; loading();
  const q = (t, s) => sb.from(t).select(s).order('created_at', { ascending: false }).limit(30);
  const [b, s, t, c, p, r] = await Promise.all([q('bookings', 'id,ref_no,status,created_at,total,trips(from_city,to_city)'), q('shipments', 'id,tracking_no,status,created_at,to_place'), q('transfers', 'id,ref_no,status,created_at,amount,currency'), q('security_requests', 'id,ref_no,status,created_at,service'), q('property_requests', 'id,ref_no,status,created_at,kind'), q('service_requests', 'id,ref_no,status,created_at,service_name')]);
  const all = [
    ...(b.data||[]).map(x => ({ ic:'🚌', t:`حجز ${x.trips.from_city} ← ${x.trips.to_city}`, ref:x.ref_no, st:x.status, d:x.created_at, h:'#/booking/'+x.id })),
    ...(s.data||[]).map(x => ({ ic:'📦', t:`إرسالية إلى ${x.to_place}`, ref:x.tracking_no, st:x.status, d:x.created_at, h:'#/ship/'+x.id })),
    ...(t.data||[]).map(x => ({ ic:'💸', t:`تحويل ${Number(x.amount).toLocaleString('ar-EG')} ${x.currency}`, ref:x.ref_no, st:x.status, d:x.created_at, h:'#/transfer/'+x.id })),
    ...(c.data||[]).map(x => ({ ic:'🛡️', t:x.service, ref:x.ref_no, st:x.status, d:x.created_at, h:'#/security/'+x.id })),
    ...(p.data||[]).map(x => ({ ic:'🏠', t:x.kind==='viewing'?'طلب معاينة عقار':'طلب حجز عقار', ref:x.ref_no, st:x.status, d:x.created_at, h:'#/orders' })),
    ...(r.data||[]).map(x => ({ ic:'🧾', t:x.service_name, ref:x.ref_no, st:x.status, d:x.created_at, h:'#/orders' }))
  ].sort((a, b) => new Date(b.d) - new Date(a.d));
  shell(all.map(x => `<a class="card row" href="${x.h}"><div style="font-size:28px">${x.ic}</div><div class="grow"><b>${esc(x.t)}</b><div class="mut" dir="ltr" style="text-align:right">${esc(x.ref)} · ${dt(x.d)}</div></div>${badge(x.st)}</a>`).join('') || '<div class="empty"><div class="big">📋</div>لا توجد طلبات بعد</div>', 'orders', 'طلباتي', false);
}
async function viewNotifs() {
  if (!need()) return; loading();
  const { data } = await sb.from('notifications').select('*').order('created_at', { ascending: false }).limit(50);
  shell((data||[]).map(n => `<div class="card notif ${n.read?'':'unread'}"><b>${esc(n.title)}</b><div class="mut">${esc(n.body)}</div><div class="mut" style="font-size:12px;margin-top:4px">${dt(n.created_at)}</div></div>`).join('') || '<div class="empty"><div class="big">🔔</div>لا توجد إشعارات</div>', 'notifs', 'الإشعارات', false);
  if ((data||[]).some(n => !n.read)) { await sb.from('notifications').update({ read: true }).eq('read', false); unread = 0; }
}
async function viewMe() {
  if (!need()) return;
  shell(`<div class="card"><div class="row"><div style="font-size:40px">👤</div><div><b>${esc(user.full_name||'مستخدم')}</b><div class="mut" dir="ltr" style="text-align:right">${esc(user.email)}</div></div></div></div>
  <label>الاسم</label><input id="fn" value="${esc(user.full_name||'')}"><label>الهاتف</label><input id="ph" type="tel" dir="ltr" value="${esc(user.phone||'')}"><label>المدينة</label><input id="ct" value="${esc(user.city||'')}">
  <div style="height:14px"></div><button class="btn" id="sv">حفظ</button><div style="height:10px"></div><button class="btn ghost" id="lo">تسجيل الخروج</button>`, 'me', 'حسابي', false);
  document.getElementById('sv').onclick = async () => { const { error } = await sb.from('profiles').update({ full_name: val('fn'), phone: val('ph'), city: val('ct') }).eq('id', user.id); if (error) return toast(errMsg(error)); Object.assign(user, { full_name: val('fn'), phone: val('ph'), city: val('ct') }); toast('تم الحفظ'); };
  document.getElementById('lo').onclick = () => sb.auth.signOut();
}

/* ---------- الموجّه ---------- */
async function route() {
  if (!sb) { $app.innerHTML = '<div class="auth"><div class="err">لم يتم ضبط اتصال Supabase. تأكد من إضافة الأسرار SUPABASE_URL و SUPABASE_ANON_KEY في المستودع ثم أعد النشر.</div></div>'; return; }
  const h = (location.hash || '#/').slice(1), [, a, b] = h.split('/');
  if (!user && !['auth', 'trips', 'seats', 'office', 'props', 'prop', ''].includes(a || '')) return go('#/auth');
  if (user && a === 'auth') return go('#/');
  const map = {
    '': () => viewHome(), auth: viewAuth, office: () => viewOffice(b), request: () => viewRequest(b),
    trips: viewTrips, seats: () => viewSeats(b), passenger: viewPassenger, booking: () => viewBooking(b),
    ship: () => b === 'new' ? viewShipNew() : b === 'track' ? viewShipTrack() : viewShip(b),
    props: viewProps, prop: () => viewProp(b),
    transfer: () => b === 'new' ? viewTransfer() : viewTransferDetail(b),
    security: () => b === 'new' ? viewSecurityNew() : viewSecurity(b),
    orders: viewOrders, notifs: viewNotifs, me: viewMe
  };
  $app.onclick = null;
  try { await (map[a || ''] || map[''])(); } catch (e) { console.error(e); toast('حدث خطأ غير متوقع'); }
}
async function loadUser(session) {
  if (!session) { user = null; unread = 0; return; }
  const [p, n] = await Promise.all([sb.from('profiles').select('*').eq('id', session.user.id).maybeSingle(), sb.from('notifications').select('id', { count: 'exact', head: true }).eq('read', false)]);
  user = { id: session.user.id, email: session.user.email, ...(p.data || {}) }; unread = n.count || 0;
}
async function boot() {
  if (sb) {
    const { data } = await sb.auth.getSession(); await loadUser(data.session);
    sb.auth.onAuthStateChange(async (ev, s) => { if (ev === 'INITIAL_SESSION') return; await loadUser(s); if (ev === 'SIGNED_OUT') go('#/'); route(); });
  }
  window.addEventListener('hashchange', route);
  await route();
  setTimeout(() => document.getElementById('splash').classList.add('hide'), 700);
}
boot();
})();
