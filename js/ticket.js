/* تصدير التذكرة: صورة PNG و PDF، وحفظها/مشاركتها (داخل APK عبر Filesystem + Share، وعلى المتصفح كتنزيل) */
(() => {
const X = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[c]));
let fontCss = null;
async function loadFonts() {
  if (fontCss !== null) return fontCss;
  fontCss = '';
  try {
    const b64 = async f => { const r = await fetch(f); if (!r.ok) throw 0; const buf = new Uint8Array(await r.arrayBuffer()); let s = ''; for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000)); return btoa(s); };
    const faces = [];
    for (const [w, sub] of [[400, 'arabic'], [700, 'arabic'], [400, 'latin'], [700, 'latin']])
      faces.push(`@font-face{font-family:'TjT';font-weight:${w};src:url(data:font/woff2;base64,${await b64(`fonts/tajawal-${sub}-${w}.woff2`)}) format('woff2');unicode-range:${sub === 'arabic' ? 'U+0600-06FF,U+FB50-FDFF,U+FE80-FEFC' : 'U+0000-00FF,U+2000-206F'}}`);
    fontCss = faces.join('');
  } catch (_) { fontCss = ''; }
  return fontCss;
}

/* d: {title, agency, route, rows:[[label,value]], qr (svg string), ref, foot} */
async function svg(d) {
  const W = 760, rowH = 64, top = 330, rows = d.rows || [];
  const qrY = top + rows.length * rowH + 50, H = qrY + 450;
  const css = await loadFonts();
  const qr = (d.qr || '').replace(/<svg[^>]*>/, m => m.replace(/width="\d+"/, 'width="300"').replace(/height="\d+"/, 'height="300"').replace('<svg', `<svg x="${(W - 300) / 2}" y="${qrY}"`));
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" direction="rtl">
<defs><style>${css}text{font-family:'TjT','Tajawal','Noto Naskh Arabic','Droid Arabic Naskh',sans-serif}</style><clipPath id="cp"><rect x="20" y="20" width="${W - 40}" height="${H - 40}" rx="30"/></clipPath></defs>
<rect width="${W}" height="${H}" fill="#F3F5F8"/>
<g clip-path="url(#cp)"><rect x="20" y="20" width="${W - 40}" height="${H - 40}" fill="#fff"/>
<rect x="20" y="20" width="${W - 40}" height="230" fill="#0B4F6C"/><rect x="20" y="238" width="${W - 40}" height="12" fill="#F5A623"/></g>
<text x="${W - 56}" y="96" font-size="38" font-weight="700" fill="#fff" text-anchor="start">${X(d.title)}</text>
<text x="56" y="92" font-size="20" fill="#fff" opacity=".75" text-anchor="start" direction="ltr">AL-MAHATTA</text>
<text x="${W - 56}" y="144" font-size="24" fill="#bfe3f2" text-anchor="start">${X(d.agency || '')}</text>
<text x="${W / 2}" y="212" font-size="34" font-weight="700" fill="#fff" text-anchor="middle">${X(d.route || '')}</text>
${rows.map((r, i) => { const y = top + i * rowH; return `<text x="${W - 56}" y="${y}" font-size="22" fill="#6B7A86" text-anchor="start">${X(r[0])}</text><text x="56" y="${y}" font-size="25" font-weight="700" fill="#16222B" text-anchor="end">${X(r[1])}</text><line x1="56" x2="${W - 56}" y1="${y + 22}" y2="${y + 22}" stroke="#E3E8ED"/>`; }).join('')}
<line x1="40" x2="${W - 40}" y1="${qrY - 24}" y2="${qrY - 24}" stroke="#C9D2D9" stroke-width="2" stroke-dasharray="10 8"/>
${qr}
<text x="${W / 2}" y="${qrY + 350}" font-size="30" font-weight="700" fill="#0B4F6C" text-anchor="middle" direction="ltr" letter-spacing="2">${X(d.ref)}</text>
<text x="${W / 2}" y="${qrY + 384}" font-size="19" fill="#6B7A86" text-anchor="middle">${X(d.foot || '')}</text></svg>`;
}

async function canvas(d) {
  const s = await svg(d), img = new Image();
  await new Promise((ok, no) => { img.onload = ok; img.onerror = () => no(new Error('render')); img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(s); });
  const k = 2, c = document.createElement('canvas'); c.width = img.width * k; c.height = img.height * k;
  const g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height); g.drawImage(img, 0, 0, c.width, c.height);
  return c;
}
const toBlob = (c, type, q) => new Promise(r => c.toBlob(r, type, q));

async function png(d) { return toBlob(await canvas(d), 'image/png'); }

/* PDF من صفحة واحدة تحتوي صورة JPEG */
async function pdf(d) {
  const c = await canvas(d), jpg = new Uint8Array(await (await toBlob(c, 'image/jpeg', .92)).arrayBuffer());
  const pw = 420, ph = Math.round(pw * c.height / c.width), enc = new TextEncoder(), parts = [], off = [];
  let len = 0; const add = b => { if (typeof b === 'string') b = enc.encode(b); parts.push(b); len += b.length; };
  const obj = (n, body) => { off[n] = len; add(`${n} 0 obj\n`); add(body); add('\nendobj\n'); };
  add('%PDF-1.4\n');
  obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  obj(3, `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pw} ${ph}] /Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>`);
  const cs = `q ${pw} 0 0 ${ph} 0 0 cm /Im0 Do Q`;
  obj(4, `<< /Length ${cs.length} >>\nstream\n${cs}\nendstream`);
  off[5] = len; add(`5 0 obj\n<< /Type /XObject /Subtype /Image /Width ${c.width} /Height ${c.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpg.length} >>\nstream\n`); add(jpg); add('\nendstream\nendobj\n');
  const xr = len; add(`xref\n0 6\n0000000000 65535 f \n${[1, 2, 3, 4, 5].map(n => String(off[n]).padStart(10, '0') + ' 00000 n \n').join('')}trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xr}\n%%EOF`);
  return new Blob(parts, { type: 'application/pdf' });
}

const b64 = blob => new Promise(r => { const f = new FileReader(); f.onload = () => r(String(f.result).split(',')[1]); f.readAsDataURL(blob); });
/* حفظ/مشاركة: داخل التطبيق تُفتح قائمة المشاركة (حفظ في الجهاز، واتساب، Drive…)، وعلى المتصفح تنزيل مباشر */
async function save(blob, name, title) {
  const cap = window.Capacitor, P = cap && cap.Plugins;
  if (cap && cap.isNativePlatform && cap.isNativePlatform() && P && P.Filesystem && P.Share) {
    const w = await P.Filesystem.writeFile({ path: name, data: await b64(blob), directory: 'CACHE' });
    await P.Share.share({ title: title || name, url: w.uri, dialogTitle: 'حفظ أو مشاركة التذكرة' });
    return 'shared';
  }
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 4000);
  return 'downloaded';
}
window.TicketExport = { svg, png, pdf, save };
})();
