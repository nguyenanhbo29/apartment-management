import 'dart:math';

/// Sinh mật khẩu tạm 10 ký tự, luôn có chữ và số (thỏa quy tắc backend).
String generateTempPassword() {
  const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
  const digits = '23456789';
  final rnd = Random.secure();
  final chars = <String>[
    letters[rnd.nextInt(letters.length)],
    digits[rnd.nextInt(digits.length)],
    for (var i = 0; i < 8; i++) (letters + digits)[rnd.nextInt(letters.length + digits.length)],
  ]..shuffle(rnd);
  return chars.join();
}
