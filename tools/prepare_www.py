#!/usr/bin/env python3
"""يجهّز مجلد www لبناء APK: ينسخ الملفات، يكتب مفاتيح Supabase، ويضمّن مكتبة Supabase والخط العربي داخل التطبيق
(بدل تحميلهما من الإنترنت في كل فتح). أي مكوّن ناقص يُترك على النسخة الأونلاين ولا يفشل البناء."""
import json, os, re, shutil, sys

url, key = os.environ.get('SUPABASE_URL', ''), os.environ.get('SUPABASE_ANON_KEY', '')
if not url or not key:
    sys.exit('::error::SUPABASE_URL / SUPABASE_ANON_KEY secrets are missing')

shutil.rmtree('www', ignore_errors=True)
os.makedirs('www')
for d in ('css', 'js', 'assets'):
    shutil.copytree(d, f'www/{d}')
for f in ('index.html', 'manifest.webmanifest'):
    shutil.copy(f, f'www/{f}')
push = '1' if os.environ.get('PUSH_ENABLED') == '1' else ''
open('www/js/config.js', 'w', encoding='utf-8').write(
    f'window.ENV={{SUPABASE_URL:{json.dumps(url)},SUPABASE_ANON_KEY:{json.dumps(key)},PUSH:{json.dumps(push)}}};\n')

html = open('www/index.html', encoding='utf-8').read()

# 1) مكتبة Supabase محلية
CDN = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js'
src = 'node_modules/@supabase/supabase-js/dist/umd/supabase.js'
if os.path.exists(src) and CDN in html:
    shutil.copy(src, 'www/js/supabase.js')
    html = html.replace(CDN, 'js/supabase.js')
    print('bundled: supabase-js')
else:
    print('WARNING: supabase-js not bundled, keeping CDN link')

# 2) الخط العربي محلياً
ARABIC = 'U+0600-06FF,U+200C-200E,U+2010-2011,U+204F,U+2E41,U+FB50-FDFF,U+FE80-FEFC'
LATIN = 'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD'
faces, n = [], 0
os.makedirs('www/fonts', exist_ok=True)
for w in (400, 500, 700, 800):
    for sub, rng in (('arabic', ARABIC), ('latin', LATIN)):
        f = f'node_modules/@fontsource/tajawal/files/tajawal-{sub}-{w}-normal.woff2'
        if os.path.exists(f):
            shutil.copy(f, f'www/fonts/tajawal-{sub}-{w}.woff2')
            faces.append(f"@font-face{{font-family:'Tajawal';font-style:normal;font-weight:{w};font-display:swap;"
                         f"src:url(../fonts/tajawal-{sub}-{w}.woff2) format('woff2');unicode-range:{rng}}}")
            n += 1
if n:
    open('www/css/fonts.css', 'w', encoding='utf-8').write('\n'.join(faces) + '\n')
    html = re.sub(r'\s*<link rel="preconnect" href="https://fonts\.googleapis\.com">', '', html)
    html = re.sub(r'\s*<link href="https://fonts\.googleapis\.com/css2[^>]*>', '', html)
    html = html.replace('<link rel="stylesheet" href="css/style.css">',
                        '<link rel="stylesheet" href="css/fonts.css">\n<link rel="stylesheet" href="css/style.css">')
    print(f'bundled: {n} font files')
else:
    print('WARNING: Tajawal font files not found, keeping Google Fonts link')

open('www/index.html', 'w', encoding='utf-8').write(html)
