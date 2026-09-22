// Kiem Dich Wizard Logic
// Xu ly quy trinh: Chon cont -> Nhap ma KDTV -> Xac nhan

const KD_WIZARD = {
  step: 1, // 1: chon, 2: nhap, 3: xac nhan
  data: {
    cont_id: null,
    ma_kdtv: '',
    lo: null
  },

  reset: function() {
    this.step = 1;
    this.data = { cont_id: null, ma_kdtv: '', lo: null };
  },

  nextStep: function() {
    if (this.step < 3) this.step++;
    this.render();
  },

  prevStep: function() {
    if (this.step > 1) this.step--;
    this.render();
  },

  close: function() {
    document.getElementById('drawer').innerHTML = '';
  },

  render: function() {
    const drawer = document.getElementById('drawer');
    if (!drawer) return;

    drawer.innerHTML = `
      <div class="drawer-wrap">
        <button class="close-area" data-act="close-wizard"></button>
        <div class="drawer">
          <div class="drawer-h">
            <h2>Kiểm dịch Wizard</h2>
            <button class="x-btn" data-act="close-wizard">X</button>
          </div>
          <div class="drawer-b">
            <div>Step: ${this.step}</div>
            <div class="sec">
                ${this.step === 1 ? '<p>Chọn cont cần kiểm dịch</p>' : ''}
                ${this.step === 2 ? '<p>Nhập mã KDTV</p>' : ''}
                ${this.step === 3 ? '<p>Xác nhận thông tin</p>' : ''}
            </div>
          </div>
          <div class="drawer-f">
            <button class="btn" data-act="prev-step" ${this.step === 1 ? 'disabled' : ''}>Quay lại</button>
            <button class="btn btn-pri" data-act="next-step">${this.step === 3 ? 'Hoàn tất' : 'Tiếp theo'}</button>
          </div>
        </div>
      </div>
    `;
  }
};
