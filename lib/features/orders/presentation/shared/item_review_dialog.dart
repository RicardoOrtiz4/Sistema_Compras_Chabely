import 'package:flutter/material.dart';

import 'package:sistema_compras/features/orders/domain/purchase_order.dart';

class ItemReviewResult {
  const ItemReviewResult({required this.items, required this.summary});

  final List<PurchaseOrderItem> items;
  final String summary;
}

Future<ItemReviewResult?> showItemReviewDialog({
  required BuildContext context,
  required PurchaseOrder order,
  required String title,
  required String confirmLabel,
}) async {
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final result = await showModalBottomSheet<ItemReviewResult>(
    context: rootNavigator.context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return _ItemReviewSheet(
        order: order,
        title: title,
        confirmLabel: confirmLabel,
      );
    },
  );

  return result;
}

class _ItemReviewSheet extends StatefulWidget {
  const _ItemReviewSheet({
    required this.order,
    required this.title,
    required this.confirmLabel,
  });

  final PurchaseOrder order;
  final String title;
  final String confirmLabel;

  @override
  State<_ItemReviewSheet> createState() => _ItemReviewSheetState();
}

class _ItemReviewSheetState extends State<_ItemReviewSheet> {
  late final List<PurchaseOrderItem> _items;
  final TextEditingController _generalCommentController =
      TextEditingController();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _items = widget.order.items;
  }

  @override
  void dispose() {
    _generalCommentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
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
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (_errorText != null) ...[
                Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'El rechazo se registrara de forma general para toda la orden.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _generalCommentController,
                decoration: const InputDecoration(
                  labelText: 'Comentario general del rechazo',
                  helperText: 'Obligatorio.',
                ),
                minLines: 2,
                maxLines: 4,
                onChanged: (_) {
                  if (_errorText != null) {
                    setState(() => _errorText = null);
                  }
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('Item ${item.line}: ${item.description}'),
                      subtitle: Text('${item.quantity} ${item.unit}'.trim()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final generalComment = _generalCommentController.text
                            .trim();
                        if (generalComment.isEmpty) {
                          setState(() {
                            _errorText = 'Agrega un motivo general.';
                          });
                          return;
                        }

                        final updatedItems = <PurchaseOrderItem>[
                          for (final item in _items)
                            item.copyWith(
                              reviewFlagged: false,
                              reviewComment: null,
                              clearReviewComment: true,
                            ),
                        ];

                        Navigator.pop(
                          context,
                          ItemReviewResult(
                            items: updatedItems,
                            summary: generalComment,
                          ),
                        );
                      },
                      child: Text(widget.confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
