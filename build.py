"""Build index.html (bản chạy thật) và test.html (bản thử với dữ liệu giả).
Cách dùng:  python build.py
- index.html : app.src.html + thư viện supabase-js (vendor/supabase.js) + kiem_dich_wizard.js NHÚNG SẴN (tự chứa)
- test.html  : app.src.html + mock.js + tests/fixtures.json (không cần mạng)
"""
import os, sys
H = os.path.dirname(os.path.abspath(__file__))
P = '<script>/*__SUPABASE_UMD__*/</script>'
WZ = '<script src="kiem_dich_wizard.js"></script>'
def rd(*p): return open(os.path.join(H, *p), encoding='utf-8').read()
src = rd('src', 'app.src.html')
assert P in src, 'thiếu chỗ nhúng thư viện trong app.src.html'
src = src.replace('<!-- MÃ NGUỒN: sửa file này rồi chạy `python build.py` để tạo index.html. Đừng sửa trực tiếp index.html. -->', '<!-- FILE TẠO TỰ ĐỘNG từ src/app.src.html bằng build.py — đừng sửa trực tiếp file này. -->')
umd = rd('vendor', 'supabase.js').replace('</script', '<\\/script')
out = src.replace(P, '<script>' + umd + '</script>')
# NHÚNG wizard để index.html tự chứa (không phụ thuộc file ngoài)
if WZ in out:
    wiz = rd('src', 'kiem_dich_wizard.js').replace('</script', '<\\/script')
    out = out.replace(WZ, '<script>' + wiz + '</script>')
open(os.path.join(H, 'index.html'), 'w', encoding='utf-8').write(out)
print('index.html OK')
fx = os.path.join(H, 'tests', 'fixtures.json')
if os.path.exists(fx):
    t = src.replace(P, '<script>window.__FX=' + rd('tests', 'fixtures.json') + ';\n</script><script>' + rd('tests', 'mock.js') + '</script>')
    if WZ in t:
        wiz = rd('src', 'kiem_dich_wizard.js').replace('</script', '<\\/script')
        t = t.replace(WZ, '<script>' + wiz + '</script>')
    open(os.path.join(H, 'tests', 'test.html'), 'w', encoding='utf-8').write(t)
    print('tests/test.html OK')
