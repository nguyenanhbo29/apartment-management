import 'package:dio/dio.dart';

import 'api_client.dart';

/// Một file gửi kèm request multipart (ảnh phiếu, ảnh xe...).
class UploadFile {
  const UploadFile({
    required this.field,
    required this.filename,
    required this.bytes,
  });

  final String field;
  final String filename;
  final List<int> bytes;

  /// Backend chỉ nhận JPEG/PNG; đoán theo đuôi file.
  DioMediaType get mediaType => filename.toLowerCase().endsWith('.png')
      ? DioMediaType('image', 'png')
      : DioMediaType('image', 'jpeg');
}

/// Gửi multipart/form-data qua [ApiClient] (tách file riêng để không sửa api_client.dart).
extension MultipartApi on ApiClient {
  /// Trả về phần `data`. Dio tự đặt `Content-Type: multipart/form-data; boundary=...`
  /// khi body là FormData. Dùng bytes để chạy được cả trên web.
  Future<T> multipart<T>(
    String method,
    String path, {
    Map<String, Object?> fields = const {},
    List<UploadFile> files = const [],
  }) {
    final form = FormData();
    fields.forEach((key, value) {
      if (value != null) form.fields.add(MapEntry(key, value.toString()));
    });
    for (final f in files) {
      form.files.add(
        MapEntry(
          f.field,
          MultipartFile.fromBytes(
            f.bytes,
            filename: f.filename,
            contentType: f.mediaType,
          ),
        ),
      );
    }
    return request<T>(method, path, body: form);
  }
}
