import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/preview/pdf_download_helper.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

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
  bool _acknowledging = false;
  bool _downloadingPdf = false;

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF de orden'),
        actions: orderAsync.valueOrNull == null
            ? null
            : [
                IconButton(
                  tooltip: 'Copiar',
                  onPressed: () => guardedPush(
                    context,
                    _copyOrderLocation(orderAsync.valueOrNull!.id),
                  ),
                  icon: const Icon(Icons.content_copy_outlined),
                ),
                IconButton(
                  tooltip: 'Descargar PDF',
                  onPressed: _downloadingPdf
                      ? null
                      : () => _downloadPdf(orderAsync.valueOrNull!),
                  icon: _downloadingPdf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                ),
              ],
      ),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const AppSplash();
          }

          return Column(
            children: [
              if (order.isRejectedPendingAcknowledgment ||
                  (order.isRejectedDraft && order.isRejectionAcknowledged))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (order.isRejectedPendingAcknowledgment)
                          FilledButton.icon(
                            onPressed: _acknowledging
                                ? null
                                : () => _acknowledgeRejectedOrder(order),
                            icon: _acknowledging
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.task_alt_outlined),
                            label: const Text('Marcar como enterado'),
                          )
                        else if (order.isRejectedDraft &&
                            order.isRejectionAcknowledged)
                          Chip(
                            avatar: const Icon(
                              Icons.task_alt_outlined,
                              size: 18,
                            ),
                            label: Text(
                              'Enterada ${order.rejectionAcknowledgedAt?.toShortDate() ?? ''}'
                                  .trim(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: _OrderPdfBody(
                  order: order,
                  hideBuyerFields: widget.hideBuyerFields,
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

  Future<void> _acknowledgeRejectedOrder(PurchaseOrder order) async {
    if (_acknowledging) return;
    setState(() => _acknowledging = true);
    try {
      await ref
          .read(purchaseOrderRepositoryProvider)
          .acknowledgeRejectedOrder(order.id);
      refreshOrderModuleData(ref, orderIds: <String>[order.id]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La orden rechazada se marco como enterada.'),
        ),
      );
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo marcar como enterada: ${reportError(error, stack, context: 'OrderPdfViewScreen.acknowledge')}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _acknowledging = false);
      }
    }
  }

  Future<void> _downloadPdf(PurchaseOrder order) async {
    if (_downloadingPdf) return;
    setState(() => _downloadingPdf = true);
    try {
      final bytes = await _resolvePdfBytes(order);
      if (!mounted) return;
      await savePdfBytes(
        context,
        bytes: bytes,
        suggestedName: '${order.id}.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _downloadingPdf = false);
      }
    }
  }

  Future<Uint8List> _resolvePdfBytes(PurchaseOrder order) async {
    if (!widget.hideBuyerFields) {
      final remotePdfUrl = order.pdfUrl?.trim();
      if (remotePdfUrl != null && remotePdfUrl.isNotEmpty) {
        final response = await http.get(Uri.parse(remotePdfUrl));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
      }
    }
    final branding = ref.read(currentBrandingProvider);
    final pdfData = _buildOrderPdfDataForView(
      branding,
      order,
      hideBuyerFields: widget.hideBuyerFields,
    );
    return buildOrderPdf(
      pdfData,
      useIsolate: false,
    );
  }
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
    final remotePdfUrl = hideBuyerFields ? null : order.pdfUrl;
    return OrderPdfInlineView(
      data: pdfData,
      remotePdfUrl: remotePdfUrl,
      pdfBuilder: (
        data, {
        bool useIsolate = false,
      }) => buildOrderPdf(
        data,
        useIsolate: false,
      ),
    );
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
  );
}

String _copyOrderLocation(String orderId) {
  return Uri(
    path: '/orders/create',
    queryParameters: {'copyFromId': orderId},
  ).toString();
}
