import 'package:flutter/material.dart';

import '../network/api_client.dart';
import 'common.dart';

/// Danh sách có phân trang: tự tải trang đầu, cuộn gần cuối thì tải thêm,
/// kéo xuống để làm mới. Muốn tải lại từ đầu (đổi bộ lọc) thì đổi `key`.
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.emptyText = 'Không có dữ liệu',
    this.padding = const EdgeInsets.only(bottom: 88),
    this.separated = true,
  });

  final Future<Paged<T>> Function(int page) fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  final EdgeInsetsGeometry padding;
  final bool separated;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final _items = <T>[];
  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final res = await widget.fetch(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(res.items);
        _page = res.page;
        _total = res.total;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final res = await widget.fetch(_page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(res.items);
        _page = res.page;
        _total = res.total;
      });
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return ErrorView(error: _error!, onRetry: _reload);

    return RefreshIndicator(
      onRefresh: _reload,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) _loadMore();
          return false;
        },
        child: _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Center(child: Text(widget.emptyText)),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: widget.padding,
                itemCount: _items.length + (_hasMore ? 1 : 0),
                separatorBuilder: (_, _) =>
                    widget.separated ? const Divider(height: 1) : const SizedBox.shrink(),
                itemBuilder: (context, i) {
                  if (i >= _items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return widget.itemBuilder(context, _items[i]);
                },
              ),
      ),
    );
  }
}
