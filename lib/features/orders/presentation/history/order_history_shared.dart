import 'package:flutter/material.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_summary_lines.dart';

bool isHistoricalOrder(PurchaseOrder order) {
  return order.isWorkflowFinished;
}

bool isHistoryRejectedOrder(PurchaseOrder order) {
  return order.isRejectedDraft;
}

bool isUnifiedHistoryOrder(PurchaseOrder order) {
  return isHistoricalOrder(order) || isHistoryRejectedOrder(order);
}

List<String> buildHistoryAreaOptions(List<PurchaseOrder> orders) {
  final options = <String>{};
  for (final order in orders) {
    final value = order.areaName.trim();
    if (value.isNotEmpty) {
      options.add(value);
    }
  }
  final sorted = options.toList(growable: false);
  sorted.sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
  return sorted;
}

List<String> buildHistoryRequesterOptions(List<PurchaseOrder> orders) {
  final options = <String>{};
  for (final order in orders) {
    final value = order.requesterName.trim();
    if (value.isNotEmpty) {
      options.add(value);
    }
  }
  final sorted = options.toList(growable: false);
  sorted.sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
  return sorted;
}

class HistoryOrderCard extends StatelessWidget {
  const HistoryOrderCard({
    required this.order,
    super.key,
    this.includeRequester = false,
    this.includeArea = false,
    this.showCompletionLine = true,
  });

  final PurchaseOrder order;
  final bool includeRequester;
  final bool includeArea;
  final bool showCompletionLine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final completionLabel = _completionLabel(order);
    final isRejected = isHistoryRejectedOrder(order);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => guardedPush(context, '/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _HistoryBadge(
                    label: 'Folio ${order.id}',
                    background: scheme.primaryContainer,
                    foreground: scheme.onPrimaryContainer,
                  ),
                  _HistoryBadge(
                    label: order.urgency.label,
                    background: order.urgency == PurchaseOrderUrgency.urgente
                        ? scheme.errorContainer
                        : scheme.secondaryContainer,
                    foreground: order.urgency == PurchaseOrderUrgency.urgente
                        ? scheme.onErrorContainer
                        : scheme.onSecondaryContainer,
                  ),
                  if (order.isRequesterReceiptAutoConfirmed)
                    _HistoryBadge(
                      label: 'Cierre automatico',
                      background: scheme.tertiaryContainer,
                      foreground: scheme.onTertiaryContainer,
                    ),
                  if (isRejected)
                    _HistoryBadge(
                      label: 'Rechazada',
                      background: scheme.errorContainer,
                      foreground: scheme.onErrorContainer,
                    ),
                  if (isRejected)
                    _HistoryBadge(
                      label: order.isRejectedPendingAcknowledgment
                          ? 'No enterada'
                          : 'Enterada',
                      background: order.isRejectedPendingAcknowledgment
                          ? scheme.secondaryContainer
                          : scheme.tertiaryContainer,
                      foreground: order.isRejectedPendingAcknowledgment
                          ? scheme.onSecondaryContainer
                          : scheme.onTertiaryContainer,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                requesterReceiptStatusLabel(order),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              OrderSummaryLines(
                order: order,
                includeRequester: includeRequester,
                includeArea: includeArea,
                includeClientNote: true,
                emptyLabel: 'Sin detalles complementarios.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _HistoryMetaText(
                    icon: Icons.event_outlined,
                    label: 'Creada: ${_dateTimeLabel(order.createdAt)}',
                  ),
                  if (showCompletionLine)
                    _HistoryMetaText(
                      icon: Icons.task_alt_outlined,
                      label: completionLabel,
                    ),
                ],
              ),
              if (order.serviceRating != null) ...[
                const SizedBox(height: 12),
                _HistoryRatingCard(order: order),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => guardedPush(context, '/orders/${order.id}'),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Detalle'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => guardedPdfPush(
                      context,
                      '/orders/${order.id}/pdf',
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Ver PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => guardedPush(
                      context,
                      historyCopyOrderLocation(order.id),
                    ),
                    icon: const Icon(Icons.content_copy_outlined),
                    label: const Text('Copiar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryEmptyState extends StatelessWidget {
  const HistoryEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String historyCopyOrderLocation(String orderId) {
  return Uri(
    path: '/orders/create',
    queryParameters: {'copyFromId': orderId},
  ).toString();
}

String _completionLabel(PurchaseOrder order) {
  if (isHistoryRejectedOrder(order)) {
    final rejectedAt = order.updatedAt ?? order.createdAt;
    return 'Rechazada: ${_dateTimeLabel(rejectedAt)}';
  }
  if (order.isClosedWithoutPurchase) {
    return 'Cerrada sin compra: ${_dateTimeLabel(order.updatedAt)}';
  }
  if (order.isClosedPartially) {
    final receivedAt = order.requesterReceivedAt;
    if (receivedAt != null) {
      return 'Cerrada parcial: ${receivedAt.toFullDateTime()}';
    }
    return 'Cerrada parcial: ${_dateTimeLabel(order.updatedAt)}';
  }
  final receivedAt = order.requesterReceivedAt;
  if (receivedAt != null) {
    return 'Recibida: ${receivedAt.toFullDateTime()}';
  }
  final completedAt = order.completedAt;
  if (completedAt != null) {
    return 'Finalizada: ${completedAt.toFullDateTime()}';
  }
  return 'Finalizada: ${_dateTimeLabel(order.updatedAt)}';
}

enum HistoryRejectionFilter {
  all,
  rejectedOnly,
  rejectedAcknowledged,
  rejectedPendingAcknowledgment,
}

bool matchesHistoryRejectionFilter(
  PurchaseOrder order,
  HistoryRejectionFilter filter,
) {
  switch (filter) {
    case HistoryRejectionFilter.all:
      return true;
    case HistoryRejectionFilter.rejectedOnly:
      return isHistoryRejectedOrder(order);
    case HistoryRejectionFilter.rejectedAcknowledged:
      return isHistoryRejectedOrder(order) && order.isRejectionAcknowledged;
    case HistoryRejectionFilter.rejectedPendingAcknowledgment:
      return order.isRejectedPendingAcknowledgment;
  }
}

String _dateTimeLabel(DateTime? value) {
  if (value == null) return 'Sin fecha';
  return value.toFullDateTime();
}

class _HistoryBadge extends StatelessWidget {
  const _HistoryBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HistoryMetaText extends StatelessWidget {
  const _HistoryMetaText({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _HistoryRatingCard extends StatelessWidget {
  const _HistoryRatingCard({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = order.serviceRating ?? 0;
    final comment = order.serviceRatingComment?.trim() ?? '';
    final ratedAt = order.serviceRatedAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Calificacion del servicio',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(
                  5,
                  (index) => Icon(
                    index < rating ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Text(
                '$rating/5',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (ratedAt != null)
                Text(
                  ratedAt.toFullDateTime(),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
