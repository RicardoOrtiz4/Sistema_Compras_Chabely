import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/business_calendar.dart';
import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/searchable_select.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/partners/data/partner_repository.dart';
import 'package:sistema_compras/core/navigation_guard.dart';

const _unitOptions = <String>[
  'PZA',
  'KG',
  'LT',
  'GAL',
  'M',
  'CM',
  'MM',
  'PULG',
  'PAQ',
  'CAJA',
  'JGO',
];

const _urgencyOrder = <PurchaseOrderUrgency>[
  PurchaseOrderUrgency.normal,
  PurchaseOrderUrgency.urgente,
];

const _maxCorrections = 3;

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key, this.draftId, this.copyFromId});

  final String? draftId;
  final String? copyFromId;

  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _draftRequested = false;
  bool _resetRequested = false;
  bool _copyRequested = false;

  late final TextEditingController _notesController;
  late final TextEditingController _urgentJustificationController;
  ScaffoldMessengerState? _messenger;
  ProviderSubscription<CreateOrderState>? _controllerSubscription;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _urgentJustificationController = TextEditingController();
    _controllerSubscription =
        ref.listenManual<CreateOrderState>(createOrderControllerProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;

      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;

      if (previous?.message != next.message && next.message != null) {
        _messenger?.showSnackBar(SnackBar(content: Text(next.message!)));
      }

      if (previous?.error != next.error && next.error != null) {
        final message = reportError(
          next.error!,
          StackTrace.current,
          context: 'CreateOrderScreen',
        );
        _messenger?.showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  @override
  void dispose() {
    _controllerSubscription?.close();
    _notesController.dispose();
    _urgentJustificationController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _messenger = ScaffoldMessenger.maybeOf(context);

    final draftId = widget.draftId;
    if (!_draftRequested && draftId != null && draftId.isNotEmpty) {
      _draftRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(createOrderControllerProvider.notifier).loadDraft(draftId);
      });
    }

    final copyFromId = widget.copyFromId;
    if (!_copyRequested && copyFromId != null && copyFromId.isNotEmpty) {
      _copyRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(createOrderControllerProvider.notifier).loadFromOrder(copyFromId);
      });
    }

    if (!_resetRequested &&
        (draftId == null || draftId.isEmpty) &&
        (copyFromId == null || copyFromId.isEmpty)) {
      _resetRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = ref.read(createOrderControllerProvider);
        final shouldReset = state.draftId != null ||
            state.requestedDeliveryDate != null ||
            state.notes.isNotEmpty ||
            state.urgentJustification.isNotEmpty ||
            state.items.length != 1;
        if (shouldReset) {
          ref.read(createOrderControllerProvider.notifier).reset();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(createOrderControllerProvider);
    final notifier = ref.read(createOrderControllerProvider.notifier);

    final userAsync = ref.watch(currentUserProfileProvider);

    final scheme = Theme.of(context).colorScheme;
    final urgencyColor = controller.urgency.color(scheme);
    final urgencyTextColor =
        ThemeData.estimateBrightnessForColor(urgencyColor) == Brightness.dark
            ? Colors.white
            : Colors.black;

    final isLastAttempt = controller.returnCount == _maxCorrections - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Requisición de compra'),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const AppSplash();
          if (controller.isLoadingDraft) return const AppSplash();

          // Mantener notas sincronizadas sin duplicar cambios
          if (_notesController.text != controller.notes) {
            _notesController.value = _notesController.value.copyWith(
              text: controller.notes,
              selection: TextSelection.collapsed(offset: controller.notes.length),
              composing: TextRange.empty,
            );
          }
          if (_urgentJustificationController.text != controller.urgentJustification) {
            _urgentJustificationController.value =
                _urgentJustificationController.value.copyWith(
              text: controller.urgentJustification,
              selection: TextSelection.collapsed(
                offset: controller.urgentJustification.length,
              ),
              composing: TextRange.empty,
            );
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (isLastAttempt) ...[
                  const SizedBox(height: 12),
                  _LastAttemptWarning(
                    draftId: controller.draftId,
                  ),
                ],

                if (controller.returnCount >= _maxCorrections) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Máximo de correcciones alcanzado',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Esta requisición ya no puede enviarse a revisión. Crea otra requisición.',
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                Text('Urgencia', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<PurchaseOrderUrgency>(
                      segments: _urgencyOrder
                          .map(
                            (urgency) => ButtonSegment(
                              value: urgency,
                              label: Text(urgency.label),
                            ),
                          )
                          .toList(),
                      selected: <PurchaseOrderUrgency>{controller.urgency},
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) return urgencyColor;
                          return null;
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) return urgencyTextColor;
                          return null;
                        }),
                      ),
                      onSelectionChanged: (value) => notifier.setUrgency(value.first),
                    ),
                    if (controller.urgency == PurchaseOrderUrgency.urgente) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _urgentJustificationController,
                          decoration: const InputDecoration(
                            labelText: 'Justificacion de urgencia',
                            helperText:
                                'Describe por que este item impide seguir trabajando o puede parar produccion.',
                          ),
                          minLines: 3,
                          maxLines: 5,
                          validator: (_) => notifier.urgentJustificationError(),
                          onChanged: notifier.setUrgentJustification,
                        ),
                      ),
                    ],
                  ],
                ),
                if (controller.urgency == PurchaseOrderUrgency.urgente) ...[
                  const SizedBox(height: 12),
                  _UrgentGuidanceBox(
                    scheme: Theme.of(context).colorScheme,
                  ),
                ],

                const SizedBox(height: 24),
                Text('Artículos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _RequestedDeliveryDateSection(
                  urgency: controller.urgency,
                  requestedDeliveryDate: controller.requestedDeliveryDate,
                  onPickDate: () => _pickRequestedDeliveryDate(
                    controller.requestedDeliveryDate,
                    controller.urgency,
                    notifier,
                  ),
                  onClearDate: controller.requestedDeliveryDate == null
                      ? null
                      : () => notifier.setRequestedDeliveryDate(null),
                ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _importCsvItems(notifier),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Importar CSV'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            ref.read(createOrderControllerProvider.notifier).addItem(),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar artículo'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                _OrderItemsSection(
                  items: controller.items,
                  unitOptions: _unitOptions,
                  onAddClient: _addClientFromSearch,
                  onChanged: (index, updated) => ref
                      .read(createOrderControllerProvider.notifier)
                      .updateItem(index, updated),
                  onRemove: controller.items.length == 1
                      ? null
                      : (index) => ref
                          .read(createOrderControllerProvider.notifier)
                          .removeItem(index),
                ),

                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Observaciones'),
                  minLines: 3,
                  maxLines: 5,
                  onChanged: (value) =>
                      ref.read(createOrderControllerProvider.notifier).setNotes(value),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        controller.isSubmitting || controller.returnCount >= _maxCorrections
                            ? null
                            : () async {
                                if (!(_formKey.currentState?.validate() ?? false)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Revisa los campos requeridos'),
                                    ),
                                  );
                                  return;
                                }
                                guardedPdfPush(context, '/orders/preview');
                              },
                    child: controller.isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: AppSplash(compact: true, size: 20),
                          )
                        : Text(
                            controller.returnCount >= _maxCorrections
                                ? 'Requiere nueva requisición'
                                : 'Revisar PDF',
                          ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'CreateOrderScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _pickRequestedDeliveryDate(
    DateTime? currentValue,
    PurchaseOrderUrgency urgency,
    CreateOrderController notifier,
  ) async {
    final now = DateTime.now();
    final normalizedNow = normalizeCalendarDate(now);
    final urgentDates = nextBusinessDaysAfter(normalizedNow);
    final isUrgent = urgency == PurchaseOrderUrgency.urgente;
    final initialDate = isUrgent
        ? _resolveUrgentInitialDate(currentValue, urgentDates)
        : normalizeCalendarDate(currentValue ?? normalizedNow);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: isUrgent ? urgentDates.first : DateTime(1900, 1, 1),
      lastDate: isUrgent ? urgentDates.last : DateTime(2100, 12, 31),
      selectableDayPredicate: isUrgent
          ? (day) => isAllowedUrgentRequestedDeliveryDate(day, today: normalizedNow)
          : null,
    );
    if (picked == null) return;
    notifier.setRequestedDeliveryDate(picked);
  }

  Future<void> _importCsvItems(CreateOrderController notifier) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _messenger?.showSnackBar(
        const SnackBar(content: Text('No se pudo leer el archivo CSV.')),
      );
      return;
    }

    try {
      final content = utf8.decode(bytes);
      final items = _parseCsvItems(content);
      notifier.replaceItems(items);
      _messenger?.showSnackBar(
        SnackBar(content: Text('Se importaron ${items.length} artículos.')),
      );
    } on FormatException catch (error) {
      _messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      _messenger?.showSnackBar(
        const SnackBar(content: Text('No se pudo importar el CSV.')),
      );
    }
  }

  Future<String?> _addClientFromSearch(String query) async {
    final name = await _askNewPartnerName(
      title: 'Agregar cliente',
      label: 'Nombre del cliente',
      seed: query,
    );
    if (name == null) return null;

    final confirmed = await _confirmPartnerCreation(
      type: PartnerType.client,
      name: name,
    );
    if (!confirmed) return null;

    final uid = ref.read(currentUserProfileProvider).value?.id;
    if (uid == null) return null;

    final repo = ref.read(partnerRepositoryProvider);
    await repo.createPartner(uid: uid, type: PartnerType.client, name: name);
    return name;
  }

  Future<String?> _askNewPartnerName({
    required String title,
    required String label,
    String? seed,
  }) async {
    final controller = TextEditingController(text: seed ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<bool> _confirmPartnerCreation({
    required PartnerType type,
    required String name,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Crear ${type.label.toLowerCase()}'),
        content: Text('¿Confirmas crear ${type.label.toLowerCase()} "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

}

class _UrgentGuidanceBox extends StatelessWidget {
  const _UrgentGuidanceBox({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'El estado urgente solo es para items importantes que, sin ellos, no se pueda seguir trabajando o paren la produccion.',
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}

class _RequestedDeliveryDateSection extends StatelessWidget {
  const _RequestedDeliveryDateSection({
    required this.urgency,
    required this.requestedDeliveryDate,
    required this.onPickDate,
    required this.onClearDate,
  });

  final PurchaseOrderUrgency urgency;
  final DateTime? requestedDeliveryDate;
  final VoidCallback onPickDate;
  final VoidCallback? onClearDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDate = requestedDeliveryDate != null;
    final helperText = hasDate
        ? 'Fecha requerida: ${requestedDeliveryDate!.toShortDate()}'
        : 'Sin fecha capturada. Define para cuando se requiere lo solicitado.';
    final urgencyHelpText = urgency == PurchaseOrderUrgency.urgente
        ? 'Para urgencia solo se permiten los próximos '
            '$urgentRequestedDeliveryBusinessDays días hábiles después de hoy.'
        : 'Con urgencia normal puedes elegir cualquier fecha.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fecha requerida por el solicitante',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(helperText, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(urgencyHelpText, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onPickDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  requestedDeliveryDate == null
                      ? 'Definir fecha'
                      : 'Cambiar fecha',
                ),
              ),
              if (onClearDate != null)
                TextButton(
                  onPressed: onClearDate,
                  child: const Text('Limpiar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

DateTime _resolveUrgentInitialDate(
  DateTime? currentValue,
  List<DateTime> urgentDates,
) {
  final normalizedCurrent = currentValue == null ? null : normalizeCalendarDate(currentValue);
  if (normalizedCurrent != null &&
      urgentDates.any((date) => isSameCalendarDate(date, normalizedCurrent))) {
    return normalizedCurrent;
  }
  return urgentDates.first;
}

class _LastAttemptWarning extends ConsumerWidget {
  const _LastAttemptWarning({required this.draftId});

  final String? draftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = _lastReturnContact(ref, draftId);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _lastAttemptMessage(contact),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _OrderItemsSection extends ConsumerWidget {
  const _OrderItemsSection({
    required this.items,
    required this.unitOptions,
    required this.onAddClient,
    required this.onChanged,
    required this.onRemove,
  });

  final List<OrderItemDraft> items;
  final List<String> unitOptions;
  final Future<String?> Function(String query)? onAddClient;
  final void Function(int index, OrderItemDraft updated) onChanged;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientOptions = ref.watch(userClientNamesProvider);
    return Column(
      children: [
        for (final entry in items.asMap().entries)
          _OrderItemCard(
            index: entry.key,
            draft: entry.value,
            clientOptions: clientOptions,
            unitOptions: unitOptions,
            onAddClient: onAddClient,
            onChanged: (updated) => onChanged(entry.key, updated),
            onRemove: onRemove == null ? null : () => onRemove!(entry.key),
          ),
      ],
    );
  }
}

class _OrderItemCard extends StatefulWidget {
  const _OrderItemCard({
    required this.index,
    required this.draft,
    required this.clientOptions,
    required this.unitOptions,
    this.onAddClient,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final OrderItemDraft draft;
  final List<String> clientOptions;
  final List<String> unitOptions;
  final Future<String?> Function(String query)? onAddClient;
  final ValueChanged<OrderItemDraft> onChanged;
  final VoidCallback? onRemove;

  @override
  State<_OrderItemCard> createState() => _OrderItemCardState();
}

class _OrderItemCardState extends State<_OrderItemCard> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _piecesController;
  late final TextEditingController _partNumberController;
  late final TextEditingController _customerController;
  late final TextEditingController _unitController;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.draft.description);
    _piecesController = TextEditingController(text: widget.draft.pieces.toString());
    _partNumberController = TextEditingController(text: widget.draft.partNumber);
    _customerController = TextEditingController(text: widget.draft.customer ?? '');
    _unitController = TextEditingController(text: widget.draft.unit);
  }

  @override
  void didUpdateWidget(covariant _OrderItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.draft.description != _descriptionController.text) {
      _descriptionController.text = widget.draft.description;
    }

    final piecesValue = widget.draft.pieces.toString();
    if (piecesValue != _piecesController.text) {
      _piecesController.text = piecesValue;
    }

    if (widget.draft.partNumber != _partNumberController.text) {
      _partNumberController.text = widget.draft.partNumber;
    }

    final customerValue = widget.draft.customer ?? '';
    if (customerValue != _customerController.text) {
      _customerController.text = customerValue;
    }

    if (widget.draft.unit != _unitController.text) {
      _unitController.text = widget.draft.unit;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _piecesController.dispose();
    _partNumberController.dispose();
    _customerController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  String _piecesLabel(String unit) {
    final normalized = unit.trim().toUpperCase();
    if (normalized == 'PZA' || normalized == 'PZ') return 'Piezas requeridas';
    if (normalized.isEmpty) return 'Cantidad requerida';
    return 'Cantidad requerida ($normalized)';
  }

  Future<void> _selectCustomer(OrderItemDraft draft) async {
    final selected = await showSearchableSelect(
      context: context,
      title: 'Selecciona cliente',
      options: widget.clientOptions,
      addLabel: 'Crear cliente',
      onAdd: widget.onAddClient,
    );
    if (selected == null) return;

    _customerController.text = selected;
    widget.onChanged(draft.copyWith(customer: selected));
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final effectiveUnit = _unitController.text.trim();
    final hasCustomer = _customerController.text.trim().isNotEmpty;
    final canPickCustomer = widget.clientOptions.isNotEmpty || widget.onAddClient != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Artículo ${draft.line}', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (widget.onRemove != null)
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline),
                    color: Theme.of(context).colorScheme.error,
                  ),
              ],
            ),

            TextFormField(
              key: ValueKey('desc-${widget.index}'),
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Descripción del producto'),
              minLines: 2,
              maxLines: 3,
              onChanged: (value) => widget.onChanged(draft.copyWith(description: value)),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Requerido' : null,
            ),

            if ((draft.reviewComment ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Motivo de rechazo',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(draft.reviewComment!.trim()),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('customer-${widget.index}'),
              controller: _customerController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Cliente (opcional)',
                suffixIcon: canPickCustomer
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasCustomer)
                            IconButton(
                              tooltip: 'Limpiar',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _customerController.clear();
                                widget.onChanged(draft.copyWith(customer: null));
                              },
                            ),
                          IconButton(
                            tooltip: 'Buscar',
                            icon: const Icon(Icons.search),
                            onPressed: () => _selectCustomer(draft),
                          ),
                        ],
                      )
                    : null,
              ),
              onTap: canPickCustomer ? () => _selectCustomer(draft) : null,
            ),

            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('unit-${widget.index}'),
              controller: _unitController,
              decoration: InputDecoration(
                labelText: 'Unidad de medida',
                suffixIcon: widget.unitOptions.isNotEmpty
                    ? IconButton(
                        tooltip: 'Buscar',
                        icon: const Icon(Icons.search),
                        onPressed: () async {
                          final selected = await showSearchableSelect(
                            context: context,
                            title: 'Selecciona unidad',
                            options: widget.unitOptions,
                          );
                          if (selected == null) return;
                          _unitController.text = selected;
                          widget.onChanged(draft.copyWith(unit: selected));
                        },
                      )
                    : null,
              ),
              onChanged: (value) => widget.onChanged(draft.copyWith(unit: value.trim())),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Requerido' : null,
            ),

            TextFormField(
              key: ValueKey('pieces-${widget.index}'),
              controller: _piecesController,
              decoration: InputDecoration(labelText: _piecesLabel(effectiveUnit)),
              keyboardType: TextInputType.number,
              onChanged: (value) => widget.onChanged(
                draft.copyWith(pieces: int.tryParse(value) ?? draft.pieces),
              ),
              validator: (value) {
                final raw = value?.trim() ?? '';
                final parsed = int.tryParse(raw);
                if (parsed == null || parsed <= 0) return 'Debe ser mayor a 0';
                return null;
              },
            ),

            TextFormField(
              key: ValueKey('part-${widget.index}'),
              controller: _partNumberController,
              decoration: const InputDecoration(labelText: 'No. de parte (opcional)'),
              onChanged: (value) => widget.onChanged(draft.copyWith(partNumber: value)),
            ),
          ],
        ),
      ),
    );
  }
}

