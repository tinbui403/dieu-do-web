"""Build index.html (bản chạy thật) và test.html (bản thử với dữ liệu giả).
Cách dùng:  python build.py
- index.html : app.src.html + thư viện supabase-js (vendor/supabase.js) nhúng sẵn
- test.html  : app.src.html + mock.js + tests/fixtures.json (không cần mạng)
"""
import os, sys
H = os.path.dirname(os.path.abspath(__file__))
P = '<script>/*__SUPABASE_UMD__*/</script>'
def rd(*p): return open(os.path.join(H, *p), encoding='utf-8').read()
src = rd('src', 'app.src.html')
assert P in src, 'thiếu chỗ nhúng thư viện trong app.src.html'
src = src.replace('<!-- MÃ NGUỒN: sửa file này rồi chạy `python build.py` để tạo index.html. Đừng sửa trực tiếp index.html. -->', '<!-- FILE TẠO TỰ ĐỘNG từ src/app.src.html bằng build.py — đừng sửa trực tiếp file này. -->')
umd = rd('vendor', 'supabase.js').replace('</script', '<\\/script')
open(os.path.join(H, 'index.html'), 'w', encoding='utf-8').write(src.replace(P, '<script>' + umd + '</script>'))
print('index.html OK')
fx = os.path.join(H, 'tests', 'fixtures.json')
if os.path.exists(fx):
    t = src.replace(P, '<script>window.__FX=' + rd('tests', 'fixtures.json') + ';\n</script><script>' + rd('tests', 'mock.js') + '</script>')
    open(os.path.join(H, 'tests', 'test.html'), 'w', encoding='utf-8').write(t)
    print('tests/test.html OK')
