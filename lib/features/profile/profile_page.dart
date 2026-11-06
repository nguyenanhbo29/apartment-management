import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../auth/application/auth_controller.dart';
import '../auth/data/app_user.dart';

/// UC-03: Xem / cập nhật hồ sơ cá nhân.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _name = TextEditingController(text: user?.fullName);
    _phone = TextEditingController(text: user?.phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _cancelEdit(AppUser user) {
    _name.text = user.fullName;
    _phone.text = user.phone ?? '';
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(fullName: _name.text, phone: _phone.text);
      if (!mounted) return;
      setState(() => _editing = false);
      showSnack(context, 'Đã cập nhật hồ sơ');
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final ok = await confirmDialog(
      context,
      title: 'Đăng xuất',
      message: 'Bạn có chắc muốn đăng xuất?',
      confirmText: 'Đăng xuất',
    );
    if (ok) await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ cá nhân'),
        actions: [
          if (!_editing)
            IconButton(
              tooltip: 'Chỉnh sửa',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _editing = true),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              child: Text(user.initials, style: theme.textTheme.headlineMedium),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(user.fullName, style: theme.textTheme.titleLarge)),
          Center(child: Chip(label: Text(user.roleLabel))),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _editing
                  ? Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _name,
                            validator: (v) => Validators.required(v, 'Họ tên'),
                            decoration: const InputDecoration(labelText: 'Họ tên'),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            validator: Validators.optionalPhone,
                            decoration: const InputDecoration(labelText: 'Số điện thoại'),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _saving ? null : () => _cancelEdit(user),
                                  child: const Text('Hủy'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: LoadingButton(
                                  loading: _saving,
                                  onPressed: _save,
                                  label: 'Lưu',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        InfoRow(icon: Icons.email_outlined, label: 'Email', value: user.email),
                        InfoRow(
                          icon: Icons.phone_outlined,
                          label: 'Điện thoại',
                          value: user.phone ?? 'Chưa cập nhật',
                        ),
                        InfoRow(
                          icon: Icons.badge_outlined,
                          label: 'Vai trò',
                          value: user.roleLabel,
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_reset),
                  title: const Text('Đổi mật khẩu'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/change-password'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.logout, color: theme.colorScheme.error),
                  title: Text('Đăng xuất', style: TextStyle(color: theme.colorScheme.error)),
                  onTap: _logout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
