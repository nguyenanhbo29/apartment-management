import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/app_user.dart';
import '../data/users_repository.dart';
import 'password_generator.dart';
import 'role_fields.dart';

/// UC-04: Manager tạo tài khoản. Người dùng phải đổi mật khẩu tạm ở lần đăng nhập đầu.
class UserFormPage extends ConsumerStatefulWidget {
  const UserFormPage({super.key});

  @override
  ConsumerState<UserFormPage> createState() => _UserFormPageState();
}

class _UserFormPageState extends ConsumerState<UserFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.resident;
  Department? _department;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_email, _name, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final user = await ref
          .read(usersRepositoryProvider)
          .create(
            email: _email.text,
            fullName: _name.text,
            phone: _phone.text,
            role: _role,
            department: _department,
            password: _password.text,
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Đã tạo tài khoản'),
          content: SelectableText(
            'Gửi thông tin đăng nhập cho người dùng:\n\n'
            'Email: ${user.email}\nMật khẩu tạm: ${_password.text}\n\n'
            'Người dùng sẽ phải đổi mật khẩu ở lần đăng nhập đầu tiên.',
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: 'Email: ${user.email}\nMật khẩu tạm: ${_password.text}'),
              ),
              child: const Text('Sao chép'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Xong')),
          ],
        ),
      );
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo tài khoản')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validators.required(v, 'Họ tên'),
              decoration: const InputDecoration(labelText: 'Họ tên'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              validator: Validators.email,
              decoration: const InputDecoration(labelText: 'Email đăng nhập'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              validator: Validators.optionalPhone,
              decoration: const InputDecoration(labelText: 'Số điện thoại (không bắt buộc)'),
            ),
            const SizedBox(height: 16),
            RoleFields(
              role: _role,
              department: _department,
              onRoleChanged: (r) => setState(() {
                _role = r;
                if (r != UserRole.staff) _department = null;
              }),
              onDepartmentChanged: (d) => setState(() => _department = d),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              autocorrect: false,
              validator: Validators.password,
              decoration: InputDecoration(
                labelText: 'Mật khẩu tạm',
                helperText: 'Tối thiểu 8 ký tự, gồm cả chữ và số',
                suffixIcon: IconButton(
                  tooltip: 'Tạo ngẫu nhiên',
                  icon: const Icon(Icons.casino_outlined),
                  onPressed: () => _password.text = generateTempPassword(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            LoadingButton(loading: _saving, onPressed: _submit, label: 'Tạo tài khoản'),
          ],
        ),
      ),
    );
  }
}
