(function(){
  const FX = window.__FX; window.__LOG = []; window.__ERR = [];
  function src(t){ return ({cont:FX.cont_all, lo:FX.lo, lo_tong_hop:FX.lo, goi_y:FX.goi_y, kho:FX.kho, nha_xe:FX.nha_xe, bai_tam:FX.bai_tam, cau_hinh:FX.cau_hinh, khach_hang:FX.khach_hang, hang_tau:FX.hang_tau, cang_den:FX.cang_den, cang_ha:FX.cang_ha, nhan_vien:FX.nhan_vien, chi_phi_cont:FX.chi_phi_cont || (FX.chi_phi_cont = []), bang_gia_xe:FX.bang_gia_xe || (FX.bang_gia_xe = [{nha_xe:'HLS', khu_vuc:'Tất cả', loai:'cat_mooc', gia:1500000}]), sao_luu_nhat_ky:FX.sao_luu_nhat_ky || (FX.sao_luu_nhat_ky = [{id:1, ten:'Sao lưu Supabase 20-09-2026', url:'https://docs.google.com/x', luc:'2026-09-20T08:02:15Z'}]), lo_da_don:[], nhat_ky:FX.nhat_ky || (FX.nhat_ky = [{id:1, bang:'lo', khoa:'604A', hanh_dong:'sua', thay_doi:{closing:['2026-09-20T04:11:00+00:00','2026-09-21T03:00:00+00:00'], da_kiem_dich:[false,true]}, nguoi:'tinbui403@gmail.com', luc:'2026-09-20T04:20:00+00:00'}, {id:2, bang:'cont', khoa:'X', hanh_dong:'xoa', thay_doi:{so_cont:'ABCU1234567'}, nguoi:'tinbui403@gmail.com', luc:'2026-09-20T04:21:00+00:00'}])})[t] || []; }
  function qb(table){
    const st = {table, f:[], op:'select'};
    const api = {
      select(cols, opts){ st.cols = cols; if (opts && opts.head) st.head = true; return api; },
      in(c, v){ st.f.push(r => v.indexOf(r[c]) > -1); return api; },
      eq(c, v){ st.eqc = c; st.eqv = v; st.f.push(r => r[c] === v); return api; },
      or(s){ st.or = s; return api; }, order(){ return api; }, limit(n){ st.limit = n; return api; }, gte(){ return api; },
      single(){ st.single = true; return api; },
      update(p){ st.op = 'update'; st.p = p; return api; }, insert(p){ st.op = 'insert'; st.p = p; return api; }, upsert(p){ st.op = 'upsert'; st.p = p; return api; }, delete(){ st.op = 'delete'; return api; },
      then(res, rej){ return new Promise(r => setTimeout(r, 5)).then(run).then(res, rej); }
    };
    function run(){
      window.__LOG.push([table, st.op, JSON.stringify(st.p || null), st.eqc, st.eqv]);
      const arr = src(table);
      if (st.op === 'update') { arr.filter(r => r[st.eqc] === st.eqv).forEach(r => Object.assign(r, st.p)); return {data:null, error:null}; }
      if (st.op === 'delete') { for (let i = arr.length - 1; i >= 0; i--) if (arr[i][st.eqc] === st.eqv) arr.splice(i, 1); return {data:null, error:null}; }
      if (st.op === 'upsert') { (Array.isArray(st.p) ? st.p : [st.p]).forEach(p => { const i = arr.findIndex(r => r.nha_xe === p.nha_xe && r.khu_vuc === p.khu_vuc && r.loai === p.loai); if (i > -1) Object.assign(arr[i], p); else arr.push(Object.assign({}, p)); }); return {data:null, error:null}; }
      if (st.op === 'insert') { (Array.isArray(st.p) ? st.p : [st.p]).forEach((p, i) => arr.push(Object.assign({id:'NEW' + arr.length + '-' + i}, p))); return {data:null, error:null}; }
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
      if (name === 'xoa_cont') { FX.cont_all = FX.cont_all.filter(c => c.id !== args.p_id); return Promise.resolve({data:null, error:null}); }
      return Promise.resolve(name === 'toi_la_ai' ? {data:[{email:'tinbui403@gmail.com', ho_ten:'Tín', vai_tro:'Quản lý', ngon_ngu:'vi', nha_xe:null}], error:null} : {data:60, error:null}); },
    auth: { getSession(){ return Promise.resolve({data:{session:{user:{email:'tinbui403@gmail.com'}}}}); }, onAuthStateChange(){}, signOut(){ return Promise.resolve(); }, signInWithPassword(o){ window.__LOG.push(['auth','signIn',o.email]); return Promise.resolve(o.password==='sai123' ? {error:{message:'Invalid login credentials'}} : {error:null}); }, updateUser(o){ window.__LOG.push(['auth','updateUser',o.password]); return Promise.resolve({data:{}, error:null}); }, signUp(){ return Promise.resolve({data:{session:null}, error:null}); } },
    channel(){ const c = { on(){ return c; }, subscribe(cb){ setTimeout(() => cb('SUBSCRIBED'), 10); return c; } }; return c; }
  }; } };
})();