String _lastAttemptMessage(String? contactArea) {
  final area = contactArea?.trim().isNotEmpty == true ? contactArea!.trim() : 'Compras';
  return 'Advertencia: este es el último intento para enviar la requisición. '
      'Antes de enviarla, contacta a $area.';
}

String _lastReturnContact(WidgetRef ref, String? draftId) {
  if (draftId == null || draftId.trim().isEmpty) return 'Compras';

  final eventsAsync = ref.watch(orderEventsProvider(draftId));
  return eventsAsync.maybeWhen(
    data: (events) {
      PurchaseOrderEvent? lastReturn;
      for (final event in events) {
        if (event.type == 'return') {
          lastReturn = event;
        }
      }
      return _contactLabel(lastReturn?.byRole);
    },
    orElse: () => 'Compras',
  );
}

String _contactLabel(String? rawRole) {
  final normalized = normalizeAreaLabel(rawRole?.trim() ?? '');
  if (normalized.isEmpty) return 'Compras';
  if (isDireccionGeneralLabel(normalized)) return 'Dirección General';
  if (isComprasLabel(normalized)) return 'Compras';
  return normalized;
}

const _csvHeaderAliases = <String, String>{
  // Línea
  'linea': 'line',
  'line': 'line',

  // No. parte
  'noparte': 'partNumber',
  'nparte': 'partNumber',
  'numeroparte': 'partNumber',
  'partnumber': 'partNumber',

  // Descripción
  'descripcion': 'description',
  'description': 'description',

  // Cantidad
  'cantidad': 'quantity',
  'quantity': 'quantity',

  // Unidad
  'unidad': 'unit',
  'unit': 'unit',

  // Proveedor
  'proveedor': 'supplier',
  'supplier': 'supplier',

  // Cliente
  'cliente': 'customer',
  'customer': 'customer',

  // Fecha estimada
  'fechaestimada': 'estimatedDate',
  'estimateddate': 'estimatedDate',
};

