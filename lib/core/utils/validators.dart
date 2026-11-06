/// Validator phía client, khớp với quy tắc backend (backend/src/validators).
class Validators {
  Validators._();

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _phone = RegExp(r'^\+?\d{9,15}$');

  static String? required(String? v, [String field = 'Trường này']) =>
      (v == null || v.trim().isEmpty) ? '$field không được để trống' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Vui lòng nhập email';
    return _email.hasMatch(v.trim()) ? null : 'Email không hợp lệ';
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu';
    if (v.length < 8) return 'Mật khẩu tối thiểu 8 ký tự';
    if (!RegExp('[A-Za-z]').hasMatch(v)) return 'Mật khẩu phải có chữ cái';
    if (!RegExp(r'\d').hasMatch(v)) return 'Mật khẩu phải có chữ số';
    return null;
  }

  /// Số điện thoại không bắt buộc
  static String? optionalPhone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return _phone.hasMatch(v.trim()) ? null : 'Số điện thoại không hợp lệ';
  }
}
