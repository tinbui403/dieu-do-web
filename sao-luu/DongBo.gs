/**
 * ĐỒNG BỘ – thêm vào dự án Apps Script "Sao lưu Supabase điều độ" (cùng dự án với SaoLuuSupabase.gs,
 * dùng lại SUPABASE_URL, SUPABASE_KEY, MA_SAO_LUU, TEN_THU_MUC, MUI_GIO, GIO_CHAY khai báo trong file đó).
 *
 *  - dongBoMaKDTV(): mỗi giờ đọc file PQS NEW, trang "QUẢN LÝ TỔNG" (cột A = số lô, cột B = mã TV)
 *                    và điền Mã KDTV cho các lô trên web điều độ.
 *  - doGet(): nút "Cập nhật mã KDTV" trên web gọi tới đây để đồng bộ NGAY (không chờ 1 giờ).
 *  - saoLuuVaGhiNhan(): sao lưu như cũ, rồi báo cho web biết đã có bản sao lưu (để gợi ý dọn dữ liệu cũ).
 *
 * CÀI ĐẶT (làm 1 lần): chọn hàm  caiDatDongBo  → Chạy.
 *
 * DEPLOY WEB APP (làm 1 lần, để nút web bấm được):
 *   1. Đổi KDTV_WEBAPP_TOKEN dưới đây thành một chuỗi bí mật bất kỳ (vd chuỗi ngẫu nhiên dài).
 *   2. Deploy → New deployment → chọn "Web app".
 *      - Execute as:  Me (chính bạn)
 *      - Who has access:  Anyone  (bắt buộc để nút web gọi được; token ở dưới bảo vệ)
 *   3. Copy URL /exec, ghép token vào cuối:  <URL_exec>?token=<KDTV_WEBAPP_TOKEN>
 *   4. Dán chuỗi đầy đủ đó vào web điều độ: Danh mục → Cấu hình → tham số "URL đồng bộ KDTV".
 */
const PQS_FILE_ID = '1yUjvcYvneW-83pVhLhkjFLjHQZJfiijQsfYGwPWSLOI';
const PQS_TRANG = 'QUẢN LÝ TỔNG';
const KDTV_WEBAPP_TOKEN = 'DIEN_TOKEN_KDTV_VAO_DAY';  // ⚠ mã bí mật — KHÔNG đưa lên GitHub.
// Bản đang chạy đã đặt token thật trong Apps Script (21/09/2026) và ghép sẵn vào
// cấu hình "URL đồng bộ KDTV" trên web. Chỉ điền lại khi cài lại từ đầu.

// Nút "Cập nhật mã KDTV" trên web gọi GET tới đây. Trả JSON { ok, n, doc } hoặc { ok:false, loi }.
function doGet(e) {
  var out = ContentService.createTextOutput().setMimeType(ContentService.MimeType.JSON);
  try {
    var token = (e && e.parameter && e.parameter.token) ? e.parameter.token : '';
    if (token !== KDTV_WEBAPP_TOKEN) { out.setContent(JSON.stringify({ ok: false, loi: 'Sai token' })); return out; }
    var r = dongBoMaKDTVChiTiet();
    out.setContent(JSON.stringify({ ok: true, n: r.n, doc: r.doc }));
  } catch (err) {
    out.setContent(JSON.stringify({ ok: false, loi: String((err && err.message) || err) }));
  }
  return out;
}

function caiDatDongBo() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    const f = t.getHandlerFunction();
    if (f === 'saoLuu' || f === 'saoLuuVaGhiNhan' || f === 'dongBoMaKDTV') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('saoLuuVaGhiNhan').timeBased().everyDays(1).atHour(GIO_CHAY).inTimezone(MUI_GIO).create();
  ScriptApp.newTrigger('dongBoMaKDTV').timeBased().everyHours(1).create();
  dongBoMaKDTV();
}

function goiSupabase_(ham, thamSo) {
  const res = UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/rpc/' + ham, {
    method: 'post',
    contentType: 'application/json',
    headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY },
    payload: JSON.stringify(thamSo),
    muteHttpExceptions: true
  });
  if (res.getResponseCode() !== 200 && res.getResponseCode() !== 204) {
    throw new Error('Supabase ' + ham + ' lỗi ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
  }
  const t = res.getContentText();
  return t ? JSON.parse(t) : null;
}

// Đọc Sheet + đẩy sang Supabase, trả cả số dòng đọc (doc) lẫn số lô cập nhật (n).
function dongBoMaKDTVChiTiet() {
  const sh = SpreadsheetApp.openById(PQS_FILE_ID).getSheetByName(PQS_TRANG);
  if (!sh) throw new Error('Không tìm thấy trang "' + PQS_TRANG + '" trong file PQS NEW');
  const last = sh.getLastRow();
  if (last < 2) return { n: 0, doc: 0 };
  const ds = sh.getRange(2, 1, last - 1, 2).getDisplayValues()
    .map(function (r) { return { lo: String(r[0]).trim().toUpperCase(), ma: String(r[1]).trim() }; })
    .filter(function (x) { return x.lo !== '' && x.ma !== ''; });
  const n = goiSupabase_('cap_nhat_ma_kdtv', { p_ma: MA_SAO_LUU, p_ds: ds });
  Logger.log('Đồng bộ Mã KDTV: đọc ' + ds.length + ' dòng, cập nhật ' + n + ' lô');
  return { n: n, doc: ds.length };
}

function dongBoMaKDTV() {
  return dongBoMaKDTVChiTiet().n;
}

function saoLuuVaGhiNhan() {
  saoLuu();
  const ten = 'Sao lưu Supabase ' + Utilities.formatDate(new Date(), MUI_GIO, 'dd-MM-yyyy');
  let url = null;
  const fo = DriveApp.getFoldersByName(TEN_THU_MUC);
  if (fo.hasNext()) { const f = fo.next().getFilesByName(ten); if (f.hasNext()) url = f.next().getUrl(); }
  goiSupabase_('ghi_nhan_sao_luu', { p_ma: MA_SAO_LUU, p_ten: ten, p_url: url, p_so_dong: null });
}
