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
  late final List<bool> _flags;
  late final List<String> _comments;
  late final List<String> _searchTexts;
  late List<int> _filteredIndexes;
  final Map<int, TextEditingController> _controllers = {};
  final TextEditingController _searchController = TextEditingController();
  int _flaggedCount = 0;
  String _searchQuery = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _items = widget.order.items;
    _flags = [for (final item in _items) item.reviewFlagged];
    _comments = [for (final item in _items) (item.reviewComment ?? '')];
    _searchTexts = [for (final item in _items) _buildItemSearchText(item)];
    _flaggedCount = _flags.where((value) => value).length;
    _filteredIndexes = List<int>.generate(_items.length, (index) => index);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _searchController.dispose();
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
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Buscar artí­culo',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _updateSearch,
              ),
              const SizedBox(height: 8),
              const _ReviewHeaderRow(),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: _filteredIndexes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final itemIndex = _filteredIndexes[index];
                    final item = _items[itemIndex];

                    final controller = _controllers.putIfAbsent(
                      itemIndex,
                      () => TextEditingController(text: _comments[itemIndex]),
                    );

                    final flagged = _flags[itemIndex];

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
                                if (newValue == _flags[itemIndex]) return;
                                setState(() {
                                  _flaggedCount += newValue ? 1 : -1;
                                  _flags[itemIndex] = newValue;
                                  if (!newValue) {
                                    _comments[itemIndex] = '';
                                    final c = _controllers[itemIndex];
                                    if (c != null) c.text = '';
                                  }
                                  if (_errorText != null) {
                                    _errorText = null;
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
                                      _comments[itemIndex] = controller.text;
                                      if (_errorText != null) {
                                        setState(() => _errorText = null);
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
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (_flaggedCount == 0) {
                          setState(() {
                            _errorText = 'Selecciona al menos un artÃ­culo.';
                          });
                          return;
                        }

                        for (var i = 0; i < _items.length; i++) {
                          if (!_flags[i]) continue;
                          if (_comments[i].trim().isEmpty) {
                            setState(() {
                              _errorText =
                                  'Agrega un motivo en todos los artÃ­culos marcados.';
                            });
                            return;
                          }
                        }

                        final updatedItems = <PurchaseOrderItem>[];
                        final summaryParts = <String>[];

                        for (var i = 0; i < _items.length; i++) {
                          final comment = _comments[i].trim();
                          final flagged = _flags[i];

                          updatedItems.add(
                            _items[i].copyWith(
                              reviewFlagged: flagged,
                              reviewComment: flagged ? comment : null,
                              clearReviewComment: !flagged,
                            ),
                          );

                          if (flagged) {
                            summaryParts.add('Item ${_items[i].line}: $comment');
                          }
                        }

                        Navigator.pop(
                          context,
                          ItemReviewResult(
                            items: updatedItems,
                            summary: summaryParts.join(' | '),
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

  void _updateSearch(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == _searchQuery) return;
    setState(() {
      _searchQuery = normalized;
      if (_searchQuery.isEmpty) {
        _filteredIndexes = List<int>.generate(_items.length, (index) => index);
        return;
      }
      final matches = <int>[];
      for (var index = 0; index < _items.length; index++) {
        if (_searchTexts[index].contains(_searchQuery)) {
          matches.add(index);
        }
      }
      _filteredIndexes = matches;
    });
  }
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
          Expanded(flex: 3, child: Text('ArtÃ­culo', style: labelStyle)),
          const SizedBox(width: 8),
          Expanded(flex: 4, child: Text('Motivo', style: labelStyle)),
        ],
      ),
    );
  }
}


String _buildItemSearchText(PurchaseOrderItem item) {
  return [
    item.line.toString(),
    item.partNumber,
    item.description,
  ].where((value) => value.trim().isNotEmpty).join(' ').toLowerCase();
}
