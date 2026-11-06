import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../application/apartments_providers.dart';
import 'apartment_detail_page.dart';

/// UC-07: Căn hộ của tôi (Cư dân). Nếu chỉ ở một căn thì mở thẳng chi tiết.
class MyApartmentsPage extends ConsumerWidget {
  const MyApartmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myApartmentsProvider);
    return list.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Căn hộ của tôi')),
        body: ErrorView(error: e, onRetry: () => ref.invalidate(myApartmentsProvider)),
      ),
      data: (items) {
        if (items.length == 1) return ApartmentDetailPage(apartmentId: items.first.id);
        return Scaffold(
          appBar: AppBar(title: const Text('Căn hộ của tôi')),
          body: items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Tài khoản của bạn chưa được gắn với căn hộ nào.\n'
                      'Vui lòng liên hệ Ban quản lý.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final a in items)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.apartment),
                          title: Text('Căn ${a.code}'),
                          subtitle: Text(
                            'Tầng ${a.floor} · ${formatArea(a.area)} · '
                            '${a.myMembership?.relation.label ?? ''}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/apartments/${a.id}'),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
