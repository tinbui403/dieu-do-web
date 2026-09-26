// Edge Function: doc-booking-pdf — đọc file PDF booking bằng Gemini (Google AI Studio) và trả về
// các ô cần cho bảng booking để NGƯỜI DUYỆT rồi lưu. KHÔNG lưu file PDF ở đâu cả (chỉ đi qua bộ nhớ).
//
// Secret cần đặt trong Supabase (Edge Functions → Secrets): GEMINI_API_KEY   (không bao giờ đưa vào web)
// Deploy: Dashboard → Edge Functions → Deploy via Editor (tắt "Verify JWT with legacy secret" như hàm quan-ly-nhan-vien)
//
// Body JSON gửi lên (cần header Authorization: Bearer <access_token> của người đã đăng nhập, vai trò QL/ĐĐ/CSKH):
//   { action:'ping' }                                   → thử API key, trả tên model dùng
//   { action:'doc_pdf', pdf_base64:'...', ten_file:'x.pdf' } → { booking:{...}, ghi_chu_ai:'...', model:'...' }
//   { action:'chat', messages:[{role:'user'|'model', text}], context:'...' } → { text }   (dùng cho chatbot Phase IV)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') || '';
const MODELS = ['gemini-3.5-flash', 'gemini-3.1-flash-lite', 'gemini-2.5-flash', 'gemini-flash-latest'];   // thử lần lượt (theo danh sách action=models 26/09), model nào chạy thì dùng
const MAX_PDF_BYTES = 8 * 1024 * 1024;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

const PROMPT_PDF = `Bạn là nhân viên chứng từ hãng tàu. Đọc file booking confirmation (PDF) đính kèm và trích đúng các thông tin sau, trả về DUY NHẤT một JSON (không markdown, không giải thích):
{
 "so_booking": "số booking / booking number (chữ IN HOA, bỏ khoảng trắng thừa)",
 "hang_tau": "tên hãng tàu viết tắt thường dùng (VD: EVERGREEN, MAERSK, OOCL, YANGMING, WANHAI, ONE, COSCO, MSC, CMA, HAPAG, ZIM, HMM, SITC, KMTC, TSL)",
 "ten_tau": "tên tàu (vessel name), IN HOA",
 "chuyen": "số chuyến (voyage)",
 "cang_den": "cảng đến / port of discharge — tên tiếng Anh IN HOA (VD: SHANGHAI, NINGBO, TIANJIN, QINGDAO, DALIAN, NANSHA)",
 "etd": "ngày tàu chạy dự kiến ETD dạng YYYY-MM-DD (null nếu không có)",
 "eta": "ngày đến dự kiến ETA dạng YYYY-MM-DD (null nếu không có)",
 "closing": "giờ cắt máng / cut-off / closing time dạng YYYY-MM-DD HH:MM (null nếu không có)",
 "so_luong_cont": số cont (số nguyên; null nếu không rõ),
 "loai_cont": "loại cont VD 40HC / 20DC / 40RH",
 "cang_di": "cảng đi / port of loading (VD CAT LAI, SPITC, HIEP PHUOC)",
 "ghi_chu": "những điểm đáng chú ý khác trong booking (ngắn gọn, tiếng Việt)"
}
Nếu một ô không tìm thấy thì để null. Không bịa số.`;

