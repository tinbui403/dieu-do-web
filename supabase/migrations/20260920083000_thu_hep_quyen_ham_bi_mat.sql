-- Các hàm dùng mã bí mật chỉ dành cho Apps Script (gọi bằng khoá công khai = vai trò anon); người dùng web không cần
revoke execute on function public.sao_luu_du_lieu(text) from authenticated;
revoke execute on function public.ghi_nhan_sao_luu(text, text, text, jsonb) from authenticated;
revoke execute on function public.cap_nhat_ma_kdtv(text, jsonb) from authenticated;
