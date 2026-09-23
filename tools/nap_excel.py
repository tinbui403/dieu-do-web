#!/usr/bin/env python3
"""
Sinh SQL "nạp chồng" dữ liệu từ sổ Excel điều độ (sheet MỚI ĐIỀU ĐỘ + Kế hoạch Hạ - Kiểm Dịch) vào Supabase.
Luật (anh Hi chốt 24/09/2026): Excel là chuẩn — ô Excel có giá trị thì ghi đè, ô trống thì giữ DB;
cont nào app đã đi xa hơn Excel (trạng thái lớn hơn) thì giữ theo app; không xoá gì ngoài danh sách --xoa-lo.
Chỉ lấy lô CLS còn hiệu lực (CLS mail → CLS ePort → ETD − 1 ngày), lô đánh dấu "R" (rớt tàu) vẫn lấy.

Dùng:  python nap_excel.py "dư liệu hôm nay.xlsx" --ngay 24/09 --ra nap_24-09.sql [--thu] [--xoa-lo 611A] [--rot-tau 617,624]
Kết quả: file SQL 1 khối `do $$ … $$` (chạy trong Supabase SQL editor). --thu = chạy thử, cuối khối raise exception 'KET_QUA…' để rollback.
KHÔNG đưa file SQL sinh ra lên git (chứa dữ liệu thật).
"""
import argparse, datetime, json, re, sys, hashlib, difflib
import openpyxl
from model import read_dieu_do, read_kd, norm, s, d, ts, is_cont, VN

# ---------- ánh xạ tên Excel → danh mục trong DB ----------
# Đặt trong file anh_xa_ten.local.json cạnh script (KHÔNG đưa lên git vì chứa tên khách / kho / nhà xe thật).
# Dạng: {"KHACH": {"TÊN TRONG EXCEL (viết hoa)": "tên trong Danh mục"}, "KHO": {...}, "NHA_XE": {...}, "HANG_TAU": {...}, "CANG": {...}, "BAI": {...}}
import os
_AX = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'anh_xa_ten.local.json'), encoding='utf-8'))
KHACH, KHO, NHA_XE, HANG_TAU, CANG, BAI = (_AX.get(k, {}) for k in ['KHACH', 'KHO', 'NHA_XE', 'HANG_TAU', 'CANG', 'BAI'])

def up(x): return norm(x).upper()
def q(v):
    """literal SQL"""
    if v is None or v == '': return 'null'
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, datetime.datetime): return "'" + v.astimezone(VN).strftime('%Y-%m-%d %H:%M:%S+07') + "'"
    if isinstance(v, datetime.date): return "'" + v.isoformat() + "'"
    return "'" + str(v).replace("'", "''") + "'"

def khach_cua(x):
    k = up(x).replace('|', ' ').strip(); k = re.sub(r'\s+', ' ', k)
    return KHACH.get(k, norm(x))
def kho_cua(x):
    k = up(x).replace('|', ' ').replace('\n', ' '); k = re.sub(r'\s+', ' ', k).strip()
    return KHO.get(k, norm(x))
def nha_xe_cua(x):
    k = up(x); return NHA_XE.get(k, norm(x) or None)
def hang_cua(x):
    k = norm(x); return HANG_TAU.get(k, HANG_TAU.get(k.upper(), k.upper()))
def cang_cua(x):
    k = up(x).replace('|', ' '); k = re.sub(r'\s+', ' ', k).strip(); return CANG.get(k, norm(x))
def bai_cua(x):
    return BAI.get(up(x))

