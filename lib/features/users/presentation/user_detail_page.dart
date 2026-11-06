import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/app_user.dart';
import '../application/users_providers.dart';
import '../data/users_repository.dart';
import 'password_generator.dart';
import 'role_fields.dart';

/// UC-04 (sửa, khóa/mở, đặt lại mật khẩu) và UC-05 (gán vai trò, bộ phận).
class UserDetailPage extends ConsumerWidget {
  const UserDetailPage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(userDetailProvider(userId));
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết tài khoản')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(userDetailProvider(userId))),
        data: (user) => _Body(user: user),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.user});
  final AppUser user;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;
  AppUser get user => widget.user;

  Future<void> _run(Future<AppUser> Function(UsersRepository repo) action, String done) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(usersRepositoryProvider));
      ref.invalidate(userDetailProvider(user.id));
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editInfo() async {
    final name = TextEditingController(text: user.fullName);
    final phone = TextEditingController(text: user.phone);
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa thông tin'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                validator: (v) => Validators.required(v, 'Họ tên'),
                decoration: const InputDecoration(labelText: 'Họ tên'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                validator: Validators.optionalPhone,
                decoration: const InputDecoration(labelText: 'Số điện thoại'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(
        (repo) => repo.update(user.id, fullName: name.text, phone: phone.text),
        'Đã cập nhật thông tin',
      );
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _changeRole() async {
    var role = user.role;
    var department = user.department;
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Vai trò & bộ phận'),
          content: Form(
            key: formKey,
            child: RoleFields(
              role: role,
              department: department,
              onRoleChanged: (r) => setLocal(() {
                role = r;
                if (r != UserRole.staff) department = null;
              }),
              onDepartmentChanged: (d) => setLocal(() => department = d),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run((repo) => repo.setRole(user.id, role, department), 'Đã cập nhật vai trò');
    }
  }

  Future<void> _toggleStatus() async {
    final locking = user.isActive;
    final ok = await confirmDialog(
      context,
      title: locking ? 'Khóa tài khoản' : 'Mở khóa tài khoản',
      message: locking
          ? '${user.fullName} sẽ không thể đăng nhập và bị đăng xuất khỏi mọi thiết bị.'
          : '${user.fullName} sẽ có thể đăng nhập lại.',
      confirmText: locking ? 'Khóa' : 'Mở khóa',
      destructive: locking,
    );
    if (ok) {
      await _run(
        (repo) => repo.setStatus(user.id, locking ? UserStatus.inactive : UserStatus.active),
        locking ? 'Đã khóa tài khoản' : 'Đã mở khóa tài khoản',
      );
    }
  }

  Future<void> _resetPassword() async {
    final password = generateTempPassword();
    final ok = await confirmDialog(
      context,
      title: 'Đặt lại mật khẩu',
      message:
          'Mật khẩu tạm mới: $password\n\n'
          'Người dùng bị đăng xuất khỏi mọi thiết bị và phải đổi mật khẩu khi đăng nhập lại.',
      confirmText: 'Đặt lại',
    );
    if (!ok) return;
    await _run((repo) => repo.resetPassword(user.id, password), 'Đã đặt lại mật khẩu');
    if (mounted) {
      await Clipboard.setData(ClipboardData(text: 'Email: ${user.email}\nMật khẩu tạm: $password'));
      if (mounted) showSnack(context, 'Đã sao chép mật khẩu tạm vào bộ nhớ tạm');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelf = ref.watch(currentUserProvider)?.id == user.id;
    final fmt = DateFormat('HH:mm dd/MM/yyyy');

    return AbsorbPointer(
      absorbing: _busy,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 28, child: Text(user.initials)),
            title: Text(user.fullName, style: theme.textTheme.titleLarge),
            subtitle: Text(user.roleLabel),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  InfoRow(icon: Icons.email_outlined, label: 'Email', value: user.email),
                  InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Điện thoại',
                    value: user.phone ?? 'Chưa cập nhật',
                  ),
                  InfoRow(
                    icon: user.isActive ? Icons.check_circle_outline : Icons.lock_outline,
                    label: 'Trạng thái',
                    value: user.status.label,
                  ),
                  InfoRow(
                    icon: Icons.login,
                    label: 'Đăng nhập',
                    value: user.lastLoginAt == null
                        ? 'Chưa đăng nhập'
                        : fmt.format(user.lastLoginAt!),
                  ),
                  if (user.mustChangePassword)
                    const InfoRow(
                      icon: Icons.info_outline,
                      label: 'Lưu ý',
                      value: 'Chưa đổi mật khẩu tạm',
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
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Sửa thông tin'),
                  onTap: _editInfo,
                ),
                if (!isSelf) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Đổi vai trò / bộ phận'),
                    onTap: _changeRole,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_reset),
                    title: const Text('Đặt lại mật khẩu'),
                    onTap: _resetPassword,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      user.isActive ? Icons.lock_outline : Icons.lock_open,
                      color: user.isActive ? theme.colorScheme.error : null,
                    ),
                    title: Text(
                      user.isActive ? 'Khóa tài khoản' : 'Mở khóa tài khoản',
                      style: user.isActive ? TextStyle(color: theme.colorScheme.error) : null,
                    ),
                    onTap: _toggleStatus,
                  ),
                ],
              ],
            ),
          ),
          if (isSelf)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Đây là tài khoản của bạn: không thể tự khóa hoặc đổi vai trò.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
