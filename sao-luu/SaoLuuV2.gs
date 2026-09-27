/**
 * SAO LƯU V2 — thêm file này vào CÙNG dự án Apps Script đang có SaoLuuSupabase.gs + DongBo.gs
 * (dùng lại SUPABASE_URL, SUPABASE_KEY, MA_SAO_LUU, TEN_THU_MUC, MUI_GIO, GIO_CHAY, goiSupabase_ của 2 file đó).
 *
 * Mỗi tối (GIO_CHAY, mặc định 23h) hàm saoLuuDayDu() làm 3 việc:
 *   1. SAO LƯU ĐẦY ĐỦ mọi bảng (kể cả booking, sự cố, chi phí phát sinh, bảng giá…) → thư mục "Sao lưu Supabase":
 *        - "Sao lưu Supabase dd-MM-yyyy.json"  (bản khôi phục chính xác)
 *        - "Sao lưu Supabase dd-MM-yyyy"       (Google Sheet, mỗi bảng 1 trang, để xem)
 *      rồi báo cho web biết (để nút Dọn dữ liệu + dọn tự động hằng tháng biết đã có bản sao lưu).
 *   2. XUẤT CHI PHÍ BÃI trong ngày → thư mục "Chi phí bãi", mỗi THÁNG 1 file "Chi phí bãi MM-yyyy":
 *        - trang "Tổng hợp": mỗi ngày × mỗi bãi 1 dòng (số cont, điện, nâng hạ, hạ cảng, phát sinh, tổng)
 *        - trang "dd-MM":    chi tiết từng cont của ngày đó
 *   3. DỌN BẢN SAO LƯU CŨ: giữ mọi bản trong SL2_GIU_NGAY ngày gần nhất + bản NGÀY 01 mỗi tháng (giữ vĩnh viễn).
 *      Bản cũ bị chuyển vào Thùng rác Drive (khôi phục được trong 30 ngày).
 *
 * CÀI ĐẶT (1 lần): chọn hàm  caiDatV2  → Chạy. Hàm này thay trigger cũ (saoLuu / saoLuuVaGhiNhan) bằng saoLuuDayDu,
 *   GIỮ NGUYÊN trigger đồng bộ mã KDTV (dongBoMaKDTV).
 * Bù chi phí bãi các ngày trước: sửa ngày trong hàm  xuatChiPhiBaiBu  rồi Chạy.
 * Có lỗi ở bước nào, Google tự gửi email báo (các bước khác vẫn chạy).
 */
const SL2_GIU_NGAY = 60;                       // giữ bản sao lưu hằng ngày trong bấy nhiêu ngày
const SL2_THU_MUC_CHI_PHI = 'Chi phí bãi';
const SL2_BANG_TRUOC = ['lo', 'cont', 'booking', 'lo_su_co', 'chi_phi_cont', 'goi_y', 'nhat_ky'];  // các trang xếp đầu Sheet
const SL2_TRANG_THAI = { '1': 'Đơn chờ lên', '2': 'Đang đóng hàng', '3': 'Đầy chờ kéo', '4': 'Ở bãi tạm', '5': 'Đã hạ cảng', '6': 'Đã lên tàu', '9': 'Hủy/đổi cont' };

function caiDatV2() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    const f = t.getHandlerFunction();
    if (f === 'saoLuu' || f === 'saoLuuVaGhiNhan' || f === 'saoLuuDayDu') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('saoLuuDayDu').timeBased().everyDays(1).atHour(GIO_CHAY).inTimezone(MUI_GIO).create();
  saoLuuDayDu();
}

function saoLuuDayDu() {
  const loi = [];
  try { sl2SaoLuuTatCa_(); } catch (e) { loi.push('Sao lưu: ' + e.message); }
  try { sl2XuatChiPhiBai_(Utilities.formatDate(new Date(), MUI_GIO, 'yyyy-MM-dd')); } catch (e) { loi.push('Chi phí bãi: ' + e.message); }
  try { sl2DonBanCu_(); } catch (e) { loi.push('Dọn bản sao lưu cũ: ' + e.message); }
  if (loi.length) throw new Error(loi.join(' | '));
}

