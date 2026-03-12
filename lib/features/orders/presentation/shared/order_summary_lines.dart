import 'package:flutter/material.dart';

import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class OrderSummaryLines extends StatelessWidget {
  const OrderSummaryLines({
    required this.order,
    super.key,
    this.includeRequester = false,
    this.includeArea = false,
    this.includeBudget = false,
    this.includeComprasComment = false,
    this.includeClientNote = false,
    this.emptyLabel = 'Sin detalles.',
  });

  final PurchaseOrder order;
  final bool includeRequester;
  final bool includeArea;
  final bool includeBudget;
  final bool includeComprasComment;
  final bool includeClientNote;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supplier = (order.supplier ?? '').trim();
    final internalOrder = (order.internalOrder ?? '').trim();
    final comprasComment = (order.comprasComment ?? '').trim();
    final clientNote = (order.clientNote ?? '').trim();

    final lines = <String>[
      if (includeRequester && order.requesterName.trim().isNotEmpty)
        'Solicitante: ${order.requesterName.trim()}',
      if (includeArea && order.areaName.trim().isNotEmpty)
        'Área: ${order.areaName.trim()}',
      if (supplier.isNotEmpty) 'Proveedor: $supplier',
      if (internalOrder.isNotEmpty) 'OC interna: $internalOrder',
      if (includeBudget && order.budget != null) 'Presupuesto: ${order.budget}',
      if (includeComprasComment && comprasComment.isNotEmpty)
        'Compras: $comprasComment',
      if (includeClientNote && clientNote.isNotEmpty) 'Nota: $clientNote',
    ];

    if (lines.isEmpty) {
      return Text(emptyLabel, style: theme.textTheme.bodySmall);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) ...[
          Text(line, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
        ],
      ],
    );
  }
}
