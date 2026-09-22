/**
 * SAO LƯU SUPABASE → GOOGLE DRIVE  (Điều độ cont chuối – Đại Cát Lâm)
 *
 * Mỗi tối tự tạo trong thư mục Drive "Sao lưu Supabase":
 *   - Google Sheet  "Sao lưu Supabase dd-MM-yyyy"       (mỗi bảng 1 trang, để xem / tải về Excel)
 *   - File JSON     "Sao lưu Supabase dd-MM-yyyy.json"  (bản đầy đủ, dùng để khôi phục chính xác)
 *
 * CÀI ĐẶT (làm 1 lần): chọn hàm  caiDat  ở thanh trên → bấm Chạy (Run) → cho phép quyền.
 * Chạy tay bất cứ lúc nào: chọn hàm  saoLuu  → Chạy.
 * MA_SAO_LUU là mã bí mật — không chia sẻ file script này cho người khác.
 */
const SUPABASE_URL = 'https://cgfcbxsyjtdlligpdzbp.supabase.co';
const SUPABASE_KEY = 'sb_publishable_sbKx-V4-EijUlCI2mnVJ5w_RYg5jHRz';
const MA_SAO_LUU = 'DIEN_MA_SAO_LUU_VAO_DAY';
const TEN_THU_MUC = 'Sao lưu Supabase';
const GIO_CHAY = 23;            // chạy trong khoảng 23h–24h mỗi tối
const MUI_GIO = 'Asia/Ho_Chi_Minh';
const THU_TU_BANG = ['lo', 'cont', 'goi_y', 'nhat_ky', 'kho', 'nha_xe', 'khach_hang', 'bai_tam',
  'hang_tau', 'cang_den', 'cang_ha', 'trang_thai', 'nhan_vien', 'cau_hinh'];

function caiDat() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'saoLuu') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('saoLuu').timeBased().everyDays(1).atHour(GIO_CHAY).inTimezone(MUI_GIO).create();
  saoLuu();
}

function saoLuu() {
  const res = UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/rpc/sao_luu_du_lieu', {
    method: 'post',
    contentType: 'application/json',
    headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY },
    payload: JSON.stringify({ p_ma: MA_SAO_LUU }),
    muteHttpExceptions: true
  });
  if (res.getResponseCode() !== 200) {
    throw new Error('Supabase trả lỗi ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 500));
  }
  const text = res.getContentText();
  const data = JSON.parse(text);
  const bayGio = new Date();
  const ten = 'Sao lưu Supabase ' + Utilities.formatDate(bayGio, MUI_GIO, 'dd-MM-yyyy');
  const thuMuc = layThuMuc_();

  // Chạy lại trong cùng ngày thì thay bản cũ của ngày đó
  [ten, ten + '.json'].forEach(function (n) {
    const it = thuMuc.getFilesByName(n);
    while (it.hasNext()) it.next().setTrashed(true);
  });

  thuMuc.createFile(ten + '.json', text, 'application/json');

  const ss = SpreadsheetApp.create(ten);
  const tongHop = [];
  THU_TU_BANG.forEach(function (bang, i) {
    const rows = data[bang] || [];
    const sh = i === 0 ? ss.getSheets()[0].setName(bang) : ss.insertSheet(bang);
    tongHop.push([bang, rows.length]);
    if (!rows.length) { sh.getRange(1, 1).setValue('(trống)'); return; }
    const cols = [];
    rows.forEach(function (r) { Object.keys(r).forEach(function (k) { if (cols.indexOf(k) < 0) cols.push(k); }); });
    const values = [cols].concat(rows.map(function (r) { return cols.map(function (c) { return oTinh_(r[c]); }); }));
    const range = sh.getRange(1, 1, values.length, cols.length);
    range.setNumberFormat('@');
    range.setValues(values);
    sh.setFrozenRows(1);
    sh.getRange(1, 1, 1, cols.length).setFontWeight('bold');
  });

  const tt = ss.insertSheet('Thông tin', 0);
  const dau = [
    ['Sao lưu dữ liệu Supabase – Điều độ cont chuối', ''],
    ['Thời điểm', Utilities.formatDate(bayGio, MUI_GIO, 'HH:mm dd/MM/yyyy')],
    ['Dự án', SUPABASE_URL],
    ['', ''],
    ['Bảng', 'Số dòng']
  ].concat(tongHop);
  tt.getRange(1, 1, dau.length, 2).setValues(dau);
  tt.getRange(1, 1).setFontWeight('bold');
  tt.getRange(5, 1, 1, 2).setFontWeight('bold');
  tt.autoResizeColumns(1, 2);

  DriveApp.getFileById(ss.getId()).moveTo(thuMuc);
  Logger.log('Đã sao lưu: ' + ten + ' — ' + tongHop.map(function (x) { return x[0] + '=' + x[1]; }).join(', '));
}

function layThuMuc_() {
  const it = DriveApp.getFoldersByName(TEN_THU_MUC);
  return it.hasNext() ? it.next() : DriveApp.createFolder(TEN_THU_MUC);
}

function oTinh_(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'object') v = JSON.stringify(v);
  if (typeof v === 'string' && v.length > 49000) return v.slice(0, 49000) + '…(cắt bớt, xem file .json)';
  return v;
}