def gio_len_kho(v, nam):
    """cột 'Ngày cont lên kho (dự kiến)': ngày → 08:00; chữ 'sáng trước 8h 19/09' → giờ + ghi chú"""
    if v is None or v == '': return None, None
    if isinstance(v, datetime.datetime): return v.replace(hour=v.hour or 8, tzinfo=VN), None
    t = norm(v)
    m = re.search(r'(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?', t)
    if not m: return None, t
    dd, mm = int(m.group(1)), int(m.group(2))
    y = int(m.group(3)) if m.group(3) else nam
    if y < 100: y += 2000
    l = t.lower(); h = 8
    mh = re.search(r'(\d{1,2})\s*h', l)
    if mh and int(mh.group(1)) < 24: h = int(mh.group(1))
    elif 'trưa' in l: h = 11
    elif 'chiều' in l or '下午' in l: h = 13
    elif 'tối' in l or '晚上' in l: h = 18
    elif 'sáng' in l or '早上' in l: h = 7
    try: return datetime.datetime(y, mm, dd, h, 0, tzinfo=VN), t
    except ValueError: return None, t

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('excel'); ap.add_argument('--ngay', required=True, help='ngày dữ liệu dd/mm (mốc "đến kho hôm nay = Đang đóng hàng")')
    ap.add_argument('--moc', default='', help='mốc trạng thái dd/mm: đến kho đúng ngày = Đang đóng hàng, trước = Đầy chờ kéo (mặc định = --ngay)')
    ap.add_argument('--ra', required=True); ap.add_argument('--thu', action='store_true')
    ap.add_argument('--xoa-lo', default='', help='lô xoá hẳn khỏi app, cách nhau dấu phẩy')
    ap.add_argument('--rot-tau', default='', help='lô rớt tàu: giữ lại, cont về theo Excel, bỏ tích KD, CLS để trống')
    ap.add_argument('--doi-ma', default='', help='đổi mã lô cũ>mới, VD 613A>613,622>622A')
    ap.add_argument('--tu-dong', type=int, default=1250, help='chỉ xét từ dòng Excel này trở đi')
    ap.add_argument('--bay-gio', default='', help='mốc giờ xét CLS (ISO, mặc định giờ hiện tại)')
    a = ap.parse_args()
    dd, mm = [int(x) for x in a.ngay.split('/')]
    now = datetime.datetime.fromisoformat(a.bay_gio) if a.bay_gio else datetime.datetime.now(VN)
    nam = now.year
    md, mmo = [int(x) for x in (a.moc or a.ngay).split('/')]
    ngay_du_lieu = datetime.date(nam, mmo, md)         # mốc: đến kho đúng ngày này = Đang đóng hàng; trước đó = Đầy chờ kéo
    xoa = [x.strip() for x in a.xoa_lo.split(',') if x.strip()]
    rot = [x.strip() for x in a.rot_tau.split(',') if x.strip()]
    doi = [tuple(x.strip().split('>')) for x in a.doi_ma.split(',') if x.strip()]
    nhan = 'Excel %02d/%02d' % (dd, mm)

    wb = openpyxl.load_workbook(a.excel, data_only=True)
    rows = read_dieu_do(wb); kd = read_kd(wb)
    lots = {}
    for r in rows:
        if r['row'] < a.tu_dong: continue
        lo = norm(r['lo'])
        if lo: lots.setdefault(lo, []).append(r)
    # ---- lô: gộp thông tin 2 sheet ----
    LO = {}
    for lo, rs in lots.items():
        f = rs[0]; k = (kd.get(lo) or [{}])[-1]
        etd = k.get('etd_phai') or k.get('etd_trai') or d(f['etd'])
        cls_mail = k.get('cls_mail'); cls_ep = k.get('cls_eport_phai') or k.get('cls_eport_trai')
        cls_x = cls_mail or cls_ep or (datetime.datetime(etd.year, etd.month, etd.day, tzinfo=VN) - datetime.timedelta(days=1) if etd else None)
        xong = bool(k.get('kiem_dich')) and bool(k.get('thanh_ly'))
        chay = (cls_x is not None and cls_x >= now and not xong) or lo in rot or bool(k.get('rot'))
        dd_tau = norm(next((x['tau'] for x in rs if norm(x['tau'])), '')); k_tau = re.sub(r'\s+(spitc|ctl|cát lái)$', '', norm(k.get('tau', '')), flags=re.I)
        chuan = lambda t: re.sub(r'[^A-Z0-9]', '', t.upper())
        giong = (not k_tau or not dd_tau or 'CONT' in dd_tau.upper() or chuan(k_tau) == chuan(dd_tau) or chuan(k_tau) in chuan(dd_tau) or chuan(dd_tau) in chuan(k_tau)
                 or difflib.SequenceMatcher(None, chuan(k_tau), chuan(dd_tau)).ratio() > 0.85)
        xep_lai = (bool(k_tau) and not giong) \
                  or (not k_tau and (k.get('etd_phai') or k.get('etd_trai')) and d(f['etd']) and (k.get('etd_phai') or k.get('etd_trai')) != d(f['etd']))
        ghi_chu = ('%s: xếp lại tàu theo sheet KD (Điều độ: %s ETD %s → KD: %s ETD %s) — kiểm tra booking / tàu' % (nhan, dd_tau or '-', d(f['etd']) or '-', k_tau or '-', etd or '-')) if xep_lai else None
        LO[lo] = dict(lo=lo, ghi_chu=ghi_chu, booking=norm(f['booking']) or None, hang_tau=hang_cua(f['hang_tau']) or None,
                      ten_tau=(re.sub(r'\s+(spitc|ctl|cát lái)$', '', (k.get('tau') or norm(next((x['tau'] for x in rs if norm(x['tau'])), ''))), flags=re.I) or None),
                      cang_den=cang_cua(f['cang_den']) or None, etd=etd, eta=d(f['eta']), etd_kho=d(f['dk_kho']),
                      closing_mail=cls_mail, closing_eport=cls_ep, closing_tay=(None if (cls_mail or cls_ep or not etd) else datetime.datetime(etd.year, etd.month, etd.day, tzinfo=VN) - datetime.timedelta(days=1)),
                      ma_don_kdtv=(k.get('kdtv') or None), da_khai_eport=bool(k.get('eport')), thanh_ly=bool(k.get('thanh_ly')),
                      so_luong=len(rs),
                      cont_kd=(k.get('cont_kd') if is_cont(k.get('cont_kd', '')) else None), rot=bool(k.get('rot')) or lo in rot,
                      cskh=norm(f['cskh']) or None, chay=chay, cls_x=cls_x, xong=xong, n=len(rs), kd_row=k.get('row'))
    scope = {lo for lo, v in LO.items() if v['chay']} - set(xoa)
    # ---- cont ----
    CONT = []
    for r in rows:
        if r['row'] < a.tu_dong: continue
        lo = norm(r['lo']); so = up(r['cont'])
        if not is_cont(so): continue
        if lo and lo not in scope: continue
        ht = norm(r['hien_trang']); bai = bai_cua(ht); den = d(r['ngay_den_kho'])
        if bai: st = '4'
        elif '登船' in ht or 'lên tàu' in ht.lower(): st = '6'
        elif den: st = '2' if den >= ngay_du_lieu else '3'
        else: st = '1'
        can_len, ghi = gio_len_kho(r['ngay_len_kho_dk'], nam)
        note = norm(r['note']); note = None if note.lower() in ('', 'x') else note
        CONT.append(dict(row=r['row'], lo=lo or None, so_cont=so, so_seal=norm(r['seal']) or None, ma_don=norm(r['ma_don']) or None,
                         khach=khach_cua(r['khach']) or None, kho=kho_cua(r['kho']) or None, kho_goc=norm(r['kho']) or None, hien_trang_goc=ht or None,
                         st=st, bai=bai, ngay_den_kho=den, ngay_goi=d(r['ngay_goi']), can_len=can_len, gio_ghi=ghi,
                         nha_xe=nha_xe_cua(r['nha_xe']), so_xe=norm(r['so_xe']) or None, tem=bool(r['tem']),
                         gio_vao=ts(r['gio_vao']) if r['gio_vao'] else None, gio_ra=ts(r['gio_ra']) if r['gio_ra'] else None,
                         gia=r['gia'] if isinstance(r['gia'], (int, float)) else None, phu_phi=r['phu_phi'] if isinstance(r['phu_phi'], (int, float)) else None,
                         phat_sinh=r['phat_sinh'] if isinstance(r['phat_sinh'], (int, float)) else None, note=note, cskh=norm(r['cskh']) or None))
    so_trung = [c for c in CONT if sum(1 for x in CONT if x['so_cont'] == c['so_cont']) > 1]
    if so_trung: sys.exit('Số cont trùng trong phạm vi nạp: ' + ', '.join(sorted({c['so_cont'] for c in so_trung})))

    # ---------- SQL ----------
    L = []
    w = L.append
    w("-- SINH TỰ ĐỘNG bởi tools/nap_excel.py — %s — mốc CLS %s — %s" % (nhan, now.strftime('%d/%m %H:%M'), 'CHẠY THỬ (rollback)' if a.thu else 'CHẠY THẬT'))
    w("-- Lô nạp: " + ', '.join(sorted(scope)) + " | xoá: " + (', '.join(xoa) or '-') + " | rớt tàu giữ: " + (', '.join(rot) or '-') + " | đổi mã: " + (', '.join(f'{x}>{y}' for x, y in doi) or '-'))
    w("do $$")
    w("declare v_n int; v_id text; v_st text; v_bai text; v_kd text; v_lo record; c record; x record; y record; v_bc text;")
    w("begin")
    w("  perform set_config('dieu_do.bo_qua_kiem_tra', 'on', true);")
    w("  drop table if exists _bao_cao; create temp table _bao_cao (tt serial, dong text);")
    w("  create temp table x_lo (lo text primary key, booking text, hang_tau text, ten_tau text, cang_den text, etd date, eta date, etd_kho date, closing_mail timestamptz, closing_eport timestamptz, closing_tay timestamptz, ma_don_kdtv text, da_khai_eport boolean, thanh_ly boolean, so_luong int, cont_kd text, rot boolean, cskh text, ghi_chu text) on commit drop;")
    w("  create temp table x_cont (row int, lo text, so_cont text, so_seal text, ma_don text, khach text, kho text, kho_goc text, hien_trang_goc text, st text, bai text, ngay_den_kho date, ngay_goi date, can_len timestamptz, gio_ghi text, nha_xe text, so_xe text, tem boolean, gio_vao timestamptz, gio_ra timestamptz, gia numeric, phu_phi numeric, phat_sinh numeric, note text, cskh text) on commit drop;")
    for lo in sorted(scope):
        v = LO[lo]
        w("  insert into x_lo values (%s);" % ', '.join(q(v[k]) for k in ['lo','booking','hang_tau','ten_tau','cang_den','etd','eta','etd_kho','closing_mail','closing_eport','closing_tay','ma_don_kdtv','da_khai_eport','thanh_ly','so_luong','cont_kd','rot','cskh','ghi_chu']))
    for c in CONT:
        w("  insert into x_cont values (%s);" % ', '.join(q(c[k]) for k in ['row','lo','so_cont','so_seal','ma_don','khach','kho','kho_goc','hien_trang_goc','st','bai','ngay_den_kho','ngay_goi','can_len','gio_ghi','nha_xe','so_xe','tem','gio_vao','gio_ra','gia','phu_phi','phat_sinh','note','cskh']))
    w("""
  -- 0. Danh mục thiếu → thêm (báo cáo)
  for x in select distinct khach as ten from x_cont where khach is not null and khach not in (select ten from public.khach_hang) loop
    insert into public.khach_hang (ten) values (x.ten); insert into _bao_cao (dong) values ('DANH MỤC: thêm khách hàng ' || x.ten); end loop;
  for x in select distinct kho as ten, khach from x_cont where kho is not null and kho not in (select ten from public.kho) loop
    insert into public.kho (ten, khach_hang_chinh) values (x.ten, x.khach); insert into _bao_cao (dong) values ('DANH MỤC: thêm kho ' || x.ten); end loop;
  for x in select distinct nha_xe as ma from x_cont where nha_xe is not null and nha_xe not in (select ma from public.nha_xe) loop
    insert into public.nha_xe (ma, ten_day_du) values (x.ma, x.ma); insert into _bao_cao (dong) values ('DANH MỤC: thêm nhà xe ' || x.ma); end loop;
  for x in select distinct hang_tau as ma from x_lo where hang_tau is not null and hang_tau not in (select ma from public.hang_tau) loop
    insert into public.hang_tau (ma) values (x.ma); insert into _bao_cao (dong) values ('DANH MỤC: thêm hãng tàu ' || x.ma); end loop;
  for x in select distinct cang_den as ma from x_lo where cang_den is not null and cang_den not in (select ma from public.cang_den) loop
    insert into public.cang_den (ma, ten_vn) values (x.ma, x.ma); insert into _bao_cao (dong) values ('DANH MỤC: thêm cảng đến ' || x.ma); end loop;
""")
    # 1. đổi mã lô
    for cu, moi in doi:
        w(f"""  if exists (select 1 from public.lo where lo = {q(cu)}) and not exists (select 1 from public.lo where lo = {q(moi)}) then
    update public.lo set lo = {q(moi)} where lo = {q(cu)};
    insert into _bao_cao (dong) values ('ĐỔI MÃ LÔ: {cu} → {moi} (' || (select count(*) from public.cont where lo = {q(moi)}) || ' cont theo)');
  end if;""")
    # 2. xoá lô
    for lo in xoa:
        w(f"""  select count(*) into v_n from public.cont where lo = {q(lo)};
  delete from public.cont where lo = {q(lo)};
  delete from public.lo where lo = {q(lo)};
  insert into _bao_cao (dong) values ('XOÁ LÔ {lo}: ' || v_n || ' cont (qua CLS, theo luật hôm qua)');""")
    # 3. lô: upsert
    w("""
  -- 3. Lô: có thì cập nhật (Excel có giá trị mới ghi đè), chưa có thì thêm
  for x in select * from x_lo order by lo loop
    select * into v_lo from public.lo where lo = x.lo;
    if not found then
      insert into public.lo (lo, booking, hang_tau, ten_tau, cang_den, etd, eta, etd_kho, closing_mail, closing_eport, closing, ma_don_kdtv, da_khai_eport, thanh_ly, so_luong_cont, cskh, nguoi_cap_nhat, ghi_chu)
      values (x.lo, x.booking, x.hang_tau, x.ten_tau, x.cang_den, x.etd, x.eta, x.etd_kho, x.closing_mail, x.closing_eport, case when x.closing_mail is null and x.closing_eport is null then x.closing_tay end, x.ma_don_kdtv, x.da_khai_eport, x.thanh_ly, x.so_luong, x.cskh, '""" + nhan + """',
              concat_ws(' · ', x.ghi_chu, case when x.rot then '""" + nhan + """: lô xếp lại tàu (R) — kiểm tra booking / tàu' end));
      insert into _bao_cao (dong) values ('LÔ MỚI ' || x.lo || ': booking ' || coalesce(x.booking,'-') || ' · tàu ' || coalesce(x.ten_tau,'-') || ' · ETD ' || coalesce(x.etd::text,'-') || ' · CLS ' || coalesce(to_char(coalesce(x.closing_mail, x.closing_eport, x.closing_tay) at time zone 'Asia/Ho_Chi_Minh', 'DD/MM HH24:MI'),'-') || case when x.rot then ' · XẾP LẠI TÀU' else '' end);
    else
      update public.lo l set
        booking = coalesce(x.booking, l.booking), hang_tau = coalesce(x.hang_tau, l.hang_tau), ten_tau = coalesce(x.ten_tau, l.ten_tau), cang_den = coalesce(x.cang_den, l.cang_den),
        etd = coalesce(x.etd, l.etd), eta = coalesce(x.eta, l.eta), etd_kho = coalesce(l.etd_kho, x.etd_kho),
        closing_mail = coalesce(x.closing_mail, l.closing_mail), closing_eport = coalesce(l.closing_eport, x.closing_eport),
        closing = case when x.closing_mail is null and x.closing_eport is null and l.closing_mail is null and l.closing_eport is null then coalesce(l.closing, x.closing_tay) else l.closing end,
        ma_don_kdtv = coalesce(x.ma_don_kdtv, l.ma_don_kdtv), da_khai_eport = l.da_khai_eport or x.da_khai_eport, thanh_ly = l.thanh_ly or x.thanh_ly,
        so_luong_cont = coalesce(x.so_luong, l.so_luong_cont), cskh = coalesce(x.cskh, l.cskh), nguoi_cap_nhat = '""" + nhan + """',
        ghi_chu = case when x.ghi_chu is null or coalesce(l.ghi_chu,'') like '%xếp lại tàu theo sheet KD%' then l.ghi_chu else concat_ws(' · ', nullif(l.ghi_chu,''), x.ghi_chu) end
      where l.lo = x.lo
        and (row(l.booking, l.hang_tau, l.ten_tau, l.cang_den, l.etd, l.eta, l.closing_mail, l.ma_don_kdtv, l.da_khai_eport, l.thanh_ly, l.so_luong_cont)
             is distinct from row(coalesce(x.booking, l.booking), coalesce(x.hang_tau, l.hang_tau), coalesce(x.ten_tau, l.ten_tau), coalesce(x.cang_den, l.cang_den), coalesce(x.etd, l.etd), coalesce(x.eta, l.eta), coalesce(x.closing_mail, l.closing_mail), coalesce(x.ma_don_kdtv, l.ma_don_kdtv), l.da_khai_eport or x.da_khai_eport, l.thanh_ly or x.thanh_ly, coalesce(x.so_luong, l.so_luong_cont))
             or (x.ghi_chu is not null and coalesce(l.ghi_chu,'') not like '%xếp lại tàu theo sheet KD%')
             or (l.closing_eport is null and x.closing_eport is not null) or (l.closing is null and l.closing_mail is null and l.closing_eport is null and x.closing_mail is null and x.closing_eport is null and x.closing_tay is not null));
      if found then
        select * into c from public.lo where lo = x.lo;
        insert into _bao_cao (dong) values ('LÔ SỬA ' || x.lo || ': '
          || case when v_lo.booking is distinct from c.booking then 'booking ' || coalesce(v_lo.booking,'-') || '→' || coalesce(c.booking,'-') || '; ' else '' end
          || case when v_lo.ten_tau is distinct from c.ten_tau then 'tàu ' || coalesce(v_lo.ten_tau,'-') || '→' || coalesce(c.ten_tau,'-') || '; ' else '' end
          || case when v_lo.hang_tau is distinct from c.hang_tau then 'hãng ' || coalesce(v_lo.hang_tau,'-') || '→' || coalesce(c.hang_tau,'-') || '; ' else '' end
          || case when v_lo.etd is distinct from c.etd then 'ETD ' || coalesce(v_lo.etd::text,'-') || '→' || coalesce(c.etd::text,'-') || '; ' else '' end
          || case when v_lo.eta is distinct from c.eta then 'ETA ' || coalesce(v_lo.eta::text,'-') || '→' || coalesce(c.eta::text,'-') || '; ' else '' end
          || case when v_lo.cls is distinct from c.cls then 'CLS ' || coalesce(to_char(v_lo.cls at time zone 'Asia/Ho_Chi_Minh','DD/MM HH24:MI'),'-') || '→' || coalesce(to_char(c.cls at time zone 'Asia/Ho_Chi_Minh','DD/MM HH24:MI'),'-') || '; ' else '' end
          || case when v_lo.ma_don_kdtv is distinct from c.ma_don_kdtv then 'KDTV ' || coalesce(v_lo.ma_don_kdtv,'-') || '→' || coalesce(c.ma_don_kdtv,'-') || '; ' else '' end
          || case when v_lo.da_khai_eport is distinct from c.da_khai_eport then 'ePort→' || c.da_khai_eport || '; ' else '' end
          || case when v_lo.thanh_ly is distinct from c.thanh_ly then 'thanh lý→' || c.thanh_ly || '; ' else '' end
          || case when v_lo.so_luong_cont is distinct from c.so_luong_cont then 'SL ' || coalesce(v_lo.so_luong_cont::text,'-') || '→' || coalesce(c.so_luong_cont::text,'-') || '; ' else '' end
          || case when v_lo.ghi_chu is distinct from c.ghi_chu then 'ghi chú→' || coalesce(c.ghi_chu,'-') || '; ' else '' end);
      end if;
    end if;
  end loop;
""")
    # 4. lô rớt tàu (giữ, phục hồi)
    for lo in rot:
        w(f"""  -- lô {lo}: rớt tàu (R) — CLS để trống chờ booking mới, bỏ tích KD / thanh lý, ghi chú
  update public.lo set closing_mail = null, closing = null, closing_eport = null, da_kiem_dich = false, thanh_ly = false, cho_keo_ha_cang = false,
         ghi_chu = case when coalesce(ghi_chu,'') like '%rớt tàu%' then ghi_chu else concat_ws(' · ', nullif(ghi_chu,''), '{nhan}: rớt tàu (R), chờ booking / tàu mới') end,
         nguoi_cap_nhat = '{nhan}'
   where lo = {q(lo)};
  delete from public.thong_tin_cu t using public.lo l where t.lo = l.lo and l.lo = {q(lo)} and t.cont_id is null and ((t.truong = 'booking' and t.gia_tri = l.booking) or (t.truong = 'ten_tau' and t.gia_tri = l.ten_tau));
  insert into _bao_cao (dong) values ('LÔ {lo}: rớt tàu → giữ lại, CLS để trống, bỏ tích KD, cont về theo Excel');""")
    # 5. cont upsert
    w("""
  -- 5. Cont: có thì cập nhật (Excel có giá trị mới ghi đè; trạng thái không lùi trừ lô rớt tàu), chưa có thì thêm
  for x in select * from x_cont order by row loop
    select * into c from public.cont where upper(so_cont) = x.so_cont and trang_thai <> '9' order by (lo = x.lo) desc nulls last, cap_nhat_luc desc limit 1;
    if not found then
      insert into public.cont (id, lo, ma_don, khach_hang, kho, so_cont, so_seal, trang_thai, bai_tam, ngay_den_kho, ngay_goi_cont, ngay_can_len_kho, gio_len_kho_ghi_chu, nha_xe, so_xe, can_tem, gio_vao_bai, gio_ra_bai, gia_bao, phu_phi_xe, phi_phat_sinh, ghi_chu, cskh, kho_goc, hien_trang_goc, nguon, nguoi_cap_nhat)
      values ('""" + 'C%02d%02d%02d' % (nam % 100, mm, dd) + """-' || x.so_cont, x.lo, x.ma_don, x.khach, x.kho, x.so_cont, x.so_seal, x.st, case when x.st = '4' then x.bai end, x.ngay_den_kho, x.ngay_goi, x.can_len, x.gio_ghi, x.nha_xe, x.so_xe, x.tem,
              coalesce(x.gio_vao, case when x.st = '4' then now() end), x.gio_ra, x.gia, x.phu_phi, x.phat_sinh, x.note, x.cskh, x.kho_goc, x.hien_trang_goc, '""" + nhan + """ (dòng ' || x.row || ')', '""" + nhan + """');
      insert into _bao_cao (dong) values ('CONT MỚI ' || x.so_cont || ' · lô ' || coalesce(x.lo,'(chưa có)') || ' · ' || coalesce(x.ma_don,'-') || ' · ' || coalesce(x.kho,'-') || ' · bước ' || x.st || coalesce(' ' || x.bai,'') || ' · nhà xe ' || coalesce(x.nha_xe,'-') || coalesce(' · ' || x.note,''));
    else
      v_st := case when x.lo is not null and x.lo = any (string_to_array('""" + ','.join(rot) + """', ',')) then x.st
                   when x.st > c.trang_thai then x.st else c.trang_thai end;
      v_bai := case when v_st = '4' then coalesce(case when x.st = '4' then x.bai end, c.bai_tam) else c.bai_tam end;
      update public.cont k set
        lo = coalesce(x.lo, k.lo), ma_don = coalesce(x.ma_don, k.ma_don), khach_hang = coalesce(x.khach, k.khach_hang), kho = coalesce(x.kho, k.kho),
        so_seal = coalesce(x.so_seal, k.so_seal), trang_thai = v_st, bai_tam = v_bai,
        ngay_den_kho = coalesce(x.ngay_den_kho, k.ngay_den_kho), ngay_goi_cont = coalesce(k.ngay_goi_cont, x.ngay_goi),
        ngay_can_len_kho = coalesce(k.ngay_can_len_kho, x.can_len), gio_len_kho_ghi_chu = coalesce(k.gio_len_kho_ghi_chu, x.gio_ghi),
        nha_xe = coalesce(x.nha_xe, k.nha_xe), so_xe = coalesce(x.so_xe, k.so_xe), can_tem = x.tem,
        gio_vao_bai = coalesce(x.gio_vao, k.gio_vao_bai, case when v_st = '4' and c.trang_thai <> '4' then now() end),
        gio_ra_bai = case when v_st < '5' and c.trang_thai >= '5' then x.gio_ra else coalesce(x.gio_ra, k.gio_ra_bai) end,
        gia_bao = coalesce(x.gia, k.gia_bao), phu_phi_xe = coalesce(x.phu_phi, k.phu_phi_xe), phi_phat_sinh = coalesce(x.phat_sinh, k.phi_phat_sinh),
        ghi_chu = case when x.note is null or coalesce(k.ghi_chu,'') like '%' || x.note || '%' then k.ghi_chu else concat_ws(' · ', nullif(k.ghi_chu,''), x.note) end,
        cskh = coalesce(x.cskh, k.cskh), kho_goc = coalesce(x.kho_goc, k.kho_goc), hien_trang_goc = x.hien_trang_goc, nguoi_cap_nhat = '""" + nhan + """'
      where k.id = c.id;
      select * into y from public.cont where id = c.id;   -- y = dòng sau sửa
      v_bc := ''
        || case when c.lo is distinct from y.lo then 'lô ' || coalesce(c.lo,'-') || '→' || coalesce(y.lo,'-') || '; ' else '' end
        || case when c.trang_thai is distinct from y.trang_thai then 'bước ' || c.trang_thai || '→' || y.trang_thai || '; ' else '' end
        || case when c.bai_tam is distinct from y.bai_tam then 'bãi ' || coalesce(c.bai_tam,'-') || '→' || coalesce(y.bai_tam,'-') || '; ' else '' end
        || case when c.so_seal is distinct from y.so_seal then 'seal ' || coalesce(c.so_seal,'-') || '→' || coalesce(y.so_seal,'-') || '; ' else '' end
        || case when c.ma_don is distinct from y.ma_don then 'mã đơn ' || coalesce(c.ma_don,'-') || '→' || coalesce(y.ma_don,'-') || '; ' else '' end
        || case when c.kho is distinct from y.kho then 'kho ' || coalesce(c.kho,'-') || '→' || coalesce(y.kho,'-') || '; ' else '' end
        || case when c.khach_hang is distinct from y.khach_hang then 'khách ' || coalesce(c.khach_hang,'-') || '→' || coalesce(y.khach_hang,'-') || '; ' else '' end
        || case when c.nha_xe is distinct from y.nha_xe then 'nhà xe ' || coalesce(c.nha_xe,'-') || '→' || coalesce(y.nha_xe,'-') || '; ' else '' end
        || case when c.ngay_den_kho is distinct from y.ngay_den_kho then 'đến kho ' || coalesce(c.ngay_den_kho::text,'-') || '→' || coalesce(y.ngay_den_kho::text,'-') || '; ' else '' end
        || case when c.can_tem is distinct from y.can_tem then 'tem→' || y.can_tem || '; ' else '' end
        || case when c.gio_vao_bai is distinct from y.gio_vao_bai then 'giờ vào bãi→' || coalesce(to_char(y.gio_vao_bai at time zone 'Asia/Ho_Chi_Minh','DD/MM HH24:MI'),'-') || '; ' else '' end
        || case when c.gio_ra_bai is distinct from y.gio_ra_bai then 'giờ ra bãi→' || coalesce(to_char(y.gio_ra_bai at time zone 'Asia/Ho_Chi_Minh','DD/MM HH24:MI'),'-') || '; ' else '' end
        || case when c.gia_bao is distinct from y.gia_bao or c.phu_phi_xe is distinct from y.phu_phi_xe then 'giá→' || coalesce(y.gia_bao::text,'-') || '/' || coalesce(y.phu_phi_xe::text,'-') || '; ' else '' end
        || case when c.ghi_chu is distinct from y.ghi_chu then 'ghi chú→' || coalesce(y.ghi_chu,'-') || '; ' else '' end;
      if v_bc <> '' then insert into _bao_cao (dong) values ('CONT SỬA ' || y.so_cont || ' (lô ' || coalesce(y.lo,'-') || '): ' || v_bc); end if;
    end if;
  end loop;

  -- 6. Cont kiểm dịch theo sheet Kế hoạch KD (mỗi lô 1 cont; lô đã tích KD thì không đổi, chỉ báo)
  for x in select l.lo, l.cont_kd from x_lo l where l.cont_kd is not null loop
    select * into c from public.lo where lo = x.lo;
    select string_agg(so_cont, ', ') into v_kd from public.cont where lo = x.lo and cont_kiem_dich and trang_thai <> '9' and upper(so_cont) <> x.cont_kd;
    if not exists (select 1 from public.cont where lo = x.lo and upper(so_cont) = x.cont_kd and trang_thai <> '9') then
      insert into _bao_cao (dong) values ('KD ⚠ lô ' || x.lo || ': sheet KD ghi cont ' || x.cont_kd || ' nhưng cont này không thuộc lô trong app → bỏ qua');
    elsif c.da_kiem_dich and v_kd is not null then
      insert into _bao_cao (dong) values ('KD ⚠ lô ' || x.lo || ' đã tích KD với cont ' || v_kd || ', sheet KD lại ghi ' || x.cont_kd || ' → giữ nguyên, team kiểm tra');
    else
      if v_kd is not null then
        update public.cont set cont_kiem_dich = false, nguoi_cap_nhat = '""" + nhan + """' where lo = x.lo and cont_kiem_dich and upper(so_cont) <> x.cont_kd;
      end if;
      update public.cont set cont_kiem_dich = true, nguoi_cap_nhat = '""" + nhan + """' where lo = x.lo and upper(so_cont) = x.cont_kd and not cont_kiem_dich;
      if found or v_kd is not null then
        insert into _bao_cao (dong) values ('KD lô ' || x.lo || ': cont kiểm dịch = ' || x.cont_kd || coalesce(' (bỏ dấu ' || v_kd || ')', ''));
      end if;
    end if;
  end loop;

  -- 7. Tổng kết
  insert into _bao_cao (dong) select '— TỔNG: ' || (select count(*) from public.lo where lo in (select lo from x_lo)) || ' lô trong phạm vi; cont đang chạy (bước 1-5): ' || (select count(*) from public.cont where trang_thai < '6') || '; cont ' || '""" + nhan + """' || ' mới: ' || (select count(*) from public.cont where nguon like '""" + nhan + """%');
""")
    if a.thu:
        w("  select string_agg(dong, E'\\n' order by tt) into v_bc from _bao_cao;")
        w("  raise exception '%', 'KET_QUA (CHẠY THỬ — đã rollback, chưa ghi gì):' || E'\\n' || v_bc;")
    w("end $$;")
    if not a.thu:
        w("select string_agg(dong, E'\\n' order by tt) as bao_cao from _bao_cao;")
    sql = '\n'.join(L) + '\n'
    open(a.ra, 'w', encoding='utf-8').write(sql)
    print('lô trong phạm vi (%d):' % len(scope), ', '.join(sorted(scope)))
    print('lô bỏ qua (CLS đã qua / xong):', ', '.join(sorted(l for l in LO if l not in scope and l not in xoa)))
    print('cont trong phạm vi:', len(CONT), '| xoá lô:', xoa, '| rớt tàu:', rot, '| đổi mã:', doi)
    print('SQL:', a.ra, len(sql), 'bytes, sha256', hashlib.sha256(sql.encode('utf-8')).hexdigest())

if __name__ == '__main__':
    main()
