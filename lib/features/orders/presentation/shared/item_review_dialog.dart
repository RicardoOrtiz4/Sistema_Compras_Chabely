import 'package:flutter/material.dart';

import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class ItemReviewResult {
  const ItemReviewResult({
    required this.items,
    required this.summary,
  });

  final List<PurchaseOrderItem> items;
  final String summary;
}

Future<ItemReviewResult?> showItemReviewDialog({
  required BuildContext context,
  required PurchaseOrder order,
  required String title,
  required String confirmLabel,
}) async {
  final items = order.items;

  // Estado inicial por item
  final flags = <bool>[
    for (final item in items) item.reviewFlagged,
  ];
  final comments = <String>[
    for (final item in items) (item.reviewComment ?? ''),
  ];

  final controllers = <int, TextEditingController>{};
  final searchController = TextEditingController();
  String? errorText;

  final result = await showModalBottomSheet<ItemReviewResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setState) {
              final query = searchController.text.trim().toLowerCase();

              final filteredIndexes = <int>[];
              for (var i = 0; i < items.length; i++) {
                if (_matchesQuery(items[i], query)) {
                  filteredIndexes.add(i);
                }
              }

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    if (errorText != null) ...[
                      Text(
                        errorText!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar artículo',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    const _ReviewHeaderRow(),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: filteredIndexes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final itemIndex = filteredIndexes[index];
                          final item = items[itemIndex];

                          final controller = controllers.putIfAbsent(
                            itemIndex,
                            () => TextEditingController(text: comments[itemIndex]),
                          );

                          final flagged = flags[itemIndex];

                          final background = flagged
                              ? Theme.of(context).colorScheme.surfaceContainerHighest
                              : Theme.of(context).colorScheme.surface;

                          return Container(
                            decoration: BoxDecoration(
                              color: background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 36,
                                  child: Checkbox(
                                    value: flagged,
                                    onChanged: (value) {
                                      final newValue = value ?? false;
                                      setState(() {
                                        flags[itemIndex] = newValue;
                                        if (!newValue) {
                                          comments[itemIndex] = '';
                                          final c = controllers[itemIndex];
                                          if (c != null) c.text = '';
                                        }
                                        if (errorText != null) {
                                          errorText = null;
                                        }
                                      });
                                    },
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Item ${item.line}: ${item.description}',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 4,
                                  child: flagged
                                      ? TextField(
                                          controller: controller,
                                          decoration: const InputDecoration(
                                            labelText: 'Motivo',
                                          ),
                                          minLines: 2,
                                          maxLines: 3,
                                          onChanged: (_) {
                                            comments[itemIndex] = controller.text;
                                            if (errorText != null) {
                                              setState(() => errorText = null);
                                            }
                                          },
                                        )
                                      : const Padding(
                                          padding: EdgeInsets.only(top: 12),
                                          child: Text(
                                            'Activa para indicar motivo.',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final flaggedCount = flags.where((v) => v).length;
                              if (flaggedCount == 0) {
                                setState(() {
                                  errorText = 'Selecciona al menos un artículo.';
                                });
                                return;
                              }

                              for (var i = 0; i < items.length; i++) {
                                if (!flags[i]) continue;
                                if (comments[i].trim().isEmpty) {
                                  setState(() {
                                    errorText =
                                        'Agrega un motivo en todos los artículos marcados.';
                                  });
                                  return;
                                }
                              }

                              final updatedItems = <PurchaseOrderItem>[];
                              final summaryParts = <String>[];

                              for (var i = 0; i < items.length; i++) {
                                final comment = comments[i].trim();
                                final flagged = flags[i];

                                updatedItems.add(
                                  items[i].copyWith(
                                    reviewFlagged: flagged,
                                    reviewComment: flagged ? comment : null,
                                    clearReviewComment: !flagged,
                                  ),
                                );

                                if (flagged) {
                                  summaryParts.add('Item ${items[i].line}: $comment');
                                }
                              }

                              Navigator.pop(
                                sheetContext,
                                ItemReviewResult(
                                  items: updatedItems,
                                  summary: summaryParts.join(' | '),
                                ),
                              );
                            },
                            child: Text(confirmLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );

  for (final controller in controllers.values) {
    controller.dispose();
  }
  searchController.dispose();

  return result;
}

class _ReviewHeaderRow extends StatelessWidget {
  const _ReviewHeaderRow();

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const SizedBox(width: 36),
          Expanded(flex: 3, child: Text('Artículo', style: labelStyle)),
          const SizedBox(width: 8),
          Expanded(flex: 4, child: Text('Motivo', style: labelStyle)),
        ],
      ),
    );
  }
}

bool _matchesQuery(PurchaseOrderItem item, String query) {
  if (query.isEmpty) return true;

  final text = [
    item.line.toString(),
    item.partNumber,
    item.description,
  ].where((value) => value.trim().isNotEmpty).join(' ').toLowerCase();

  return text.contains(query);
}
