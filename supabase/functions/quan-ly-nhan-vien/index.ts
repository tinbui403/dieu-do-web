// Edge Function: quan-ly-nhan-vien
// Cho phép Quản lý (vai_tro = 'Quản lý') tạo tài khoản đăng nhập (email + mật khẩu)
// cho nhân viên mới, hoặc đặt lại mật khẩu cho nhân viên đã có — TỪ TRONG APP,
// không cần vào Supabase Dashboard, và KHÔNG để lộ service_role key ra trình duyệt
// (key đó chỉ tồn tại ở đây, phía server).
//
// Deploy: supabase functions deploy quan-ly-nhan-vien
// (không cần thêm secret gì — SUPABASE_URL và SUPABASE_SERVICE_ROLE_KEY
//  đã có sẵn tự động trong mọi Edge Function của dự án).
//
// Body JSON gửi lên:
//   { action:'create_employee', email, password, ho_ten, vai_tro, ngon_ngu, nha_xe, hoat_dong }
//   { action:'set_password', email, password }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

const VAI_TRO_HOP_LE = ['Quản lý', 'Điều độ', 'CSKH', 'Nhà xe', 'Chỉ xem'];
const NGON_NGU_HOP_LE = ['vi', 'zh', 'both'];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    if (req.method !== 'POST') throw new Error('Method not allowed');

    const authHeader = req.headers.get('Authorization') || '';
    const jwt = authHeader.replace(/^Bearer\s+/i, '');
    if (!jwt) throw new Error('Thiếu token đăng nhập');

    // Xác thực người gọi bằng chính JWT của họ (không dùng service role để xác thực)
    const asCaller = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: userData, error: userErr } = await asCaller.auth.getUser(jwt);
    if (userErr || !userData?.user?.email) throw new Error('Token không hợp lệ');
    const callerEmail = userData.user.email.toLowerCase();

    // Từ đây dùng service role (chỉ nằm trên server) để kiểm tra quyền + thao tác admin
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: nv, error: nvErr } = await admin
      .from('nhan_vien')
      .select('vai_tro')
      .eq('email', callerEmail)
      .maybeSingle();
    if (nvErr) throw nvErr;
    if (!nv || nv.vai_tro !== 'Quản lý') throw new Error('Chỉ Quản lý (admin) mới được thực hiện thao tác này');

    const body = await req.json().catch(() => ({}));
    const action = body.action;

    if (action === 'create_employee') {
      const email = String(body.email || '').trim().toLowerCase();
      const password = String(body.password || '');
      const ho_ten = body.ho_ten ? String(body.ho_ten).trim() : null;
      const vai_tro = VAI_TRO_HOP_LE.includes(body.vai_tro) ? body.vai_tro : 'Điều độ';
      const ngon_ngu = NGON_NGU_HOP_LE.includes(body.ngon_ngu) ? body.ngon_ngu : 'vi';
      const nha_xe = body.nha_xe || null;
      const hoat_dong = body.hoat_dong !== false;

      if (!EMAIL_RE.test(email)) throw new Error('Email không hợp lệ');
      if (password.length < 6) throw new Error('Mật khẩu cần ít nhất 6 ký tự');

      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true, // admin đã tạo trực tiếp -> không bắt xác nhận email nữa
      });
      if (createErr) throw createErr;

      const { error: insErr } = await admin
        .from('nhan_vien')
        .insert({ email, ho_ten, vai_tro, ngon_ngu, nha_xe, hoat_dong });
      if (insErr) {
        // rollback tài khoản auth vừa tạo để tránh tài khoản mồ côi (có auth nhưng không có quyền)
        if (created?.user?.id) await admin.auth.admin.deleteUser(created.user.id);
        throw insErr;
      }

      return json({ ok: true });
    }

    if (action === 'set_password') {
      const email = String(body.email || '').trim().toLowerCase();
      const password = String(body.password || '');
      if (password.length < 6) throw new Error('Mật khẩu cần ít nhất 6 ký tự');

      // supabase-js chưa có getUserByEmail() phía admin -> tìm trong danh sách user
      let target = null;
      for (let page = 1; page <= 20 && !target; page++) {
        const { data: list, error: listErr } = await admin.auth.admin.listUsers({ page, perPage: 200 });
        if (listErr) throw listErr;
        target = list.users.find((u) => (u.email || '').toLowerCase() === email) || null;
        if (!list.users.length || list.users.length < 200) break;
      }
      if (!target) throw new Error('Không tìm thấy tài khoản đăng nhập cho email này');

      const { error: updErr } = await admin.auth.admin.updateUserById(target.id, { password });
      if (updErr) throw updErr;

      return json({ ok: true });
    }

    throw new Error('action không hợp lệ');
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e) }, 400);
  }
});
