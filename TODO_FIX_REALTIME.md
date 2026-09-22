// Cần sửa: startRealtime trong src/app.src.html
// Lỗi: "cannot add `postgres_changes` callbacks for realtime:dieu-do after `subscribe()`."
// Nguyên nhân: startRealtime được gọi trong afterLogin, mà afterLogin có thể được gọi nhiều lần.
// Mỗi lần gọi startRealtime sẽ tạo channel mới và đăng ký thêm callback.

// Giải pháp:
// 1. Lưu channel vào biến toàn cục.
// 2. Trước khi subscribe, nếu channel đã tồn tại, unsub và xóa nó đi.

// Sửa lại hàm startRealtime trong src/app.src.html:

let activeChannel = null;

function startRealtime() {
  if (activeChannel) {
    activeChannel.unsubscribe();
    sb.removeChannel(activeChannel);
    activeChannel = null;
  }
  
  activeChannel = sb.channel('dieu-do')
    .on('postgres_changes', { event:'*', schema:'public', table:'cont' }, scheduleReload)
    .on('postgres_changes', { event:'*', schema:'public', table:'lo' }, scheduleReload)
    .on('postgres_changes', { event:'*', schema:'public', table:'goi_y' }, scheduleReload)
    .subscribe(st => { S.live = st === 'SUBSCRIBED'; const el = document.getElementById('live'); if (el) el.className = 'live' + (S.live ? ' on' : ''); });
}

// Kiểm tra lại nơi gọi startRealtime:
// Dòng 1421: afterLogin (lines 1421-1431) -> OK
