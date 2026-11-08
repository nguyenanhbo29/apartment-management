import 'package:flutter/material.dart';

import 'common.dart';

/// Hỏi lại trước khi rời form còn dữ liệu chưa lưu (nút Back hệ thống, nút quay lại trên AppBar).
///
///   UnsavedChangesGuard(isDirty: () => _dirty, child: Scaffold(...))
///
/// Form trống thì thoát luôn, không làm phiền. Lưu xong gọi `context.pop()` như bình thường:
/// `Navigator.pop` không bị chặn, chỉ thao tác "quay lại" (maybePop) mới đi qua đây.
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.isDirty,
    required this.child,
  });

  /// Gọi lúc người dùng bấm quay lại, nên không cần setState mỗi lần gõ phím.
  final bool Function() isDirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave =
            !isDirty() ||
            await confirmDialog(
              context,
              title: 'Bỏ nội dung đang nhập?',
              message: 'Thông tin bạn vừa nhập sẽ không được lưu.',
              confirmText: 'Bỏ',
              destructive: true,
            );
        if (leave && context.mounted) Navigator.of(context).pop(result);
      },
      child: child,
    );
  }
}
