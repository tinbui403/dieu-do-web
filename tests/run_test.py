import asyncio, json, os, pathlib
HERE = pathlib.Path(__file__).resolve().parent
URL = (HERE / 'test.html').as_uri()
os.makedirs(HERE / 'shots', exist_ok=True)
os.chdir(HERE)
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        ctx = await b.new_context(viewport={'width':1440,'height':900}, timezone_id='Asia/Ho_Chi_Minh', locale='vi-VN')
        pg = await ctx.new_page()
        errs = []
        pg.on('pageerror', lambda e: errs.append('pageerror: ' + str(e)))
        pg.on('console', lambda m: errs.append('console.' + m.type + ': ' + m.text) if m.type in ('error','warning') else None)
        await pg.route('**/fonts.googleapis.com/**', lambda r: r.abort())
        await pg.route('**/fonts.gstatic.com/**', lambda r: r.abort())
        await pg.goto(URL)
        await pg.wait_for_selector('.tile', timeout=8000)
        await pg.screenshot(path='shots/01_tong.png', full_page=True)
        for i, tab in enumerate(['goiy','homnay','taikho','bai','kd','lo','danhmuc']):
            await pg.click(f'.side [data-tab="{tab}"]')
            await pg.wait_for_timeout(250)
            await pg.screenshot(path=f'shots/{i+2:02d}_{tab}.png', full_page=True)
        # actions: suggestion approve
        await pg.click('.side [data-tab="goiy"]'); await pg.wait_for_timeout(200)
        cards = await pg.query_selector_all('.gy-main'); await cards[1].click(); await pg.wait_for_timeout(150)
        mooc = await pg.evaluate('(() => { const g = gyView(S.goiy.find(x => x.id === S.sel)); return [g.mooc, g.nx, g.locked]; })()')
        panel_txt = await pg.inner_text('.panel')
        if mooc[2]:
            assert mooc[0] == mooc[1] and ('kéo về được' in panel_txt) and not await pg.query_selector('select[data-on="gy-pick"]'), 'không khoá nhà xe theo mooc: ' + str(mooc)
        else:
            await pg.select_option('select[data-on="gy-pick"]', 'KLC'); await pg.wait_for_timeout(150)
        await pg.screenshot(path='shots/09_goiy_mooc.png')
        await pg.click('.panel [data-act="gy-approve"]'); await pg.wait_for_timeout(300)
        upd = await pg.evaluate('window.__LOG.filter(x => x[0] === "goi_y" && x[1] === "update").slice(-1)[0][2]')
        if mooc[2]: assert ('"nha_xe_chon":"' + mooc[0] + '"') in upd, 'duyệt sai nhà xe: ' + upd
        await pg.click('.panel [data-act="copy-gy"]'); await pg.wait_for_timeout(200)
        await pg.screenshot(path='shots/10_goiy_after.png', full_page=True)
        # homnay apply
        await pg.click('.side [data-tab="homnay"]'); await pg.wait_for_timeout(200)
        btn = await pg.query_selector('[data-act="gy-apply"]'); await btn.click(); await pg.wait_for_timeout(150)
        btn = await pg.query_selector('[data-act="gy-apply"]'); await btn.click(); await pg.wait_for_timeout(400)
        await pg.screenshot(path='shots/11_homnay_after.png', full_page=True)
        # tai kho move + drawer
        await pg.click('.side [data-tab="taikho"]'); await pg.wait_for_timeout(200)
        await pg.click('[data-act="move"]'); await pg.wait_for_timeout(400)
        await pg.click('.tr [data-act="open-cont"]'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='shots/12_drawer.png')
        await pg.fill('#f-cont input[name="du_kien_day"]', '2026-09-20T21:00')
        await pg.fill('#f-cont textarea[name="ghi_chu"]', 'thử ghi chú')
        await pg.click('#save-btn'); await pg.wait_for_timeout(400)
        # new lo
        await pg.click('.side [data-tab="lo"]'); await pg.wait_for_timeout(200)
        await pg.click('[data-act="new-lo"]'); await pg.wait_for_timeout(200)
        await pg.fill('#f-lo input[name="lo"]', '999T'); await pg.fill('#f-lo input[name="closing"]', '2026-09-22T10:00')
        await pg.screenshot(path='shots/13_newlo.png')
        await pg.click('#save-btn'); await pg.wait_for_timeout(500)
        # lô mới phải mở lại và hiện trong danh sách
        assert await pg.query_selector('#f-lo'), 'không mở lại lô mới'
        await pg.screenshot(path='shots/13b_newlo_saved.png')
        await pg.click('#drawer [data-act="new-cont"]'); await pg.wait_for_timeout(300)
        await pg.select_option('#f-cont select[name="kho"]', index=1)
        await pg.fill('#f-cont input[name="so_cont"]', 'test 1234567')
        await pg.click('#save-btn'); await pg.wait_for_timeout(500)
        txt = await pg.inner_text('#drawer'); assert 'TEST1234567' in txt, 'cont mới không hiện trong lô'
        await pg.screenshot(path='shots/13c_lo_with_cont.png')
        await pg.evaluate('closeDrawer()')
        await pg.click('[data-act="new-lo"]'); await pg.wait_for_timeout(200)
        await pg.fill('#f-lo input[name="lo"]', '998T'); await pg.click('#save-btn'); await pg.wait_for_timeout(500)
        await pg.click('#drawer [data-act="del-lo"]'); await pg.wait_for_timeout(100)
        await pg.click('#drawer [data-act="del-lo"]'); await pg.wait_for_timeout(500)
        assert not await pg.query_selector('#f-lo'), 'xoá lô không đóng'
        lolist = await pg.inner_text('#main'); assert '999T' in lolist and '998T' not in lolist, 'danh sách lô sai'
        # --- Lô: sắp xếp, số lượng + tạo sẵn đơn, hủy/khôi phục, lịch sử ---
        await pg.select_option('select[data-on="lo-sortk"]', 'lo'); await pg.wait_for_timeout(200)
        names = await pg.eval_on_selector_all('#main .tr [data-act="open-lo"]', 'els => els.map(e => e.textContent)')
        import re as _re
        assert names == sorted(names, key=lambda x: [int(p) if p.isdigit() else p for p in _re.split(r'(\d+)', x)]), 'sắp xếp theo lô sai: ' + str(names[:8])
        await pg.click('[data-act="lo-dir"]'); await pg.wait_for_timeout(200)
        names2 = await pg.eval_on_selector_all('#main .tr [data-act="open-lo"]', 'els => els.map(e => e.textContent)')
        assert names2 == names[::-1], 'đảo chiều sai'
        await pg.click('.th-sort[data-k="closing"]'); await pg.wait_for_timeout(200)
        await pg.screenshot(path='shots/40_lo_sort.png', full_page=True)
        await pg.click('[data-act="new-lo"]'); await pg.wait_for_timeout(200)
        await pg.fill('#f-lo input[name="lo"]', '700T'); await pg.fill('#f-lo input[name="so_luong_cont"]', '3')
        await pg.select_option('#f-lo select[name="d_kho"]', index=2); await pg.fill('#f-lo input[name="d_ma_don"]', 'HX 0920')
        await pg.screenshot(path='shots/41_newlo_form.png')
        await pg.click('#save-btn'); await pg.wait_for_timeout(600)
        ins = await pg.evaluate('window.__LOG.filter(x => x[0] === "cont" && x[1] === "insert").slice(-1)[0]')
        import json as _j
        rows = _j.loads(ins[2]); assert isinstance(rows, list) and len(rows) == 3 and rows[0]['ma_don'] == 'HX 0920' and 'd_kho' not in rows[0], 'không tạo đủ 3 đơn: ' + str(ins)
        lo_ins = await pg.evaluate('window.__LOG.filter(x => x[0] === "lo" && x[1] === "insert").slice(-1)[0][2]')
        assert '"d_kho"' not in lo_ins and '"so_luong_cont":3' in lo_ins, 'lô lưu sai: ' + lo_ins
        await pg.screenshot(path='shots/42_newlo_saved.png')
        # hủy lô
        await pg.fill('#huy-ly-do', 'Khách hủy đơn')
        await pg.click('[data-act="huy-lo"]'); await pg.wait_for_timeout(100); await pg.click('[data-act="huy-lo"]'); await pg.wait_for_timeout(600)
        assert 'Lô đã hủy' in await pg.inner_text('#drawer'), 'không hiện banner hủy'
        await pg.screenshot(path='shots/43_lo_huy.png')
        await pg.click('[data-act="khoi-phuc-lo"]'); await pg.wait_for_timeout(600)
        assert 'Lô đã hủy' not in await pg.inner_text('#drawer'), 'khôi phục lỗi'
        await pg.click('[data-act="nk-load"]'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='shots/44_lo_history.png')
        await pg.evaluate('closeDrawer()')
        # --- Yêu cầu đợt 3: tại kho, bãi, kiểm dịch, hạ cảng, ePort, danh mục, chi phí ---
        await pg.click('.side [data-tab="taikho"]'); await pg.wait_for_timeout(250)
        await pg.screenshot(path='shots/60_taikho_cls.png', full_page=True)
        await pg.click('.side [data-tab="bai"]'); await pg.wait_for_timeout(250)
        assert 'Tổng chi phí' in await pg.inner_text('#main'), 'bãi thiếu tổng chi phí'
        await pg.select_option('select[data-on="bai-sort"]', 'tien'); await pg.wait_for_timeout(200)
        await pg.screenshot(path='shots/61_bai.png', full_page=True)
        first = await pg.query_selector('#main .tr [data-act="open-cont"]')
        if first:
            await first.click(); await pg.wait_for_timeout(300)
            await pg.fill('#cp-tien', '350000'); await pg.fill('#cp-ghichu', 'PTI thử')
            await pg.click('[data-act="cp-add"]'); await pg.wait_for_timeout(500)
            ins = await pg.evaluate('window.__LOG.filter(x => x[0] === "chi_phi_cont" && x[1] === "insert").length')
            assert ins == 1, 'không thêm được phát sinh'
            await pg.screenshot(path='shots/62_cont_chiphi.png')
            await pg.evaluate('closeDrawer()')
        await pg.click('.side [data-tab="kd"]'); await pg.wait_for_timeout(250)
        await pg.screenshot(path='shots/63_kd.png', full_page=True)
        await pg.click('.side [data-tab="hacang"]'); await pg.wait_for_timeout(250)
        await pg.click('[data-on="hc-all"]'); await pg.wait_for_timeout(250)
        await pg.screenshot(path='shots/64_hacang.png', full_page=True)
        await pg.click('.side [data-tab="lo"]'); await pg.wait_for_timeout(250)
        await pg.click('[data-act="eport-run"]'); await pg.wait_for_timeout(8500)
        rpcs = await pg.evaluate('window.__LOG.filter(x => x[0] === "rpc").map(x => x[1])')
        assert 'eport_gui_yeu_cau' in rpcs and 'eport_xu_ly_ket_qua' in rpcs, 'ePort chưa gọi: ' + str(rpcs)
        await pg.screenshot(path='shots/65_lo_eport.png', full_page=True)
        await pg.click('[data-act="open-lo"][data-lo="604A"]'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='shots/66_lo_drawer_cls.png')
        dr = await pg.inner_text('.drawer')
        assert 'SPITC' in dr, 'form lô chưa hiện cảng ePort SPITC'
        cell = await pg.evaluate('clsDetail(S.lots["604A"])')
        assert 'ePort SPITC' in cell, 'bảng lô chưa ghi nguồn SPITC: ' + cell
        assert 'SPITC (theo ePort)' in await pg.evaluate('cangHa(S.lots["604A"])'), 'hạ cảng chưa lấy cảng theo ePort'
        await pg.evaluate('closeDrawer()')
        # ===== QUY TRÌNH KIỂM DỊCH → HẠ CẢNG (dựng tình huống lô 123 có 4 cont A-B-C-D, A là cont KD) =====
        kd = await pg.evaluate("""(() => {
          const now = Date.now(), iso = h => new Date(now + h * 36e5).toISOString();
          S.cauhinh['Giờ trước closing hạ thẳng cảng'] = '48';
          const l = { lo:'123T', booking:'BK123T', hang_tau:'CMA', ten_tau:'TAU THU 1N', closing:iso(100), cls:iso(100), da_kiem_dich:false, ma_don_kdtv:null, so_cont:4, so_cont_dang_chay:4, _n:true };
          S.lots['123T'] = l;
          const mk = (x, kdc) => ({ id:'TST' + x + '-123T', lo:'123T', so_cont:'TST' + x + '000000' + x.charCodeAt(0) % 10, kho:S.kho[0].ten, trang_thai:'3', nha_xe:'HLS', cont_kiem_dich:kdc });
          ['A', 'B', 'C', 'D'].forEach((x, i) => S.conts.push(mk(x, i === 0)));
          const A = S.conts.find(c => c.id === 'TSTA-123T'), B = S.conts.find(c => c.id === 'TSTB-123T');
          const o = {};
          o.why_kho = kdWhy(l);                          // A còn ở kho
          o.b_to5_chuaKD = stBlock(B, l, '5');           // B hạ cảng khi chưa KD
          A.trang_thai = '4'; A.bai_tam = 'DCL'; o.why_dcl = kdWhy(l);
          A.bai_tam = 'HLS'; o.why_kdtv = kdWhy(l);
          l.ma_don_kdtv = 'TV-THU'; o.why_ok = kdWhy(l);
          l.da_kiem_dich = true;
          o.b_to5_cls100 = stBlock(B, l, '5');           // lô KD nhưng CLS còn 100h → phải hạ bãi
          l.closing = iso(30); o.b_to5_cls30 = stBlock(B, l, '5');
          B.trang_thai = '4'; B.bai_tam = 'HLS'; l.closing = iso(100); o.b_bai_to5 = stBlock(B, l, '5');
          S.me.vai_tro = 'CSKH'; o.cskh_lui = stBlock(Object.assign({}, B, { trang_thai:'5' }), l, '4'); S.me.vai_tro = 'Quản lý';
          o.mucQua = mucPill('Quá CLS').length > 0;
          l.da_kiem_dich = false; B.trang_thai = '3'; B.bai_tam = null;
          return o; })()""")
        assert 'phải về bãi' in kd['why_kho'], kd
        assert 'lô chưa kiểm dịch' in kd['b_to5_chuaKD'], kd
        assert 'HLS / PD / HT' in kd['why_dcl'] and 'DCL' in kd['why_dcl'], kd
        assert 'mã KDTV' in kd['why_kdtv'], kd
        assert kd['why_ok'] == '', kd
        assert 'phải hạ bãi' in kd['b_to5_cls100'], kd
        assert kd['b_to5_cls30'] == '' and kd['b_bai_to5'] == '', kd
        assert 'lùi' in kd['cskh_lui'], kd
        assert kd['mucQua'], 'thiếu nhãn Quá CLS'
        # Form lô: ô KD / Được hạ cảng chỉ đọc, nút tích đúng điều kiện
        await pg.evaluate('openLo(S.lots["123T"])'); await pg.wait_for_timeout(250)
        assert not await pg.query_selector('.drawer input[name="da_kiem_dich"]') and not await pg.query_selector('.drawer input[name="cho_keo_ha_cang"]'), 'form lô còn ô tích KD / hạ cảng tay'
        assert await pg.is_enabled('.drawer [data-act="kd-done"]'), 'đủ điều kiện mà nút tích KD bị khoá'
        await pg.screenshot(path='shots/70_lo_kd_du_dk.png')
        await pg.evaluate('S.conts.find(c => c.id === "TSTA-123T").bai_tam = "DCL"; openLo(S.lots["123T"])'); await pg.wait_for_timeout(200)
        assert not await pg.is_enabled('.drawer [data-act="kd-done"]'), 'cont KD ở DCL mà vẫn tích được'
        assert 'HLS / PD / HT' in await pg.inner_text('.drawer [data-kd-why]')
        await pg.screenshot(path='shots/71_lo_kd_dcl.png')
        await pg.evaluate('closeDrawer()')
        # Form cont B: không có lựa chọn hạ cảng khi lô chưa KD; ô cont KD bị khoá vì lô đã có A
        await pg.evaluate('openCont(S.conts.find(c => c.id === "TSTB-123T"))'); await pg.wait_for_timeout(250)
        assert await pg.evaluate('document.querySelector(\'.drawer select[name="trang_thai"] option[value="5"]\').disabled'), 'lô chưa KD mà vẫn chọn được Đã hạ cảng'
        assert await pg.query_selector('.drawer [data-kd-lock]'), 'lô đã có cont KD mà vẫn đánh dấu được cont KD thứ 2'
        assert not await pg.query_selector('.drawer [data-ha-thang]'), 'hiện nút hạ thẳng cảng khi lô chưa KD'
        await pg.screenshot(path='shots/72_cont_khoa_ha_cang.png')
        await pg.evaluate('closeDrawer()')
        # Lô đã KD + CLS 30h: cont B đầy ở kho có nút Hạ thẳng cảng
        await pg.evaluate('S.conts.find(c => c.id === "TSTA-123T").bai_tam = "HLS"; S.lots["123T"].da_kiem_dich = true; S.lots["123T"].closing = new Date(Date.now() + 30 * 36e5).toISOString(); openCont(S.conts.find(c => c.id === "TSTB-123T"))'); await pg.wait_for_timeout(250)
        assert await pg.query_selector('.drawer [data-ha-thang]'), 'lô KD, CLS 30h mà không có nút hạ thẳng cảng'
        await pg.screenshot(path='shots/73_cont_ha_thang.png')
        await pg.evaluate('closeDrawer()')
        # Màn Kiểm dịch: nút chỉ ở nhóm Sẵn sàng kiểm, chỉ QL / ĐĐ; báo lô sai quy trình + lô chưa chọn cont KD
        await pg.evaluate("""(() => { const l = S.lots['123T']; l.da_kiem_dich = false; l.closing = new Date(Date.now() + 100 * 36e5).toISOString();
          S.conts.find(c => c.id === 'TSTC-123T').trang_thai = '5';                       // C đã ở cảng khi lô chưa KD → sai quy trình
          S.lots['124T'] = { lo:'124T', booking:'BK124T', closing:new Date(Date.now() - 51 * 36e5).toISOString(), da_kiem_dich:false, so_cont_dang_chay:1, _n:true };
          S.conts.push({ id:'TSTE-124T', lo:'124T', so_cont:'TSTE0000005', kho:S.kho[0].ten, trang_thai:'3', nha_xe:'VTL', cont_kiem_dich:false });
          S.tab = 'kd'; renderMain(); })()"""); await pg.wait_for_timeout(250)
        main = await pg.inner_text('#main')
        assert await pg.query_selector('#main [data-kd-sai]') and '123T' in await pg.inner_text('#main [data-kd-sai]'), 'không báo lô sai quy trình'
        assert '124T' in await pg.inner_text('#main [data-kd-chua-chon]'), 'không báo lô chưa chọn cont KD'
        n_btn = await pg.evaluate('document.querySelectorAll(\'#main [data-act="kd-done"]\').length')
        n_ready = await pg.evaluate('kdGroups().filter(x => x.nhom === 1 && x.k !== "—").length')
        assert n_btn == n_ready, f'nút tích KD xuất hiện ngoài nhóm Sẵn sàng kiểm: {n_btn} nút / {n_ready} lô'
        await pg.screenshot(path='shots/74_kd_man_hinh.png', full_page=True)
        await pg.evaluate("S.me.vai_tro = 'CSKH'; renderMain()"); await pg.wait_for_timeout(150)
        assert await pg.evaluate('document.querySelectorAll(\'#main [data-act="kd-done"]\').length') == 0, 'CSKH vẫn thấy nút tích KD'
        await pg.evaluate("S.me.vai_tro = 'Quản lý'; S.tab = 'lo'; renderMain()"); await pg.wait_for_timeout(200)
        assert 'cont ở cảng khi chưa KD' in await pg.inner_text('#main'), 'danh sách lô không báo sai quy trình'
        await pg.screenshot(path='shots/75_lo_bao_sai.png', full_page=True)
        # Màn Hạ cảng: lô đã KD có cont ở bãi, CLS ≤ 72h mới hiện (60h có, 80h không, lô chưa KD không)
        hc = await pg.evaluate("""(() => { const iso = h => new Date(Date.now() + h * 36e5).toISOString();
          [['125T', 60, true], ['126T', 80, true], ['127T', 30, false]].forEach(([lo, h, kd]) => {
            S.lots[lo] = { lo, booking:'BK' + lo, closing:iso(h), da_kiem_dich:kd, so_cont_dang_chay:1, _n:true };
            S.conts.push({ id:'TSTH-' + lo, lo, so_cont:'TSTH' + lo, kho:S.kho[0].ten, trang_thai:'4', bai_tam:'HLS', nha_xe:'HLS', cont_kiem_dich:false }); });
          const ks = haCangLots(false).map(x => x.l.lo), all = haCangLots(true).map(x => x.l.lo);
          S.conts = S.conts.filter(c => !/^TSTH-/.test(c.id)); ['125T', '126T', '127T'].forEach(k => delete S.lots[k]);
          return { ks, all, gio:HC_GIO }; })()""")
        assert hc['gio'] == 72 and '125T' in hc['ks'] and '126T' not in hc['ks'] and '127T' not in hc['ks'], hc
        assert '126T' in hc['all'] and '127T' not in hc['all'], hc
        await pg.evaluate("""(() => { S.conts = S.conts.filter(c => !/-12[34]T$/.test(c.id)); delete S.lots['123T']; delete S.lots['124T']; S.tab = 'lo'; renderMain(); })()""")
        await pg.click('.side [data-tab="danhmuc"]'); await pg.wait_for_timeout(200)
        for tab in ['bai', 'gia']:
            await pg.click(f'[data-act="dm-tab"][data-v="{tab}"]'); await pg.wait_for_timeout(250)
            await pg.screenshot(path=f'shots/67_dm_{tab}.png', full_page=True)
        await pg.fill('form[data-form="gia"][data-key=""] input[name="g_rut_mooc"]', '1200000')
        await pg.click('form[data-form="gia"][data-key=""] button[type="submit"]'); await pg.wait_for_timeout(400)
        up = await pg.evaluate('window.__LOG.filter(x => x[0] === "bang_gia_xe" && x[1] === "upsert").length')
        assert up == 1, 'không lưu được giá cước'
        await pg.click('[data-act="dm-tab"][data-v="don"]'); await pg.wait_for_timeout(500)
        await pg.screenshot(path='shots/68_dm_don.png', full_page=True)
        await pg.click('[data-act="don-run"]'); await pg.wait_for_timeout(150); await pg.click('[data-act="don-run"]'); await pg.wait_for_timeout(400)
        assert 'don_du_lieu' in await pg.evaluate('window.__LOG.filter(x => x[0] === "rpc").map(x => x[1])'), 'không gọi dọn dữ liệu'
        await pg.click('[data-act="dm-tab"][data-v="nhaxe"]'); await pg.wait_for_timeout(200)
        await pg.click('form[data-key="HLS"] [data-act="dm-del"]'); await pg.wait_for_timeout(100); await pg.click('form[data-key="HLS"] [data-act="dm-del"]'); await pg.wait_for_timeout(400)
        assert 'xoa_nha_xe' in await pg.evaluate('window.__LOG.filter(x => x[0] === "rpc").map(x => x[1])'), 'không gọi xoá nhà xe'
        # search
        await pg.fill('#topq', 'FBIU58'); await pg.wait_for_timeout(700)
        await pg.screenshot(path='shots/14_tim.png', full_page=True)
        # danh muc save
        await pg.click('.side [data-tab="danhmuc"]'); await pg.wait_for_timeout(200)
        await pg.fill('form[data-key="HLS"] input[name="sdt_zalo"]', '0912 345 678')
        await pg.click('form[data-key="HLS"] button[type="submit"]'); await pg.wait_for_timeout(400)
        await pg.click('[data-act="dm-tab"][data-v="nv"]'); await pg.wait_for_timeout(200)
        await pg.click('[data-act="dm-tab"][data-v="nk"]'); await pg.wait_for_timeout(300)
        assert 'ABCU1234567' in await pg.inner_text('#main'), 'tab nhật ký trống'
        await pg.screenshot(path='shots/45_nhatky.png', full_page=True)
        await pg.click('[data-act="dm-tab"][data-v="nv"]'); await pg.wait_for_timeout(200)
        await pg.screenshot(path='shots/15_nv.png', full_page=True)
        # zh
        await pg.click('[data-act="lang"][data-lang="zh"]'); await pg.click('.side [data-tab="goiy"]'); await pg.wait_for_timeout(300)
        await pg.screenshot(path='shots/16_goiy_zh.png')
        await pg.click('[data-act="lang"][data-lang="vi"]')
        log = await pg.evaluate('window.__LOG.filter(x => x[1] !== "select")')
        # mobile
        m = await b.new_context(viewport={'width':390,'height':844}, timezone_id='Asia/Ho_Chi_Minh', device_scale_factor=2, is_mobile=True, has_touch=True)
        mp = await m.new_page()
        mp.on('pageerror', lambda e: errs.append('m pageerror: ' + str(e)))
        await mp.route('**/fonts.g*/**', lambda r: r.abort())
        await mp.goto(URL); await mp.wait_for_selector('.tile', timeout=8000)
        await mp.screenshot(path='shots/20_m_tong.png')
        await mp.click('.bottom-nav [data-tab="goiy"]'); await mp.wait_for_timeout(250); await mp.screenshot(path='shots/21_m_goiy.png')
        await mp.click('.bottom-nav [data-tab="taikho"]'); await mp.wait_for_timeout(250); await mp.screenshot(path='shots/22_m_taikho.png')
        await mp.click('.bottom-nav [data-act="nav-open"]'); await mp.wait_for_timeout(300); await mp.screenshot(path='shots/23_m_menu.png')
        await mp.mouse.click(375, 420); await mp.wait_for_timeout(250)
        await mp.click('.tr [data-act="open-cont"]'); await mp.wait_for_timeout(300); await mp.screenshot(path='shots/24_m_drawer.png')
        # login screen
        lp = await b.new_page(viewport={'width':1100,'height':800})
        await lp.route('**/fonts.g*/**', lambda r: r.abort())
        await lp.goto(URL)
        await lp.wait_for_selector('.tile', timeout=8000)
        await lp.evaluate('renderLogin()'); await lp.screenshot(path='shots/30_login.png')
        await lp.fill('#login-form [name=email]', 'tinbui403@gmail.com'); await lp.fill('#login-form [name=password]', 'sai123')
        await lp.click('[data-act="pw-eye"]'); await lp.wait_for_timeout(100)
        await lp.click('#login-btn'); await lp.wait_for_timeout(300)
        kept = await lp.input_value('#login-form [name=email]')
        assert kept == 'tinbui403@gmail.com', 'email bị xoá sau khi đăng nhập sai: ' + repr(kept)
        await lp.screenshot(path='shots/31_login_err.png')
        # đổi mật khẩu
        await pg.evaluate('closeDrawer()')
        await pg.click('.side [data-act="pw-open"]'); await pg.wait_for_timeout(250)
        await pg.fill('#f-pw [name=p1]', 'abc123'); await pg.fill('#f-pw [name=p2]', 'abc124')
        await pg.click('#save-btn'); await pg.wait_for_timeout(200)
        still = await pg.query_selector('#f-pw'); assert still, 'form đóng dù 2 mật khẩu khác nhau'
        await pg.fill('#f-pw [name=p2]', 'abc123'); await pg.screenshot(path='shots/32_pw.png')
        await pg.click('#save-btn'); await pg.wait_for_timeout(300)
        gone = await pg.query_selector('#f-pw'); assert not gone, 'form đổi mật khẩu không đóng'
        auth = await pg.evaluate('window.__LOG.filter(x => x[0] === "auth")'); print('AUTH', auth)
        await mp.evaluate('closeDrawer()'); await mp.click('.bottom-nav [data-act="nav-open"]'); await mp.wait_for_timeout(300); await mp.screenshot(path='shots/33_m_menu_pw.png')
        print(json.dumps(log, ensure_ascii=False, indent=0)[:3000])
        print('ERRORS:', errs)
        await b.close()
asyncio.run(main())