List<OrderItemDraft> _parseCsvItems(String content) {
  final delimiter = _guessDelimiter(content);
  final converter = CsvToListConverter(
    fieldDelimiter: delimiter,
    shouldParseNumbers: false,
    eol: '\n',
  );

  final rows = converter.convert(content);
  if (rows.isEmpty) {
    throw const FormatException('El CSV está vacío.');
  }

  final rawHeader = rows.first.map((cell) => cell.toString().trim()).toList();
  final headerMap = <String, int>{};

  for (var i = 0; i < rawHeader.length; i++) {
    final normalized = _normalizeHeader(rawHeader[i]);
    final canonical = _csvHeaderAliases[normalized];
    if (canonical != null) {
      headerMap[canonical] = i;
    }
  }

  if (!headerMap.containsKey('description')) {
    throw const FormatException('Falta la columna "descripción" en el CSV.');
  }
  if (!headerMap.containsKey('quantity')) {
    throw const FormatException('Falta la columna "cantidad" en el CSV.');
  }

  final items = <OrderItemDraft>[];

  for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (_isRowEmpty(row)) continue;

    final description = _cleanText(_cellValue(row, headerMap, 'description'));
    if (description.isEmpty) continue;

    final unit = _cleanText(_cellValue(row, headerMap, 'unit')).toUpperCase();
    final partNumber = _cleanText(_cellValue(row, headerMap, 'partNumber'));
    final customer = _cleanText(_cellValue(row, headerMap, 'customer'));
    final supplier = _cleanText(_cellValue(row, headerMap, 'supplier'));

    final pieces = _parseQuantity(
          _cellValue(row, headerMap, 'quantity'),
        ) ??
        1;

    final estimatedDate = _parseDate(_cellValue(row, headerMap, 'estimatedDate'));

    items.add(
      OrderItemDraft(
        line: items.length + 1,
        pieces: pieces,
        partNumber: partNumber,
        description: description,
        quantity: pieces,
        unit: unit.isEmpty ? 'PZA' : unit,
        customer: customer.isEmpty ? null : customer,
        supplier: supplier.isEmpty ? null : supplier,
        estimatedDate: estimatedDate,
      ),
    );
  }

  if (items.isEmpty) {
    throw const FormatException('El CSV no contiene artículos válidos.');
  }

  final sharedDate = _earliestDate(items);
  if (sharedDate != null) {
    return [for (final item in items) item.copyWith(estimatedDate: sharedDate)];
  }

  return items;
}