async function gemini(model: string, parts: unknown[], jsonMode: boolean) {
  const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + model + ':generateContent';
  const body: Record<string, unknown> = { contents: [{ role: 'user', parts }] };
  if (jsonMode) body.generationConfig = { responseMimeType: 'application/json', temperature: 0.1 };
  const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY }, body: JSON.stringify(body) });
  const txt = await r.text();
  if (!r.ok) throw new Error('Gemini ' + model + ' HTTP ' + r.status + ': ' + txt.slice(0, 300));
  const d = JSON.parse(txt);
  const out = (d.candidates?.[0]?.content?.parts || []).map((p: { text?: string }) => p.text || '').join('');
  if (!out) throw new Error('Gemini không trả nội dung: ' + txt.slice(0, 200));
  return out;
}
async function geminiAny(parts: unknown[], jsonMode: boolean) {
  const errs: string[] = [];
  for (const m of MODELS) {
    try { return { model: m, text: await gemini(m, parts, jsonMode) }; }
    catch (e) { const s = String(e); errs.push(s.slice(0, 220)); if (!/HTTP (400|404|429|503)/.test(s)) throw e; }
  }
  throw new Error(errs.join(' | ') || 'Không gọi được Gemini');
}
function parseJson(s: string) {
  const t = s.trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
  try { return JSON.parse(t); } catch { const m = t.match(/\{[\s\S]*\}/); if (m) return JSON.parse(m[0]); throw new Error('AI không trả JSON hợp lệ: ' + t.slice(0, 200)); }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    if (req.method !== 'POST') throw new Error('Method not allowed');
    if (!GEMINI_API_KEY) throw new Error('Chưa đặt secret GEMINI_API_KEY trong Supabase');

    // Người gọi phải đăng nhập và là QL / ĐĐ / CSKH (dùng chính JWT của họ để xác thực)
    const authHeader = req.headers.get('Authorization') || '';
    const jwt = authHeader.replace(/^Bearer\s+/i, '');
    const apikey = req.headers.get('apikey') || '';
    const laSecret = !!apikey && (apikey === SERVICE_ROLE_KEY || (Deno.env.get('SUPABASE_SECRET_KEYS') || '').includes(apikey)) || (!!jwt && jwt === SERVICE_ROLE_KEY);
    if (!jwt && !laSecret) throw new Error('Thiếu token đăng nhập');
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    if (!laSecret) {   // gọi bằng secret key (chỉ từ Dashboard / server) thì bỏ qua bước kiểm tra nhân viên
      const asCaller = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } });
      const { data: userData, error: userErr } = await asCaller.auth.getUser(jwt);
      if (userErr || !userData?.user?.email) throw new Error('Token không hợp lệ');
      const { data: nv } = await admin.from('nhan_vien').select('vai_tro, hoat_dong').eq('email', userData.user.email.toLowerCase()).maybeSingle();
      if (!nv || nv.hoat_dong === false || !['Quản lý', 'Điều độ', 'CSKH'].includes(nv.vai_tro)) throw new Error('Bạn không có quyền dùng chức năng này');
    }

    const body = await req.json().catch(() => ({}));
    const action = body.action;

    if (action === 'models') {
      const r = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200', { headers: { 'x-goog-api-key': GEMINI_API_KEY } });
      const txt = await r.text(); if (!r.ok) throw new Error('HTTP ' + r.status + ': ' + txt.slice(0, 300));
      const d = JSON.parse(txt);
      return json({ ok: true, models: (d.models || []).filter((x: { supportedGenerationMethods?: string[] }) => (x.supportedGenerationMethods || []).includes('generateContent')).map((x: { name: string }) => x.name) });
    }
    if (action === 'ping') {
      const r = await geminiAny([{ text: 'Trả lời đúng một chữ: OK' }], false);
      return json({ ok: true, model: r.model, text: r.text.trim().slice(0, 50) });
    }

    if (action === 'doc_pdf') {
      const b64 = String(body.pdf_base64 || '').replace(/^data:.*?;base64,/, '');
      if (!b64) throw new Error('Thiếu file PDF');
      if (b64.length * 0.75 > MAX_PDF_BYTES) throw new Error('File PDF quá lớn (tối đa 8 MB)');
      const r = await geminiAny([{ inline_data: { mime_type: 'application/pdf', data: b64 } }, { text: PROMPT_PDF }], true);
      const bk = parseJson(r.text);
      // chuẩn hoá nhẹ; việc khớp danh mục (hãng tàu / cảng đến) để web làm vì web có danh mục
      if (bk.so_booking) bk.so_booking = String(bk.so_booking).toUpperCase().replace(/\s+/g, ' ').trim();
      if (bk.so_luong_cont != null && isNaN(Number(bk.so_luong_cont))) bk.so_luong_cont = null;
      return json({ ok: true, model: r.model, booking: bk, ten_file: body.ten_file || null });
    }

    if (action === 'chat') {
      const ctx = String(body.context || '').slice(0, 40000);
      // Web co the gui 'contents' (dinh dang Gemini day du, ho tro function calling)
      // hoac 'messages' (dinh dang cu {role,text}) — fallback tuong thich nguoc.
      let contents: unknown[];
      if (Array.isArray(body.contents)) {
        contents = body.contents.slice(-40);
      } else {
        const msgs = Array.isArray(body.messages) ? body.messages.slice(-24) : [];
        contents = msgs.map((m: { role: string; text: string }) => ({ role: m.role === 'model' ? 'model' : 'user', parts: [{ text: String(m.text || '').slice(0, 10000) }] }));
      }
      const tools = Array.isArray(body.tools) ? body.tools : null;
      const stTable = `Bảng trạng thái cont (trang_thai):
1=Đơn chờ lên (chờ cắt rỗng)  2=Đang đóng hàng  3=Đầy chờ kéo
4=Ở bãi tạm     5=Đã hạ cảng       6=Đã lên tàu   9=Hủy/đổi cont`;
      const sys = `Bạn là trợ lý điều độ container của công ty Đại Cát Lâm. Hỗ trợ người dùng tra cứu thông tin vận chuyển.
Quy tắc:
- Trả lời bằng tiếng Việt, ngắn gọn, rõ ràng
- Dùng **in đậm** cho số cont, mã lô, trạng thái quan trọng
- Khi cần dữ liệu (lô, cont, booking, thống kê), HÃY GỌI CÔNG CỤ được cung cấp thay vì đoán; chỉ trả lời sau khi có kết quả công cụ
- Câu hỏi có ĐIỀU KIỆN LỌC (kho + trạng thái, lô + trạng thái, khách + trạng thái…) thì DÙNG loc_cont, KHÔNG dùng tra_cont (tra_cont chỉ để tìm 1 số cont/mã đơn cụ thể). Nếu loc_cont trả rỗng mới kết luận không có.

NGHIỆP VỤ ĐIỀU PHỐI KÉO CONT (rất quan trọng, tuân thủ đúng):
- "Kéo cont về cảng" = gom các cont ĐẦY CHỜ KÉO ở cùng KHU VỰC vào một chuyến xe cho tiết kiệm. Tiêu chí gộp: CÙNG KHU VỰC (bắt buộc), ưu tiên cont GẤP CLS, và nếu được thì cùng nhà xe.
- TUYỆT ĐỐI KHÔNG đòi hỏi cùng khách hàng khi kéo cont, và KHÔNG từ chối ghép vì khác khách. Cùng khách hàng CHỈ áp dụng khi GHÉP LÔ (gộp cont vào một lô), KHÁC hoàn toàn với kéo cont về.
- Cont "gấp" = sắp hoặc ĐÃ QUÁ hạn CLS; cont ĐÃ QUÁ HẠN là GẤP NHẤT (gio_con_lai âm). Với câu hỏi kéo cont / cont gấp / khu vực nào có cont gấp, DÙNG cont_gap_can_keo (đã xếp gấp trước, kèm khu_vuc và gio_con_lai) — KHÔNG tự kết luận "không có cont gấp" khi chưa gọi công cụ này.
- KHÔNG bịa số liệu, booking, tên khách; nếu công cụ trả về rỗng thì nói rõ không tìm thấy
- Nếu người dùng muốn thay đổi dữ liệu, mô tả rõ đề xuất (không tự lưu)
${stTable}
${ctx ? '\nBỐI CẢNH MÀN HÌNH (JSON):\n' + ctx : ''}`;
      let last = '';
      for (const m of MODELS) {
        try {
          const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + m + ':generateContent';
          const reqBody: Record<string, unknown> = { system_instruction: { parts: [{ text: sys }] }, contents };
          if (tools) reqBody.tools = tools;
          const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY }, body: JSON.stringify(reqBody) });
          const txt = await r.text();
          if (!r.ok) { last = 'Gemini ' + m + ' HTTP ' + r.status + ': ' + txt.slice(0, 300); if (/^(404|429|503)$/.test(String(r.status))) continue; throw new Error(last); }
          const d = JSON.parse(txt);
          const parts = d.candidates?.[0]?.content?.parts || [];
          const fnCall = parts.find((p: { functionCall?: unknown }) => p.functionCall);
          if (fnCall) {
            // AI yeu cau goi cong cu — tra ve cho web thuc thi query
            return json({ ok: true, model: m, functionCall: fnCall.functionCall, parts });
          }
          const text = parts.filter((p: { text?: string }) => p.text).map((p: { text?: string }) => p.text || '').join('');
          if (!text) { last = 'no text'; continue; }
          return json({ ok: true, model: m, text });
        } catch (e) { last = String(e); }
      }
      throw new Error(last || 'Không gọi được Gemini');
    }

    throw new Error('action không hợp lệ');
  } catch (e) {
    return json({ ok: false, error: (e as Error).message || String(e) }, 400);
  }
});
