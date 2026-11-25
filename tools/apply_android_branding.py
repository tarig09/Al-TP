#!/usr/bin/env python3
"""يطبّق أيقونة التطبيق وشاشة البداية الأصلية على مشروع أندرويد المُولَّد (بعد: npx cap add android)."""
import glob, os, shutil, sys

res = 'android/app/src/main/res'
if not os.path.isdir(res):
    sys.exit('::error::android res folder not found; run `npx cap add android` first')
for f in glob.glob(f'{res}/drawable*/splash.png') + glob.glob(f'{res}/mipmap-*/ic_launcher*.png') + glob.glob(f'{res}/mipmap-*/ic_launcher*.webp'):
    os.remove(f)
shutil.copytree('resources/android/res', res, dirs_exist_ok=True)
print('branding applied: icons + splash')
