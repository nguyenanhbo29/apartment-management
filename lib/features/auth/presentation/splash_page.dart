import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../application/auth_controller.dart';

class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: auth.hasError && !auth.isLoading
          ? ErrorView(
              error: auth.error!,
              onRetry: () => ref.read(authControllerProvider.notifier).retry(),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
