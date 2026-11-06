import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../application/auth_controller.dart';

/// Đổi mật khẩu. Nếu tài khoản mới được cấp (mustChangePassword) thì
/// đây là màn hình bắt buộc, không thể vào app khi chưa đổi.
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(bool forced) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).changePassword(_current.text, _new.text);
      if (!mounted) return;
      showSnack(context, 'Đổi mật khẩu thành công');
      // Bắt buộc: router tự chuyển về trang chủ. Tự nguyện: quay lại.
      if (!forced && context.canPop()) context.pop();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forced = ref.watch(currentUserProvider)?.mustChangePassword ?? false;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đổi mật khẩu'),
        automaticallyImplyLeading: !forced,
        actions: [
          if (forced)
            TextButton(
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              child: const Text('Đăng xuất'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (forced) ...[
                      Card(
                        color: theme.colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Đây là lần đăng nhập đầu tiên hoặc mật khẩu vừa được đặt lại. '
                            'Vui lòng đổi mật khẩu để tiếp tục.',
                            style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    PasswordField(
                      controller: _current,
                      label: forced ? 'Mật khẩu được cấp' : 'Mật khẩu hiện tại',
                      validator: (v) => Validators.required(v, 'Mật khẩu hiện tại'),
                    ),
                    const SizedBox(height: 16),
                    PasswordField(
                      controller: _new,
                      label: 'Mật khẩu mới',
                      validator: (v) {
                        final err = Validators.password(v);
                        if (err != null) return err;
                        return v == _current.text ? 'Mật khẩu mới phải khác mật khẩu cũ' : null;
                      },
                    ),
                    const SizedBox(height: 4),
                    Text('Tối thiểu 8 ký tự, gồm cả chữ và số', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 16),
                    PasswordField(
                      controller: _confirm,
                      label: 'Nhập lại mật khẩu mới',
                      validator: (v) => v == _new.text ? null : 'Mật khẩu nhập lại không khớp',
                      onSubmitted: (_) => _submit(forced),
                    ),
                    const SizedBox(height: 24),
                    LoadingButton(
                      loading: _loading,
                      onPressed: () => _submit(forced),
                      label: 'Đổi mật khẩu',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
