import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_download_helper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_rejection_history.dart';

class OrderPdfViewScreen extends ConsumerStatefulWidget {
  const OrderPdfViewScreen({
    required this.orderId,
    this.hideBuyerFields = false,
    super.key,
  });

  final String orderId;
  final bool hideBuyerFields;

  @override
  ConsumerState<OrderPdfViewScreen> createState() => _OrderPdfViewScreenState();
}

class _OrderPdfViewScreenState extends ConsumerState<OrderPdfViewScreen> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    final actions = orderAsync.maybeWhen(
      data: (order) {
        if (order == null) return const <Widget>[];

        return <Widget>[
          IconButton(
            onPressed: _downloading ? null : () => _downloadPdf(order),
            tooltip: 'Descargar PDF',
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
          _PdfViewHistoryActionButton(
            order: order,
            onShowHistory: (events) => _showHistory(context, order, events),
          ),
        ];
      },
      orElse: () => const <Widget>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF de orden'),
        actions: [
          ...actions,
        ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }

          final isRejectedDraft = _isRejectedDraft(order);
          final copyRoute =
              '/orders/create?copyFromId=${Uri.encodeComponent(order.id)}';

          return Column(
            children: [
              Expanded(
                child: _OrderPdfBody(
                  order: order,
                  hideBuyerFields: widget.hideBuyerFields,
                ),
              ),
              if (isRejectedDraft)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => guardedPush(context, copyRoute),
                      icon: const Icon(Icons.content_copy_outlined),
                      label: const Text('Copiar orden'),
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'OrderPdfViewScreen')}',
          ),
        ),
      ),
    );
  }

  void _showHistory(
    BuildContext context,
    PurchaseOrder order,
    List<PurchaseOrderEvent> events,
  ) {
    final branding = ref.read(currentBrandingProvider);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OrderRejectionHistory(
              branding: branding,
              order: order,
              events: events,
              showOnlyOriginal: true,
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadPdf(PurchaseOrder order) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final branding = ref.read(currentBrandingProvider);
      final pdfData = _buildOrderPdfDataForView(
        branding,
        order,
        hideBuyerFields: widget.hideBuyerFields,
      );
      final bytes = await buildOrderPdf(pdfData, useIsolate: false);
      if (!mounted) return;
      await savePdfBytes(
        context,
        bytes: bytes,
        suggestedName: 'requisicion_${order.id}.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }
}

bool _isRejectedDraft(PurchaseOrder order) {
  final reason = order.lastReturnReason;
  return order.status == PurchaseOrderStatus.draft &&
      ((reason != null && reason.trim().isNotEmpty) || order.returnCount > 0);
}

class _OrderPdfBody extends ConsumerWidget {
  const _OrderPdfBody({
    required this.order,
    required this.hideBuyerFields,
  });

  final PurchaseOrder order;
  final bool hideBuyerFields;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(currentBrandingProvider);
    final pdfData = _buildOrderPdfDataForView(
      branding,
      order,
      hideBuyerFields: hideBuyerFields,
    );
    return OrderPdfInlineView(data: pdfData);
  }
}

OrderPdfData _buildOrderPdfDataForView(
  CompanyBranding branding,
  PurchaseOrder order, {
  required bool hideBuyerFields,
}) {
  final sanitizedItems = !hideBuyerFields
      ? null
      : order.items
            .map(
              (item) => OrderItemDraft.fromModel(
                item,
              ).copyWith(customer: '', clearSupplier: true),
            )
            .toList(growable: false);
  return buildPdfDataFromOrder(
    order,
    branding: branding,
    supplier: hideBuyerFields ? '' : null,
    items: sanitizedItems,
    hideBudget: hideBuyerFields,
    suppressUpdatedAt: _isRejectedDraft(order),
  );
}

class _PdfViewHistoryActionButton extends ConsumerWidget {
  const _PdfViewHistoryActionButton({
    required this.order,
    required this.onShowHistory,
  });

  final PurchaseOrder order;
  final ValueChanged<List<PurchaseOrderEvent>> onShowHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (order.returnCount <= 0) {
      return IconButton(
        icon: const Icon(Icons.history),
        tooltip: 'Historial de cambios',
        onPressed: null,
      );
    }

    final eventsAsync = ref.watch(orderEventsProvider(order.id));

    return eventsAsync.when(
      data: (events) {
        final canShow = events.any((event) => event.type == 'return');

        return IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Historial de cambios',
          onPressed: canShow ? () => onShowHistory(events) : null,
        );
      },
      loading: () => IconButton(
        icon: const Icon(Icons.history),
        tooltip: 'Historial de cambios',
        onPressed: null,
      ),
      error: (_, __) => IconButton(
        icon: const Icon(Icons.history),
        tooltip: 'Historial de cambios',
        onPressed: null,
      ),
    );
  }
}
