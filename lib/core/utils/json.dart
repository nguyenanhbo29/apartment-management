// Đọc JSON từ backend (Mongoose) cho các model.

/// Trường populate có thể là object `{_id, ...}` hoặc chỉ id: trả về (id, object?).
(String?, Map<String, dynamic>?) refOf(Object? v) => switch (v) {
  final Map<String, dynamic> m => (m['_id'] as String?, m),
  final String s => (s, null),
  _ => (null, null),
};

/// Chuỗi ISO (UTC) -> giờ máy.
DateTime? dateOf(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

List<String> stringsOf(Object? v) =>
    (v as List?)?.map((e) => e.toString()).toList() ?? const [];

int? intOf(Object? v) => (v as num?)?.toInt();
