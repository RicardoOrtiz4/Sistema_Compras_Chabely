import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(createOrderControllerProvider);

    ref.listen(createOrderControllerProvider, (previous, next) {
      if (previous?.message != next.message && next.message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.message!)));
      }
      if (previous?.error != next.error && next.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final userAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Requisici�n de compra'),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _OrderHeader(userName: user.name, area: user.areaDisplay),
                const SizedBox(height: 12),
                Text('Selecciona urgencia', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<PurchaseOrderUrgency>(
                  segments: PurchaseOrderUrgency.values
                      .map((urgency) => ButtonSegment(
                            value: urgency,
                            label: Text(urgency.label),
                          ))
                      .toList(),
                  selected: <PurchaseOrderUrgency>{controller.urgency},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => ref
                      .read(createOrderControllerProvider.notifier)
                      .setUrgency(value.first),
                ),
                const SizedBox(height: 24),
                Text('Items', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                ...controller.items.asMap().entries.map(
                  (entry) => _OrderItemCard(
                    index: entry.key,
                    draft: entry.value,
                    onChanged: (updated) => ref
                        .read(createOrderControllerProvider.notifier)
                        .updateItem(entry.key, updated),
                    onRemove: controller.items.length == 1
                        ? null
                        : () => ref
                            .read(createOrderControllerProvider.notifier)
                            .removeItem(entry.key),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref
                      .read(createOrderControllerProvider.notifier)
                      .addItem(),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar rengl�n'),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: controller.isSaving
                            ? null
                            : () =>
                                ref.read(createOrderControllerProvider.notifier).saveDraft(),
                        child: controller.isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Guardar borrador'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: controller.isSubmitting
                            ? null
                            : () async {
                                if (!(_formKey.currentState?.validate() ?? false)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Revisa los campos requeridos')),
                                  );
                                  return;
                                }
                                await ref
                                    .read(createOrderControllerProvider.notifier)
                                    .submit();
                              },
                        child: controller.isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Enviar a revisi�n'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.userName, required this.area});

  final String userName;
  final String area;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Folio: Se asignar� al enviar',
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('Solicitante: $userName'),
            Text('�rea: $area'),
            Text('Fecha: ${now.toFullDateTime()}'),
          ],
        ),
      ),
    );
  }
}

class _OrderItemCard extends StatefulWidget {
  const _OrderItemCard({
    required this.index,
    required this.draft,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final OrderItemDraft draft;
  final ValueChanged<OrderItemDraft> onChanged;
  final VoidCallback? onRemove;

  @override
  State<_OrderItemCard> createState() => _OrderItemCardState();
}

class _OrderItemCardState extends State<_OrderItemCard> {
  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Item ${draft.line}', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (widget.onRemove != null)
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            TextFormField(
              key: ValueKey('pieces-${widget.index}'),
              initialValue: draft.pieces.toString(),
              decoration: const InputDecoration(labelText: 'Piezas requeridas'),
              keyboardType: TextInputType.number,
              onChanged: (value) => widget.onChanged(
                draft.copyWith(pieces: int.tryParse(value) ?? draft.pieces),
              ),
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed <= 0) {
                  return 'Debe ser mayor a 0';
                }
                return null;
              },
            ),
            TextFormField(
              key: ValueKey('part-${widget.index}'),
              initialValue: draft.partNumber,
              decoration: const InputDecoration(labelText: 'No. de parte'),
              onChanged: (value) => widget.onChanged(draft.copyWith(partNumber: value)),
              validator: (value) => value == null || value.isEmpty ? 'Requerido' : null,
            ),
            TextFormField(
              key: ValueKey('desc-${widget.index}'),
              initialValue: draft.description,
              decoration: const InputDecoration(labelText: 'Descripci�n del producto'),
              minLines: 2,
              maxLines: 3,
              onChanged: (value) => widget.onChanged(draft.copyWith(description: value)),
              validator: (value) => value == null || value.isEmpty ? 'Requerido' : null,
            ),
            TextFormField(
              key: ValueKey('qty-${widget.index}'),
              initialValue: draft.quantity.toString(),
              decoration: const InputDecoration(labelText: 'Cantidad'),
              keyboardType: TextInputType.number,
              onChanged: (value) => widget.onChanged(
                draft.copyWith(quantity: double.tryParse(value) ?? draft.quantity),
              ),
              validator: (value) {
                final parsed = double.tryParse(value ?? '');
                if (parsed == null || parsed <= 0) {
                  return 'Cantidad inv�lida';
                }
                return null;
              },
            ),
            TextFormField(
              key: ValueKey('unit-${widget.index}'),
              initialValue: draft.unit,
              decoration: const InputDecoration(labelText: 'Unidad de medida'),
              onChanged: (value) => widget.onChanged(draft.copyWith(unit: value)),
              validator: (value) => value == null || value.isEmpty ? 'Requerido' : null,
            ),
            TextFormField(
              key: ValueKey('customer-${widget.index}'),
              initialValue: draft.customer ?? '',
              decoration: const InputDecoration(labelText: 'Cliente (opcional)'),
              onChanged: (value) => widget.onChanged(draft.copyWith(customer: value)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    draft.estimatedDate != null
                        ? 'Fecha estimada: ${draft.estimatedDate!.toShortDate()}'
                        : 'Selecciona fecha estimada',
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: draft.estimatedDate ?? DateTime.now(),
                    );
                    if (date != null) {
                      widget.onChanged(draft.copyWith(estimatedDate: date));
                    }
                  },
                  child: const Text('Seleccionar'),
                ),
                if (draft.estimatedDate != null)
                  IconButton(
                    onPressed: () => widget.onChanged(
                      draft.copyWith(removeEstimatedDate: true),
                    ),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


