import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/company_branding.dart';

import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';

class SupplierEtaOrderPreviewScreen extends ConsumerWidget {
  const SupplierEtaOrderPreviewScreen({
    required this.order,
    required this.etaDate,
    super.key,
  });

  final PurchaseOrder order;
  final DateTime etaDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(currentBrandingProvider);
    final pdfData = buildPdfDataFromOrder(
      order,
      branding: branding,
      etaDate: etaDate,
      cacheSalt: 'supplier-eta-preview-${order.id}-${etaDate.millisecondsSinceEpoch}',
    );

    return Scaffold(
      appBar: AppBar(title: Text('PDF ${order.id}')),
      body: branding.id.isEmpty
          ? const AppSplash()
          : OrderPdfInlineView(data: pdfData),
    );
  }
}
