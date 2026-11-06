import 'package:intl/intl.dart';

final _date = DateFormat('dd/MM/yyyy');
final _dateTime = DateFormat('HH:mm dd/MM/yyyy');

String formatDate(DateTime? d, [String empty = '—']) => d == null ? empty : _date.format(d);

String formatDateTime(DateTime? d, [String empty = '—']) => d == null ? empty : _dateTime.format(d);

/// Ngày gửi lên API (yyyy-MM-dd), không lệch múi giờ.
String apiDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime? parseDate(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

String formatArea(num v) => '${NumberFormat('#,##0.##', 'vi').format(v)} m²';