// Chạy tay để xuất bù chi phí bãi cho một khoảng ngày (yyyy-MM-dd)
function xuatChiPhiBaiBu() {
  const TU = '2026-09-27', DEN = Utilities.formatDate(new Date(), MUI_GIO, 'yyyy-MM-dd');
  for (let d = new Date(TU + 'T12:00:00+07:00'); Utilities.formatDate(d, MUI_GIO, 'yyyy-MM-dd') <= DEN; d = new Date(d.getTime() + 864e5)) {
    sl2XuatChiPhiBai_(Utilities.formatDate(d, MUI_GIO, 'yyyy-MM-dd'));
  }
}

/* ---------- 1. Sao lưu đầy đủ ---------- */
function sl2SaoLuuTatCa_() {
  const data = goiSupabase_('sao_luu_du_lieu', { p_ma: MA_SAO_LUU });
  if (!data || !data.so_dong) throw new Error('Supabase chưa chạy migration sao lưu đầy đủ (thiếu so_dong)');
  const bayGio = new Date();
  const ten = 'Sao lưu Supabase ' + Utilities.formatDate(bayGio, MUI_GIO, 'dd-MM-yyyy');
  const thuMuc = sl2ThuMuc_(TEN_THU_MUC);
  [ten, ten + '.json'].forEach(function (n) { const it = thuMuc.getFilesByName(n); while (it.hasNext()) it.next().setTrashed(true); });

  // JSON trước (bản khôi phục) — nếu bước Sheet lỗi vẫn có JSON
  const fJson = thuMuc.createFile(ten + '.json', JSON.stringify(data), 'application/json');

  const bangs = Object.keys(data).filter(function (k) { return Array.isArray(data[k]); });
  bangs.sort(function (a, b) {
    const ia = SL2_BANG_TRUOC.indexOf(a), ib = SL2_BANG_TRUOC.indexOf(b);
    return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b);
  });
  const ss = SpreadsheetApp.create(ten);
  const tongHop = [];
  bangs.forEach(function (bang, i) {
    const rows = data[bang];
    const sh = i === 0 ? ss.getSheets()[0].setName(bang) : ss.insertSheet(bang);
    tongHop.push([bang, rows.length]);
    if (!rows.length) { sh.getRange(1, 1).setValue('(trống)'); return; }
    const cols = [];
    rows.forEach(function (r) { Object.keys(r).forEach(function (k) { if (cols.indexOf(k) < 0) cols.push(k); }); });
    const values = [cols].concat(rows.map(function (r) { return cols.map(function (c) { return sl2O_(r[c]); }); }));
    const range = sh.getRange(1, 1, values.length, cols.length);
    range.setNumberFormat('@');
    range.setValues(values);
    sh.setFrozenRows(1);
    sh.getRange(1, 1, 1, cols.length).setFontWeight('bold');
  });
  const tt = ss.insertSheet('Thông tin', 0);
  const dau = [['Sao lưu ĐẦY ĐỦ dữ liệu Supabase – Điều độ', ''], ['Thời điểm', Utilities.formatDate(bayGio, MUI_GIO, 'HH:mm dd/MM/yyyy')],
    ['Dự án', SUPABASE_URL], ['Khôi phục chính xác', 'dùng file ' + ten + '.json'], ['', ''], ['Bảng', 'Số dòng']].concat(tongHop);
  tt.getRange(1, 1, dau.length, 2).setValues(dau);
  tt.getRange(1, 1).setFontWeight('bold'); tt.getRange(6, 1, 1, 2).setFontWeight('bold'); tt.autoResizeColumns(1, 2);
  DriveApp.getFileById(ss.getId()).moveTo(thuMuc);

  goiSupabase_('ghi_nhan_sao_luu', { p_ma: MA_SAO_LUU, p_ten: ten, p_url: fJson.getUrl(), p_so_dong: data.so_dong });
  Logger.log('Đã sao lưu đầy đủ: ' + ten + ' — ' + tongHop.map(function (x) { return x[0] + '=' + x[1]; }).join(', '));
}

