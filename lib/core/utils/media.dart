import '../config/app_config.dart';

/// Ảnh upload được backend trả dạng '/uploads/...', phục vụ ở gốc server (không có '/api').
/// Ví dụ apiBaseUrl 'http://10.0.2.2:3000/api' -> 'http://10.0.2.2:3000/uploads/...'.
String mediaUrl(String path) {
  if (path.startsWith('http')) return path;
  final base = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/api/?$'), '');
  return '$base$path';
}
