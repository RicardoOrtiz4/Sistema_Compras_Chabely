import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';

class OrderPdfPreloadGate extends ConsumerStatefulWidget {
  const OrderPdfPreloadGate({
    required this.orders,
    required this.child,
    this.limit,
    this.enabled = true,
    super.key,
  });

  final List<PurchaseOrder> orders;
  final Widget child;
  final int? limit;
  final bool enabled;

  @override
  ConsumerState<OrderPdfPreloadGate> createState() =>
      _OrderPdfPreloadGateState();
}

class _OrderPdfPreloadGateState extends ConsumerState<OrderPdfPreloadGate> {
  late final String _prefetchGroupKey;
  late CompanyBranding _branding;
  ProviderSubscription<CompanyBranding>? _brandingSubscription;
  String? _scheduledKey;
  int _generation = 0;
  bool _syncQueued = false;

  @override
  void initState() {
    super.initState();
    _prefetchGroupKey = 'order-pdf-gate:${identityHashCode(this)}';
    _branding = ref.read(currentBrandingProvider);
    _brandingSubscription = ref.listenManual<CompanyBranding>(
      currentBrandingProvider,
      (_, next) {
        _branding = next;
        _queueSync();
      },
    );
    _queueSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.of(context);
    _queueSync();
  }

  @override
  void didUpdateWidget(covariant OrderPdfPreloadGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.limit != widget.limit ||
        !identical(oldWidget.orders, widget.orders)) {
      _queueSync();
    }
  }

  @override
  void dispose() {
    _brandingSubscription?.close();
    bumpPdfPrefetchGroup(_prefetchGroupKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void _queueSync() {
    if (_syncQueued) return;
    _syncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncQueued = false;
      if (!mounted) return;
      _syncPrefetch();
    });
  }

  void _syncPrefetch() {
    if (!widget.enabled || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      _cancelScheduledPrefetch();
      return;
    }
    _schedulePrefetch(_branding);
  }

  void _schedulePrefetch(CompanyBranding branding) {
    final effectiveLimit = widget.limit ?? 1;
    if (effectiveLimit <= 0 || widget.orders.isEmpty) {
      _cancelScheduledPrefetch();
      return;
    }

    final nextKey = _buildPrefetchKey(
      orders: widget.orders,
      branding: branding,
      limit: effectiveLimit,
    );
    if (_scheduledKey == nextKey) return;
    _scheduledKey = nextKey;
    final generation = bumpPdfPrefetchGroup(_prefetchGroupKey);
    _generation = generation;
    final prefetchLimit = effectiveLimit > 1 ? 1 : effectiveLimit;
    if (prefetchLimit <= 0) {
      return;
    }
    final scheduledOrders = widget.orders
        .take(prefetchLimit)
        .toList(growable: false);
    final scheduledBranding = branding;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        if (_generation != generation) {
          return;
        }
        if (scheduledOrders.isEmpty) {
          return;
        }
        prefetchOrderPdfsForOrders(
          scheduledOrders,
          branding: scheduledBranding,
          limit: prefetchLimit,
          groupKey: _prefetchGroupKey,
          generation: generation,
        );
      });
    });
  }

  void _cancelScheduledPrefetch() {
    _scheduledKey = null;
    _generation = bumpPdfPrefetchGroup(_prefetchGroupKey);
  }

  String _buildPrefetchKey({
    required List<PurchaseOrder> orders,
    required CompanyBranding branding,
    required int limit,
  }) {
    final buffer = StringBuffer()
      ..write(branding.id)
      ..write('|')
      ..write(limit)
      ..write('|');

    for (final order in orders.take(limit)) {
      buffer
        ..write(order.id)
        ..write(':')
        ..write(order.updatedAt?.millisecondsSinceEpoch ?? 0)
        ..write('|');
    }

    return buffer.toString();
  }
}