/* ---------- 2. Chi phí bãi theo ngày ---------- */
function sl2XuatChiPhiBai_(ngay) {           // ngay = 'yyyy-MM-dd' (giờ VN)
  const kq = goiSupabase_('chi_phi_bai_ngay', { p_ma: MA_SAO_LUU, p_ngay: ngay });
  const p = ngay.split('-'), tenFile = 'Chi phí bãi ' + p[1] + '-' + p[0], tenTrang = p[2] + '-' + p[1];
  const thuMuc = sl2ThuMuc_(SL2_THU_MUC_CHI_PHI);
  let ss;
  const it = thuMuc.getFilesByName(tenFile);
  if (it.hasNext()) ss = SpreadsheetApp.open(it.next());
  else { ss = SpreadsheetApp.create(tenFile); DriveApp.getFileById(ss.getId()).moveTo(thuMuc); ss.getSheets()[0].setName('Tổng hợp'); }

  const rows = kq.cont || [];
  const ts = function (v) { return v ? Utilities.formatDate(new Date(v), MUI_GIO, 'HH:mm dd/MM/yyyy') : ''; };
  const TIEN = [10, 11, 12, 13, 14, 15];     // cột tiền (0-based) trong bảng chi tiết

  // --- trang chi tiết ngày ---
  const cu = ss.getSheetByName(tenTrang); if (cu) ss.deleteSheet(cu);
  const sh = ss.insertSheet(tenTrang, 1);
  const giaBai = (kq.bai || []).map(function (b) {
    return b.ma + ': điện ' + (b.dien_moi_gio || 0).toLocaleString('vi-VN') + ' đ/giờ, nâng hạ ' + (b.nang_ha || 0).toLocaleString('vi-VN') + ' đ, hạ cảng ' + (b.ha_cang || 0).toLocaleString('vi-VN') + ' đ';
  }).join(' · ');
  const head = ['Bãi', 'Số cont', 'Lô', 'Khách hàng', 'Trạng thái', 'KD', 'Vào bãi', 'Ra bãi', 'Giờ trong ngày', 'Giờ tích luỹ',
    'Điện trong ngày', 'Nâng hạ', 'Hạ cảng', 'Phát sinh', 'Tổng trong ngày', 'Tổng tích luỹ (như web)'];
  const out = [['CHI PHÍ BÃI NGÀY ' + p[2] + '/' + p[1] + '/' + p[0], '', '', '', '', '', '', '', '', '', '', '', '', '', '', ''],
               ['Giá đang áp dụng: ' + (giaBai || '—'), '', '', '', '', '', '', '', '', '', '', '', '', '', '', ''],
               ['Xuất lúc ' + ts(kq.luc) + ' · "Trong ngày" = phần phát sinh đúng ngày này; cộng các ngày = tổng thực tế', '', '', '', '', '', '', '', '', '', '', '', '', '', '', ''],
               head];
  const theoBai = {};
  rows.forEach(function (r) { (theoBai[r.bai] = theoBai[r.bai] || []).push(r); });
  const tongHop = [];
  Object.keys(theoBai).sort().forEach(function (bai) {
    const t = { dien: 0, nang: 0, ha: 0, ps: 0, ngay: 0, tl: 0 };
    theoBai[bai].forEach(function (r) {
      out.push([bai, r.so_cont || '', r.lo || '', r.khach_hang || '', SL2_TRANG_THAI[r.trang_thai] || r.trang_thai, r.kiem_dich ? 'KD' : '',
        ts(r.gio_vao_bai), ts(r.gio_ra_bai), r.gio_trong_ngay, r.gio_tich_luy,
        +r.dien_ngay, +r.nang_ha_ngay, +r.ha_cang_ngay, +r.phat_sinh_ngay, +r.tong_ngay, +r.tong_tich_luy]);
      t.dien += +r.dien_ngay; t.nang += +r.nang_ha_ngay; t.ha += +r.ha_cang_ngay; t.ps += +r.phat_sinh_ngay; t.ngay += +r.tong_ngay; t.tl += +r.tong_tich_luy;
    });
    out.push(['Cộng ' + bai, theoBai[bai].length + ' cont', '', '', '', '', '', '', '', '', t.dien, t.nang, t.ha, t.ps, t.ngay, t.tl]);
    tongHop.push([ngay, bai, (theoBai[bai][0].ten_bai || ''), theoBai[bai].length, t.dien, t.nang, t.ha, t.ps, t.ngay]);
  });
  if (!rows.length) out.push(['(Không có cont nào ở bãi trong ngày này)', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '']);
  sh.getRange(1, 1, out.length, head.length).setValues(out);
  sh.getRange(1, 1).setFontWeight('bold').setFontSize(13);
  sh.getRange(4, 1, 1, head.length).setFontWeight('bold').setBackground('#EDE9FE');
  sh.setFrozenRows(4);
  if (out.length > 4) {
    TIEN.forEach(function (c) { sh.getRange(5, c + 1, out.length - 4, 1).setNumberFormat('#,##0'); });
    for (let i = 4; i < out.length; i++) if (String(out[i][0]).indexOf('Cộng ') === 0) sh.getRange(i + 1, 1, 1, head.length).setFontWeight('bold').setBackground('#F5F3FF');
  }
  sh.autoResizeColumns(1, head.length);

  // --- trang Tổng hợp (mỗi ngày × bãi 1 dòng; chạy lại ngày đó thì thay dòng cũ) ---
  const th = ss.getSheetByName('Tổng hợp') || ss.insertSheet('Tổng hợp', 0);
  const TH_HEAD = ['Ngày', 'Bãi', 'Tên bãi', 'Số cont', 'Điện', 'Nâng hạ', 'Hạ cảng', 'Phát sinh', 'Tổng trong ngày'];
  let cur = th.getLastRow() > 1 ? th.getRange(2, 1, th.getLastRow() - 1, TH_HEAD.length).getValues() : [];
  cur = cur.filter(function (r) { const d = sl2Ngay_(r[0]); return /^\d{4}-\d{2}-\d{2}$/.test(d) && d !== ngay; });   // bỏ dòng CỘNG + dòng cũ của ngày này
  const moi = cur.map(function (r) { return [sl2Ngay_(r[0])].concat(r.slice(1)); }).concat(tongHop);
  moi.sort(function (a, b) { return String(a[0]).localeCompare(String(b[0])) || String(a[1]).localeCompare(String(b[1])); });
  th.clear();
  th.getRange(1, 1, 1, TH_HEAD.length).setValues([TH_HEAD]).setFontWeight('bold').setBackground('#EDE9FE');
  if (moi.length) {
    th.getRange(2, 1, moi.length, TH_HEAD.length).setValues(moi);
    th.getRange(2, 1, moi.length, 1).setNumberFormat('@');
    th.getRange(2, 5, moi.length, 5).setNumberFormat('#,##0');
    const n = moi.length + 2;
    th.getRange(n, 1, 1, 4).setValues([['CỘNG THÁNG', '', '', '']]);
    th.getRange(n, 5, 1, 5).setFormulas([['=SUM(E2:E' + (n - 1) + ')', '=SUM(F2:F' + (n - 1) + ')', '=SUM(G2:G' + (n - 1) + ')', '=SUM(H2:H' + (n - 1) + ')', '=SUM(I2:I' + (n - 1) + ')']]).setNumberFormat('#,##0');
    th.getRange(n, 1, 1, TH_HEAD.length).setFontWeight('bold').setBackground('#F5F3FF');
  }
  th.setFrozenRows(1); th.autoResizeColumns(1, TH_HEAD.length);
  Logger.log('Chi phí bãi ' + ngay + ': ' + rows.length + ' cont → ' + tenFile + ' / ' + tenTrang);
}