String _cellValue(List<dynamic> row, Map<String, int> headerMap, String key) {
  final index = headerMap[key];
  if (index == null || index < 0 || index >= row.length) return '';
  return row[index]?.toString() ?? '';
}

String _guessDelimiter(String content) {
  final lines = content.split('\n');
  final firstLine = lines.firstWhere(
    (line) => line.trim().isNotEmpty,
    orElse: () => content,
  );
  final commaCount = ','.allMatches(firstLine).length;
  final semicolonCount = ';'.allMatches(firstLine).length;
  return semicolonCount > commaCount ? ';' : ',';
}

bool _isRowEmpty(List<dynamic> row) {
  for (final cell in row) {
    if (cell != null && cell.toString().trim().isNotEmpty) return false;
  }
  return true;
}

String _cleanText(String value) => value.trim();

int? _parseQuantity(String quantityRaw) {
  final quantity = _parseInt(quantityRaw);
  if (quantity != null && quantity > 0) return quantity;

  return null;
}

int? _parseInt(String raw) {
  final cleaned = raw.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  final parsed = num.tryParse(cleaned);
  if (parsed == null) return null;
  return parsed.toInt();
}

DateTime? _parseDate(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // ISO (yyyy-MM-dd / yyyy-MM-ddTHH:mm:ss)
  final isoParsed = DateTime.tryParse(trimmed);
  if (isoParsed != null) {
    return DateTime(isoParsed.year, isoParsed.month, isoParsed.day);
  }

  // dd/MM/yyyy
  final slashParts = trimmed.split('/');
  if (slashParts.length == 3) {
    final day = int.tryParse(slashParts[0]);
    final month = int.tryParse(slashParts[1]);
    final year = int.tryParse(slashParts[2]);
    if (day != null && month != null && year != null) {
      return DateTime(year, month, day);
    }
  }

  // yyyy-MM-dd (por si viene con espacios o variantes)
  final dashParts = trimmed.split('-');
  if (dashParts.length == 3) {
    final year = int.tryParse(dashParts[0]);
    final month = int.tryParse(dashParts[1]);
    final day = int.tryParse(dashParts[2]);
    if (day != null && month != null && year != null) {
      return DateTime(year, month, day);
    }
  }

  return null;
}

DateTime? _earliestDate(List<OrderItemDraft> items) {
  final dates = items.map((item) => item.estimatedDate).whereType<DateTime>().toList();
  if (dates.isEmpty) return null;
  dates.sort();
  return dates.first;
}

String _normalizeHeader(String raw) {
  var s = raw.trim().toLowerCase();

  // Corrige acentos normales
  s = s
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');

  // Solo letras y números
  return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

