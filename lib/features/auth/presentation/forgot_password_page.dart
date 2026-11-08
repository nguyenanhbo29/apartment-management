import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../data/auth_repository.dart';

/// UC-02: Quên mật khẩu. Bước 1 nhập email nhận OTP, bước 2 nhập OTP + mật khẩu mới.
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _emailForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _otpSent = false;
  bool _loading = false;
  String? _devOtp;

  @override
  void dispose() {
    for (final c in [_email, _otp, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_emailForm.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final devOtp = await ref.read(authRepositoryProvider).forgotPassword(_email.text);
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _devOtp = devOtp;
      });
      showSnack(context, 'Nếu email tồn tại, mã OTP đã được gửi tới hộp thư.');
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (!_resetForm.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(email: _email.text, otp: _otp.text, newPassword: _password.text);
      if (!mounted) return;
      showSnack(context, 'Đặt lại mật khẩu thành công, vui lòng đăng nhập.');
      context.go('/login');
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Quên mật khẩu')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Form(
                    key: _emailForm,
                    child: TextFormField(
                      controller: _email,
                      enabled: !_otpSent,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: Validators.email,
                      decoration: const InputDecoration(
                        labelText: 'Email tài khoản',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_otpSent)
                    LoadingButton(loading: _loading, onPressed: _sendOtp, label: 'Gửi mã OTP')
                  else
                    Form(
                      key: _resetForm,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_devOtp != null)
                            Card(
                              color: theme.colorScheme.tertiaryContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'Chế độ demo: mã OTP là $_devOtp',
                                  style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _otp,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            validator: (v) => RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '')
                                ? null
                                : 'Mã OTP gồm 6 chữ số',
                            decoration: const InputDecoration(
                              labelText: 'Mã OTP (hiệu lực 10 phút)',
                              prefixIcon: Icon(Icons.pin_outlined),
                            ),
                          ),
                          const SizedBox(height: 8),
                          PasswordField(
                            controller: _password,
                            label: 'Mật khẩu mới',
                            validator: Validators.password,
                          ),
                          const SizedBox(height: 16),
                          PasswordField(
                            controller: _confirm,
                            label: 'Nhập lại mật khẩu mới',
                            validator: (v) =>
                                v == _password.text ? null : 'Mật khẩu nhập lại không khớp',
                          ),
                          const SizedBox(height: 24),
                          LoadingButton(
                            loading: _loading,
                            onPressed: _reset,
                            label: 'Đặt lại mật khẩu',
                          ),
                          TextButton(
                            onPressed: _loading ? null : _sendOtp,
                            child: const Text('Gửi lại mã'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