/* ---------- 3. Dọn bản sao lưu cũ ---------- */
function sl2DonBanCu_() {
  const re = /^Sao lưu Supabase (\d{2})-(\d{2})-(\d{4})(\.json)?$/;
  const homNay = new Date(Utilities.formatDate(new Date(), MUI_GIO, 'yyyy-MM-dd') + 'T00:00:00+07:00');
  const files = sl2ThuMuc_(TEN_THU_MUC).getFiles();
  let n = 0;
  while (files.hasNext()) {
    const f = files.next(), m = re.exec(f.getName());
    if (!m || m[1] === '01') continue;                           // giữ vĩnh viễn bản ngày 01 mỗi tháng
    const ngay = new Date(m[3] + '-' + m[2] + '-' + m[1] + 'T00:00:00+07:00');
    if ((homNay - ngay) / 864e5 > SL2_GIU_NGAY) { f.setTrashed(true); n++; }
  }
  Logger.log('Dọn bản sao lưu cũ: chuyển ' + n + ' file vào Thùng rác');
}

/* ---------- tiện ích ---------- */
function sl2ThuMuc_(ten) { const it = DriveApp.getFoldersByName(ten); return it.hasNext() ? it.next() : DriveApp.createFolder(ten); }
function sl2Ngay_(v) { return v instanceof Date ? Utilities.formatDate(v, MUI_GIO, 'yyyy-MM-dd') : String(v); }
function sl2O_(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'object') v = JSON.stringify(v);
  if (typeof v === 'string' && v.length > 49000) return v.slice(0, 49000) + '…(cắt bớt, xem file .json)';
  return v;
}
