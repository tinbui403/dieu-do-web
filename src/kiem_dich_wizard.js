// Kiem Dich Wizard — quy trình 3 bước: chọn cont KD, nhập mã KDTV, xác nhận & lưu
const KD_WIZARD = {
  step: 1,
  lo: null,
  contId: null,
  maKdtv: '',

  open: function(loId) {
    const l = S.lots[loId];
    if (!l) { toast(T1('Không tìm thấy lô ' + loId, '找不到批次 ' + loId), true); return; }
    this.step = 1;
    this.lo = loId;
    const existing = S.conts.find(c => c.lo === loId && c.cont_kiem_dich && c.trang_thai !== '9');
    this.contId = existing ? existing.id : null;
    this.maKdtv = l.ma_don_kdtv || '';
    S.drawer = { kind: 'kd-wizard', id: loId };
    this.render();
  },

  close: function() {
    S.drawer = null;
    document.getElementById('drawer').innerHTML = '';
  },

  selectCont: function(id) {
    this.contId = id;
    this.render();
  },

  _readMa: function() {
    const el = document.getElementById('kd-wizard-ma');
    if (el) this.maKdtv = el.value.trim();
  },

  nextStep: function() {
    if (this.step === 1) {
      if (!this.contId) { toast(T1('Vui lòng chọn cont kiểm dịch.', '请先选择检疫柜。'), true); return; }
      this.step = 2;
    } else if (this.step === 2) {
      this._readMa();
      if (!this.maKdtv) { toast(T1('Vui lòng nhập mã KDTV.', '请输入检疫单号。'), true); return; }
      this.step = 3;
    }
    this.render();
  },

  prevStep: function() {
    if (this.step === 2) { this.step = 1; this.render(); }
    else if (this.step === 3) { this.step = 2; this.render(); }
  },

  save: async function() {
    this._readMa();
    const l = S.lots[this.lo];
    const cont = S.conts.find(c => c.id === this.contId);
    if (!l || !cont || !this.maKdtv) return;
    const tickEl = document.getElementById('kd-wizard-tick');
    const tickKd = tickEl && tickEl.checked;
    const btn = document.getElementById('kd-wizard-save-btn');
    if (btn) btn.disabled = true;
    try {
      // Bỏ đánh dấu KD các cont cũ trong lô (nếu khác cont đang chọn)
      const oldKd = S.conts.filter(c => c.lo === this.lo && c.cont_kiem_dich && c.id !== this.contId && c.trang_thai !== '9');
      for (const c of oldKd) {
        await q(sb.from('cont').update({ cont_kiem_dich: false }).eq('id', c.id));
      }
      // Đánh dấu cont được chọn là cont KD
      await q(sb.from('cont').update({ cont_kiem_dich: true }).eq('id', this.contId));
      // Cập nhật mã KDTV (và tích KD nếu đủ điều kiện)
      const loPatch = { ma_don_kdtv: this.maKdtv };
      if (tickKd) loPatch.da_kiem_dich = true;
      await q(sb.from('lo').update(loPatch).eq('lo', this.lo));

      toast(T1('Đã lưu kiểm dịch lô ' + this.lo, '已保存检疫信息 ' + this.lo));
      this.close();
      await loadData();
      renderMain();
      renderNavCounts();
      if (S.lots[this.lo]) openLo(S.lots[this.lo]);
    } catch (e) {
      if (btn) btn.disabled = false;
      toast(errMsg(e), true);
    }
  },

  render: function() {
    const l = S.lots[this.lo];
    if (!l) return;
    const conts = S.conts.filter(c => c.lo === this.lo && c.trang_thai !== '9')
      .sort((a, b) => +a.trang_thai - +b.trang_thai);
    const selCont = conts.find(c => c.id === this.contId);
    const readyKd = selCont && selCont.trang_thai === '4' && BAI_KD.indexOf(selCont.bai_tam) > -1;
    const canTickNow = readyKd && this.maKdtv;

    // --- Step bar ---
    const stepLabels = [T1('Chọn cont', '选柜'), T1('Mã KDTV', '检疫单号'), T1('Xác nhận', '确认')];
    const stepBar = '<div style="display:flex;gap:6px;margin-bottom:18px">' +
      stepLabels.map((s, i) => '<div style="flex:1;text-align:center;padding:7px 4px;border-radius:8px;font-size:12px;font-weight:600;' +
        (i + 1 === this.step ? 'background:var(--pri);color:#fff' :
         i + 1 < this.step ? 'background:var(--teal-bg);color:var(--teal-ink)' :
         'background:var(--soft);color:var(--faint)') + '">' +
        (i + 1 < this.step ? '✓ ' : (i + 1 === this.step ? '' : (i + 1) + '. ')) + esc(s) + '</div>').join('') + '</div>';

    // --- Body theo step ---
    let body = '';
    if (this.step === 1) {
      body = '<p style="margin:0 0 12px;font-size:13px;color:var(--muted)">' +
        esc(T1('Chọn cont sẽ đi kiểm dịch. Ưu tiên cont đang ở bãi HLS / PD / HT (đã sẵn sàng).', '请选择检疫柜，优先选已在HLS/PD/HT堆场的柜子。')) + '</p>' +
        (conts.length ? conts.map(c => {
          const isSel = c.id === this.contId;
          const atKdBai = c.trang_thai === '4' && BAI_KD.indexOf(c.bai_tam) > -1;
          const atOtherBai = c.trang_thai === '4' && !atKdBai;
          const bg = isSel ? 'var(--pri)' : atKdBai ? 'var(--teal-bg)' : 'var(--soft)';
          const fg = isSel ? '#fff' : 'var(--ink)';
          const border = isSel ? '2px solid var(--pri)' : atKdBai ? '2px solid #A9D6CF' : '1px solid var(--line)';
          const badge = atKdBai ? pill(T1('Sẵn sàng KD', '可检疫'), 'var(--teal-bg)', 'var(--teal-ink)') :
                        atOtherBai ? pill('Bãi ' + (c.bai_tam || '?'), 'var(--amb-bg)', 'var(--amb-ink)') :
                        stPill(c.trang_thai);
          return '<button type="button" data-act="kd-wizard-sel" data-id="' + esc(c.id) + '" ' +
            'style="display:flex;align-items:center;gap:12px;width:100%;text-align:left;border:' + border + ';background:' + bg + ';color:' + fg + ';border-radius:10px;padding:11px 14px;margin-bottom:8px;cursor:pointer">' +
            '<div style="flex:1;min-width:0">' +
              '<div class="mono" style="font-size:15px;font-weight:700">' + esc(c.so_cont || c.ma_don || T1('Chưa có số', '未填柜号')) + '</div>' +
              '<div style="font-size:12px;margin-top:2px;opacity:' + (isSel ? '.85' : '1') + '">' +
                esc(c.kho ? c.kho : '') + (c.bai_tam ? (c.kho ? ' → ' : '') + 'Bãi ' + c.bai_tam : '') +
                (c.nha_xe ? ' · ' + c.nha_xe : '') +
              '</div>' +
            '</div>' +
            '<div>' + badge + '</div>' +
            (isSel ? '<div style="font-size:18px">✓</div>' : '') +
            '</button>';
        }).join('') : '<p class="muted">' + esc(T1('Lô chưa có cont.', '此批次暂无柜子。')) + '</p>');

    } else if (this.step === 2) {
      body =
        '<div style="background:var(--soft);border-radius:10px;padding:10px 14px;margin-bottom:16px">' +
          '<div class="muted" style="font-size:11px;margin-bottom:3px">' + esc(T1('Cont kiểm dịch', '检疫柜')) + '</div>' +
          '<div class="mono" style="font-size:17px;font-weight:700">' + esc(selCont ? (selCont.so_cont || selCont.ma_don || '—') : '—') + '</div>' +
          '<div class="muted" style="font-size:12px">' + esc(selCont ? stLabel(selCont.trang_thai) + (selCont.bai_tam ? ' · Bãi ' + selCont.bai_tam : '') : '') + '</div>' +
        '</div>' +
        '<label class="field" style="display:block">' +
          '<span style="font-weight:600">' + esc(T('kdtv')) + '</span> <span style="color:var(--red-ink)">*</span><br>' +
          '<input id="kd-wizard-ma" type="text" value="' + esc(this.maKdtv) + '" ' +
            'placeholder="VD: 11300/HAN-KD/24/05..." ' +
            'autocapitalize="characters" ' +
            'style="font-family:var(--mono);font-size:15px;letter-spacing:.03em;margin-top:6px" required>' +
        '</label>' +
        '<p class="muted" style="font-size:12px;margin-top:8px">' +
          esc(T1('Mã trên tờ kiểm dịch tiêu vật của lô. Sẽ được lưu vào lô.', '检疫单号，来自检疫证书。')) +
        '</p>';

    } else {
      const whyNoTick = !readyKd ?
        (selCont && selCont.trang_thai !== '4' ? T1('cont chưa về bãi', '柜未到堆场') :
         selCont && BAI_KD.indexOf(selCont.bai_tam) < 0 ? T1('bãi ' + (selCont.bai_tam || '?') + ' không được kiểm dịch (chỉ HLS / PD / HT)', '堆场不符') : '') : '';
      body =
        '<div class="kv" style="background:var(--soft);border-radius:10px;padding:12px 16px;margin-bottom:16px">' +
          '<span>' + esc(T('loCol')) + '</span><span style="font-weight:700">' + esc(this.lo) + (l.booking ? ' · ' + l.booking : '') + '</span>' +
          '<span>' + esc(T('kdCont')) + '</span><span class="mono" style="font-weight:700">' + esc(selCont ? (selCont.so_cont || selCont.ma_don || '—') : '—') + '</span>' +
          '<span>' + esc(T('kdtv')) + '</span><span class="mono">' + esc(this.maKdtv) + '</span>' +
          '<span>' + esc(T1('Trạng thái cont', '柜状态')) + '</span><span>' + (selCont ? esc(stLabel(selCont.trang_thai) + (selCont.bai_tam ? ' · Bãi ' + selCont.bai_tam : '')) : '—') + '</span>' +
        '</div>' +
        (canTickNow ?
          '<label class="chk" style="margin-bottom:14px;padding:10px 12px;background:var(--teal-bg);border-radius:10px">' +
            '<input id="kd-wizard-tick" type="checkbox" checked>' +
            '<span>' + esc(T1('Tích "Lô đã kiểm dịch" ngay — cont đang ở bãi ' + (selCont.bai_tam || '') + ', đủ điều kiện.', '立即勾选已检疫—柜已在合规堆场。')) + '</span>' +
          '</label>' :
          (whyNoTick ? '<div style="font-size:12px;color:var(--muted);padding:8px 12px;background:var(--amb-bg);border-radius:8px;margin-bottom:14px">ℹ ' +
            esc(T1('Chưa thể tích KD ngay vì ' + whyNoTick + '. Bấm Lưu rồi tích thủ công sau khi cont về đúng bãi.', '暂不能勾选KD：' + whyNoTick + '。保存后待柜到位再手动勾选。')) +
            '</div>' : '')) +
        '<button id="kd-wizard-save-btn" type="button" class="btn btn-pri" data-act="kd-wizard-save" style="width:100%;min-height:44px;font-size:15px">' +
          esc(T1('💾 Lưu kiểm dịch', '保存检疫信息')) +
        '</button>';
    }

    // --- Footer nav ---
    const footer = '<div style="display:flex;gap:8px;margin-top:18px;padding-top:14px;border-top:1px solid var(--line)">' +
      (this.step > 1 ?
        '<button type="button" class="btn" data-act="kd-prev-step" style="flex:1">← ' + esc(T1('Quay lại', '返回')) + '</button>' :
        '<button type="button" class="btn" data-act="close-wizard" style="flex:1">' + esc(T1('Đóng', '关闭')) + '</button>') +
      (this.step < 3 ?
        '<button type="button" class="btn btn-pri" data-act="kd-next-step" style="flex:2">' + esc(T1('Tiếp theo', '下一步')) + ' →</button>' : '') +
      '</div>';

    document.getElementById('drawer').innerHTML =
      '<div class="drawer-wrap">' +
        '<button class="close-area" data-act="close-wizard" aria-label="' + esc(T('close')) + '"></button>' +
        '<aside class="drawer" role="dialog" aria-labelledby="kd-wiz-title">' +
          '<div class="drawer-h">' +
            '<div style="flex:1;min-width:0">' +
              '<b id="kd-wiz-title" style="font-size:18px;color:var(--pri-ink)">' + esc(T1('Kiểm dịch Wizard', '检疫向导')) + '</b>' +
              '<span class="muted" style="font-size:13px;display:block;margin-top:2px">' +
                esc(T('loCol') + ' ' + this.lo + (l.booking ? ' · ' + l.booking : '') + (l.closing ? ' · CLS ' + fTs(l.closing) : '')) +
              '</span>' +
            '</div>' +
            '<button class="x-btn" data-act="close-wizard" aria-label="' + esc(T('close')) + '">' + ico('x', 16) + '</button>' +
          '</div>' +
          '<div class="drawer-b">' + stepBar + body + footer + '</div>' +
        '</aside>' +
      '</div>';

    // Focus vào input mã KDTV ở step 2
    if (this.step === 2) {
      const ma = document.getElementById('kd-wizard-ma');
      if (ma) { ma.focus(); ma.select(); }
    }
  }
};
