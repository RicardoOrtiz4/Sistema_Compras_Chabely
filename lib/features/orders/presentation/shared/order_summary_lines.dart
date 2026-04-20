import 'package:flutter/material.dart';

import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class OrderSummaryLines extends StatelessWidget {
  const OrderSummaryLines({
    required this.order,
    super.key,
    this.includeRequester = false,
    this.includeArea = false,
    this.includeBudget = false,
    this.includeUrgentJustification = true,
    this.includeComprasComment = false,
    this.includeClientNote = false,
    this.emptyLabel = 'Sin detalles.',
  });

  final PurchaseOrder order;
  final bool includeRequester;
  final bool includeArea;
  final bool includeBudget;
  final bool includeUrgentJustification;
  final bool includeComprasComment;
  final bool includeClientNote;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supplier = (order.supplier ?? '').trim();
    final itemInternalOrders = order.items
        .map((item) => (item.internalOrder ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final internalOrder = itemInternalOrders.isNotEmpty
        ? itemInternalOrders.join(', ')
        : (order.internalOrder ?? '').trim();
    final clientNote = (order.clientNote ?? '').trim();
    final urgentJustification = (order.urgentJustification ?? '').trim();
    final notPurchasedCount = countItemsMarkedAsNotPurchased(order);

    final lines = <String>[
      if (includeRequester && order.requesterName.trim().isNotEmpty)
        'Solicitante: ${order.requesterName.trim()}',
      if (includeArea && order.areaName.trim().isNotEmpty)
        'Área: ${order.areaName.trim()}',
      if (supplier.isNotEmpty) 'Proveedor: $supplier',
      if (internalOrder.isNotEmpty)
        itemInternalOrders.length > 1
            ? 'OC internas: $internalOrder'
            : 'OC interna: $internalOrder',
      if (includeBudget && order.budget != null) 'Presupuesto: ${order.budget}',
      if (notPurchasedCount > 0)
        'Items cerrados sin compra: $notPurchasedCount',
      if (includeClientNote && clientNote.isNotEmpty) 'Nota: $clientNote',
    ];

    final hasUrgentJustification =
        includeUrgentJustification && urgentJustification.isNotEmpty;

    if (lines.isEmpty && !hasUrgentJustification) {
      return Text(emptyLabel, style: theme.textTheme.bodySmall);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) ...[
          Text(line, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
        ],
        if (hasUrgentJustification) ...[
          Text(
            'Urgente: $urgentJustification',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
        ],
      ],
    );
  }
}
