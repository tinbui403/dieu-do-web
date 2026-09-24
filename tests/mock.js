(function(){
  const FX = window.__FX; window.__LOG = []; window.__ERR = [];
  function src(t){ return ({cont:FX.cont_all, lo:FX.lo, lo_tong_hop:FX.lo, goi_y:FX.goi_y, kho:FX.kho, nha_xe:FX.nha_xe, bai_tam:FX.bai_tam, cau_hinh:FX.cau_hinh, khach_hang:FX.khach_hang, hang_tau:FX.hang_tau, cang_den:FX.cang_den, cang_ha:FX.cang_ha, nhan_vien:FX.nhan_vien, chi_phi_cont:FX.chi_phi_cont || (FX.chi_phi_cont = []), bang_gia_xe:FX.bang_gia_xe || (FX.bang_gia_xe = [{nha_xe:'HLS', khu_vuc:'Tất cả', loai:'cat_mooc', gia:1500000}]), sao_luu_nhat_ky:FX.sao_luu_nhat_ky || (FX.sao_luu_nhat_ky = [{id:1, ten:'Sao lưu Supabase 20-09-2026', url:'https://docs.google.com/x', luc:'2026-09-20T08:02:15Z'}]), lo_da_don:[], lo_su_co:FX.lo_su_co || (FX.lo_su_co = []), thong_tin_cu:FX.thong_tin_cu || (FX.thong_tin_cu = []), booking:FX.booking || (FX.booking = []), booking_tong_hop:bkTH(), nhat_ky:FX.nhat_ky || (FX.nhat_ky = [{id:1, bang:'lo', khoa:'604A', hanh_dong:'sua', thay_doi:{closing:['2026-09-20T04:11:00+00:00','2026-09-21T03:00:00+00:00'], da_kiem_dich:[false,true]}, nguoi:'tinbui403@gmail.com', luc:'2026-09-20T04:20:00+00:00'}, {id:2, bang:'cont', khoa:'X', hanh_dong:'xoa', thay_doi:{so_cont:'ABCU1234567'}, nguoi:'tinbui403@gmail.com', luc:'2026-09-20T04:21:00+00:00'}])})[t] || []; }
  // ---- Booking (mô phỏng migration 20260924150000: view booking_tong_hop + trigger lo_dong_bo_booking) ----
  function bkTH(){ return (FX.booking || []).map(b => { const ls = FX.lo.filter(l => l.so_booking === b.so_booking && !l.da_huy); const nC = l => FX.cont_all.filter(c => c.lo === l.lo && c.trang_thai !== '9').length;
    return Object.assign({}, b, { so_lo:ls.length, cont_ke_hoach:ls.reduce((a, l) => a + (l.so_luong_cont || 0), 0), cont_thuc_te:ls.reduce((a, l) => a + nC(l), 0), cont_da_xep:ls.reduce((a, l) => a + Math.max(l.so_luong_cont || 0, nC(l)), 0), cac_lo:ls.map(l => l.lo + (l.khach_hang ? ' (' + l.khach_hang + ')' : '')).join(', ') || null }); }); }
  function loTrig(p, old){ const norm = v => { v = (v == null ? '' : String(v)).toUpperCase().trim(); return v || null; };
    if ('booking' in p) p.booking = norm(p.booking); if ('so_booking' in p) p.so_booking = norm(p.so_booking);
    let moi = false;
    if (!old) { if (p.so_booking == null) p.so_booking = p.booking || null; moi = true; }
    else if ('so_booking' in p && p.so_booking !== (old.so_booking || null)) moi = true;
    else if ('booking' in p && p.booking !== (old.booking || null)) { p.so_booking = p.booking; moi = true; }
    else return;
    if (p.so_booking == null) { p.booking = null; return; }
    p.booking = p.so_booking;
    const B = FX.booking || (FX.booking = []), b = B.find(x => x.so_booking === p.so_booking), cur = Object.assign({}, old || {}, p);
    if (!b) B.push({ so_booking:p.so_booking, hang_tau:cur.hang_tau || null, ten_tau:cur.ten_tau || null, chuyen:null, cang_den:cur.cang_den || null, etd:cur.etd || null, eta:cur.eta || null, so_luong_cont:null, ghi_chu:null, nguon:'tự tạo từ lô ' + cur.lo, cap_nhat_luc:new Date().toISOString(), nguoi_cap_nhat:'tinbui403@gmail.com' });
    else if (moi) ['hang_tau', 'ten_tau', 'cang_den', 'etd', 'eta'].forEach(k => { if (cur[k] == null && b[k] != null) p[k] = b[k]; }); }
  function qb(table){
    const st = {table, f:[], op:'select'};
    const api = {
      select(cols, opts){ st.cols = cols; if (opts && opts.head) st.head = true; return api; },
      in(c, v){ st.f.push(r => v.indexOf(r[c]) > -1); return api; },
      eq(c, v){ st.eqc = c; st.eqv = v; st.f.push(r => r[c] === v); return api; },
      or(s){ st.or = s; return api; }, order(){ return api; }, limit(n){ st.limit = n; return api; }, gte(){ return api; },
      ilike(c, v){ const re = new RegExp('^' + String(v).replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*') + '$', 'i'); st.f.push(r => re.test(String(r[c] || ''))); return api; },
      single(){ st.single = true; return api; },
      update(p){ st.op = 'update'; st.p = p; return api; }, insert(p){ st.op = 'insert'; st.p = p; return api; }, upsert(p){ st.op = 'upsert'; st.p = p; return api; }, delete(){ st.op = 'delete'; return api; },
      then(res, rej){ return new Promise(r => setTimeout(r, 5)).then(run).then(res, rej); }
    };
    function run(){
      window.__LOG.push([table, st.op, JSON.stringify(st.p || null), st.eqc, st.eqv]);
      const arr = src(table);
      if (st.op === 'update') { arr.filter(r => r[st.eqc] === st.eqv).forEach(r => { const p = Object.assign({}, st.p); if (table === 'lo') loTrig(p, r); Object.assign(r, p); }); return {data:null, error:null}; }
      if (st.op === 'delete') { for (let i = arr.length - 1; i >= 0; i--) if (arr[i][st.eqc] === st.eqv) arr.splice(i, 1); return {data:null, error:null}; }
      if (st.op === 'upsert') { (Array.isArray(st.p) ? st.p : [st.p]).forEach(p => { const i = arr.findIndex(r => r.nha_xe === p.nha_xe && r.khu_vuc === p.khu_vuc && r.loai === p.loai); if (i > -1) Object.assign(arr[i], p); else arr.push(Object.assign({}, p)); }); return {data:null, error:null}; }
      if (st.op === 'insert') { const rows = Array.isArray(st.p) ? st.p : [st.p];
        if (table === 'booking') { for (const p of rows) { p.so_booking = String(p.so_booking || '').toUpperCase().trim(); if (!p.so_booking) return {data:null, error:{message:'null value in column "so_booking"'}}; if (arr.some(r => r.so_booking === p.so_booking)) return {data:null, error:{message:'duplicate key value violates unique constraint "booking_pkey"'}}; arr.push(Object.assign({cap_nhat_luc:new Date().toISOString(), nguoi_cap_nhat:'tinbui403@gmail.com'}, p)); } return {data:null, error:null}; }
        rows.forEach((p, i) => { const r = Object.assign({id:'NEW' + arr.length + '-' + i}, p); if (table === 'lo') loTrig(r, null); arr.push(r); }); return {data:null, error:null}; }
      if (st.head) return {data:null, count:FX.shipped, error:null};
      if (table === 'cont' && st.cols && st.cols.indexOf('kho,nha_xe') === 0) return {data:FX.recent, error:null};
      let d = arr.filter(r => st.f.every(fn => fn(r)));
      if (table === 'cont' && st.or && st.limit === 60) { const m = st.or.match(/%([^%]+)%/); const qq = m ? m[1].toUpperCase() : ''; d = arr.filter(r => ['so_cont','so_seal','lo','ma_don','kho','khach_hang'].some(k => String(r[k] || '').toUpperCase().indexOf(qq) > -1)).slice(0, 60); }
      if (st.single) return {data:d[0] || null, error: d[0] ? null : {message:'not found'}};
      return {data:d, error:null};
    }
    return api;
  }
  window.supabase = { createClient(){ return {
    from: qb,
    rpc(name, args){ window.__LOG.push(['rpc', name, JSON.stringify(args || null)]);
      if (name === 'xoa_lo') { const n = FX.cont_all.filter(c => c.lo === args.p_lo).length; FX.cont_all = FX.cont_all.filter(c => c.lo !== args.p_lo); FX.lo.splice(FX.lo.findIndex(l => l.lo === args.p_lo), 1); return Promise.resolve({data:n, error:null}); }
      if (name === 'eport_gui_yeu_cau') return Promise.resolve({data:3, error:null});
      if (name === 'eport_xu_ly_ket_qua') { const l = FX.lo.find(x => x.lo === '604A'); if (l) { l.closing_eport = '2026-09-20T18:30:00+00:00'; l.eport_chuyen = '71N'; l.eport_tau = 'XIN AN'; l.eport_cang = 'SPITC'; l.cang_ha = null; } return Promise.resolve({data:{da_xu_ly:3, lo_thay_doi:5, con_cho:0}, error:null}); }
      if (name === 'lo_co_the_don') return Promise.resolve({data:[{lo:'390', booking:'BK390', ten_tau:'MERATUS JAYAGIRI', etd:'2026-06-05', so_cont:4, ban_sao_luu:'Sao lưu Supabase 20-09-2026'}, {lo:'391', booking:'BK391', ten_tau:'X', etd:'2026-06-06', so_cont:3, ban_sao_luu:'Sao lưu Supabase 20-09-2026'}], error:null});
      if (name === 'don_du_lieu') return Promise.resolve({data:args.p_ds.length, error:null});
      if (name === 'xoa_nha_xe' || name === 'xoa_kho') return Promise.resolve({data:'ngung', error:null});
      if (name === 'xoa_nhan_vien') { FX.nhan_vien = FX.nhan_vien.filter(v => v.email !== args.p_email); return Promise.resolve({data:null, error:null}); }
      if (name === 'huy_lo') { const l = FX.lo.find(x => x.lo === args.p_lo); Object.assign(l, {da_huy:true, ly_do_huy:args.p_ly_do, huy_boi:'tinbui403@gmail.com', huy_luc:new Date().toISOString(), so_cont_dang_chay:0}); let n = 0; FX.cont_all.forEach(c => { if (c.lo === args.p_lo && c.trang_thai === '1') { c.trang_thai = '9'; c.huy_theo_lo = true; n++; } }); return Promise.resolve({data:n, error:null}); }
      if (name === 'khoi_phuc_lo') { const l = FX.lo.find(x => x.lo === args.p_lo); Object.assign(l, {da_huy:false, ly_do_huy:null}); let n = 0; FX.cont_all.forEach(c => { if (c.lo === args.p_lo && c.huy_theo_lo) { c.trang_thai = '1'; c.huy_theo_lo = false; n++; } }); return Promise.resolve({data:n, error:null}); }
      if (name === 'goi_y_booking') { const a = args || {}, t = new Date(Date.now() + 7 * 36e5).toISOString().slice(0, 10), th = bkTH();
        const B = (FX.booking || []).filter(b => (!b.etd || b.etd >= t) && (!a.p_cang_den || !b.cang_den || b.cang_den === a.p_cang_den));
        const d = B.map(b => { const x = th.find(y => y.so_booking === b.so_booking) || {}, xep = x.cont_da_xep || 0, con = b.so_luong_cont == null ? null : b.so_luong_cont - xep, n = a.p_so_cont || 1;
          const dd = a.p_ngay_tau && b.etd ? Math.round((new Date(b.etd) - new Date(a.p_ngay_tau)) / 864e5) : null;
          const diem = (a.p_cang_den && b.cang_den === a.p_cang_den ? 50 : 0) + (dd === null ? 10 : dd === 0 ? 40 : Math.abs(dd) <= 2 ? 30 : Math.abs(dd) <= 5 ? 15 : 0) + (!a.p_hang_tau ? 0 : b.hang_tau === a.p_hang_tau ? 20 : -30) + (con === null ? 5 : con >= n ? 25 : -40);
          return Object.assign({}, b, { da_xep:xep, con_lai:con, diem, ly_do:[a.p_cang_den && b.cang_den === a.p_cang_den ? 'đúng cảng' : '', dd === 0 ? 'đúng ngày tàu' : b.etd ? 'ETD ' + b.etd.slice(8) + '/' + b.etd.slice(5, 7) : 'chưa có ETD', con === null ? 'chưa ghi số cont' : con >= n ? 'còn ' + con + ' chỗ' : 'THIẾU CHỖ (còn ' + Math.max(con, 0) + ')'].filter(Boolean).join(' · ') }); }).sort((x, y) => y.diem - x.diem).slice(0, 10);
        return Promise.resolve({data:d, error:null}); }
      if (name === 'xoa_cont') { FX.cont_all = FX.cont_all.filter(c => c.id !== args.p_id); return Promise.resolve({data:null, error:null}); }
      return Promise.resolve(name === 'toi_la_ai' ? {data:[{email:'tinbui403@gmail.com', ho_ten:'Tín', vai_tro:'Quản lý', ngon_ngu:'vi', nha_xe:null}], error:null} : {data:60, error:null}); },
    auth: { getSession(){ return Promise.resolve({data:{session:{user:{email:'tinbui403@gmail.com'}}}}); }, onAuthStateChange(){}, signOut(){ return Promise.resolve(); }, signInWithPassword(o){ window.__LOG.push(['auth','signIn',o.email]); return Promise.resolve(o.password==='sai123' ? {error:{message:'Invalid login credentials'}} : {error:null}); }, updateUser(o){ window.__LOG.push(['auth','updateUser',o.password]); return Promise.resolve({data:{}, error:null}); }, signUp(){ return Promise.resolve({data:{session:null}, error:null}); } },
    channel(){ const c = { on(){ return c; }, subscribe(cb){ setTimeout(() => cb('SUBSCRIBED'), 10); return c; } }; return c; }
  }; } };
})();
