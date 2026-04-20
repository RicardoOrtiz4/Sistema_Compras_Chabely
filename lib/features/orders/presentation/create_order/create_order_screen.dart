import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/access_control.dart';
import 'package:sistema_compras/core/business_calendar.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/searchable_select.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Requisición de compra'),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const AppSplash();
          if (controller.isLoadingDraft) return const AppSplash();
          final canAssignClients = canAssignClientsToOrderItems(user);
          final clientOptions = canAssignClients
              ? ref.watch(userClientNamesProvider)
              : const <String>[];

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
                _CreateOrderActions(
                  canAssignClients: canAssignClients,
                  onImportCsv: () => _importCsvItems(notifier),
                  onAddItem: () =>
                      ref.read(createOrderControllerProvider.notifier).addItem(),
                  onAssignClient: canAssignClients
                      ? () => _assignClientToItems(
                            notifier,
                            controller.items,
                            clientOptions,
                          )
                      : null,
                ),
                const SizedBox(height: 12),
                _OrderItemsSection(
                  items: controller.items,
                  unitOptions: _unitOptions,
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
                    onPressed: controller.isSubmitting
                        ? null
                        : () async {
                            final notifier = ref.read(
                              createOrderControllerProvider.notifier,
                            );
                            if (!(_formKey.currentState?.validate() ?? false)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Revisa los campos requeridos'),
                                ),
                              );
                              return;
                            }
                            final requestedDeliveryDateError =
                                notifier.requestedDeliveryDateError();
                            if (requestedDeliveryDateError != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(requestedDeliveryDateError),
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
                        : const Text('Revisar PDF'),
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
    final isUrgent = urgency == PurchaseOrderUrgency.urgente;
    final initialDate = isUrgent
        ? _resolveUrgentInitialDate(currentValue, normalizedNow)
        : _resolveNormalInitialDate(currentValue, normalizedNow);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: isUrgent
          ? normalizedNow
          : normalizedNow.add(
              const Duration(days: normalRequestedDeliveryLeadDays),
            ),
      lastDate: isUrgent
          ? normalizedNow.add(
              const Duration(days: urgentRequestedDeliveryWindowDays),
            )
          : DateTime(2100, 12, 31),
      selectableDayPredicate: (day) {
        final normalizedDay = normalizeCalendarDate(day);
        if (normalizedDay.isBefore(normalizedNow)) {
          return false;
        }
        if (!isUrgent) {
          return isAllowedNormalRequestedDeliveryDate(
            normalizedDay,
            today: normalizedNow,
          );
        }
        return isAllowedUrgentRequestedDeliveryDate(
          normalizedDay,
          today: normalizedNow,
        );
      },
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

  Future<void> _assignClientToItems(
    CreateOrderController notifier,
    List<OrderItemDraft> visibleItems,
    List<String> clientOptions,
  ) async {
    if (visibleItems.isEmpty) {
      _messenger?.showSnackBar(
        const SnackBar(content: Text('Agrega al menos un item.')),
      );
      return;
    }

    final result = await showDialog<_ClientAssignmentResult>(
      context: context,
      builder: (context) => _ClientAssignmentDialog(
        items: visibleItems,
        clientOptions: clientOptions,
        onAddClient: _addClientFromSearch,
      ),
    );
    if (result == null) return;

    final currentItems = ref.read(createOrderControllerProvider).items;
    for (final index in result.itemIndexes) {
      if (index < 0 || index >= currentItems.length) continue;
      notifier.updateItem(
        index,
        result.clearClient
            ? currentItems[index].copyWith(clearCustomer: true)
            : currentItems[index].copyWith(customer: result.clientName),
      );
    }
    _messenger?.showSnackBar(
      SnackBar(
        content: Text(
          result.clearClient
              ? 'Cliente removido de ${result.itemIndexes.length} item(s).'
              : 'Cliente asignado a ${result.itemIndexes.length} item(s).',
        ),
      ),
    );
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

    final actor = ref.read(currentUserProfileProvider).value;
    final uid = actor?.id;
    if (uid == null) return null;

    final repo = ref.read(partnerRepositoryProvider);
    await repo.createPartner(
      uid: uid,
      type: PartnerType.client,
      name: name,
      actor: actor,
    );
    ref.invalidate(userClientsProvider);
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

class _CreateOrderActions extends StatelessWidget {
  const _CreateOrderActions({
    required this.canAssignClients,
    required this.onImportCsv,
    required this.onAddItem,
    required this.onAssignClient,
  });

  final bool canAssignClients;
  final VoidCallback onImportCsv;
  final VoidCallback onAddItem;
  final VoidCallback? onAssignClient;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      OutlinedButton.icon(
        onPressed: onImportCsv,
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Importar CSV'),
      ),
      OutlinedButton.icon(
        onPressed: onAddItem,
        icon: const Icon(Icons.add),
        label: const Text('Agregar item'),
      ),
      if (canAssignClients)
        OutlinedButton.icon(
          onPressed: onAssignClient,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Asignar cliente'),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                buttons[i],
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: buttons[i]),
            ],
          ],
        );
      },
    );
  }
}

class _ClientAssignmentResult {
  const _ClientAssignmentResult({
    required this.clientName,
    required this.itemIndexes,
    this.clearClient = false,
  });

  final String clientName;
  final Set<int> itemIndexes;
  final bool clearClient;
}

class _ClientAssignmentDialog extends StatefulWidget {
  const _ClientAssignmentDialog({
    required this.items,
    required this.clientOptions,
    required this.onAddClient,
  });

  final List<OrderItemDraft> items;
  final List<String> clientOptions;
  final Future<String?> Function(String query) onAddClient;

  @override
  State<_ClientAssignmentDialog> createState() => _ClientAssignmentDialogState();
}

class _ClientAssignmentDialogState extends State<_ClientAssignmentDialog> {
  final Set<int> _selected = <int>{};
  String? _clientName;

  bool get _allSelected =>
      widget.items.isNotEmpty && _selected.length == widget.items.length;

  Future<void> _pickClient() async {
    final selected = await showSearchableSelect(
      context: context,
      title: 'Selecciona cliente',
      options: widget.clientOptions,
      addLabel: 'Crear cliente',
      onAdd: widget.onAddClient,
    );
    if (selected == null) return;
    setState(() => _clientName = selected.trim());
  }

  void _toggleAll(bool selected) {
    setState(() {
      _selected.clear();
      if (selected) {
        for (var i = 0; i < widget.items.length; i++) {
          _selected.add(i);
        }
      }
    });
  }

  void _toggleItem(int index, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
    });
  }

  void _apply() {
    final clientName = _clientName?.trim() ?? '';
    if (clientName.isEmpty || _selected.isEmpty) return;
    Navigator.pop(
      context,
      _ClientAssignmentResult(
        clientName: clientName,
        itemIndexes: Set<int>.from(_selected),
      ),
    );
  }

  void _clearAssignedClient() {
    if (_selected.isEmpty) return;
    Navigator.pop(
      context,
      _ClientAssignmentResult(
        clientName: '',
        itemIndexes: Set<int>.from(_selected),
        clearClient: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canApply = (_clientName?.trim().isNotEmpty ?? false) && _selected.isNotEmpty;

    return AlertDialog(
      title: const Text('Asignar cliente'),
      content: SizedBox(
        width: 640,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickClient,
                      icon: const Icon(Icons.person_search_outlined),
                      label: Text(
                        (_clientName?.trim().isNotEmpty ?? false)
                            ? _clientName!.trim()
                            : 'Seleccionar cliente',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Quitar cliente',
                    onPressed: _selected.isEmpty ? null : _clearAssignedClient,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: _allSelected,
                    onChanged: (value) => _toggleAll(value ?? false),
                  ),
                  const Text('Seleccionar todos'),
                  const Spacer(),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: const Text('Limpiar'),
                  ),
                ],
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    final customer = (item.customer ?? '').trim();
                    final details = <String>[
                      if (item.partNumber.trim().isNotEmpty)
                        'No. parte: ${item.partNumber}',
                      'Cantidad: ${item.pieces} ${item.unit}',
                      if (customer.isNotEmpty) 'Cliente actual: $customer',
                    ];

                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _selected.contains(index),
                      onChanged: (value) => _toggleItem(index, value ?? false),
                      title: Text(
                        'Item ${item.line}: ${item.description}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        details.join(' | '),
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: canApply ? _apply : null,
          child: const Text('Aplicar'),
        ),
      ],
    );
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
        ? 'Para urgencia solo se permite elegir entre hoy y '
            '$urgentRequestedDeliveryWindowDays dias mas.'
        : 'Con urgencia normal solo puedes elegir desde '
            '$normalRequestedDeliveryLeadDays dias despues de hoy, en dia habil.';

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

DateTime _resolveNormalInitialDate(
  DateTime? currentValue,
  DateTime today,
) {
  final normalizedCurrent = currentValue == null ? null : normalizeCalendarDate(currentValue);
  if (normalizedCurrent != null &&
      isAllowedNormalRequestedDeliveryDate(normalizedCurrent, today: today)) {
    return normalizedCurrent;
  }
  return firstAllowedNormalRequestedDeliveryDate(today: today);
}

DateTime _resolveUrgentInitialDate(
  DateTime? currentValue,
  DateTime today,
) {
  final normalizedCurrent = currentValue == null ? null : normalizeCalendarDate(currentValue);
  if (normalizedCurrent != null &&
      isAllowedUrgentRequestedDeliveryDate(normalizedCurrent, today: today)) {
    return normalizedCurrent;
  }
  return today;
}

class _OrderItemsSection extends StatelessWidget {
  const _OrderItemsSection({
    required this.items,
    required this.unitOptions,
    required this.onChanged,
    required this.onRemove,
  });

  final List<OrderItemDraft> items;
  final List<String> unitOptions;
  final void Function(int index, OrderItemDraft updated) onChanged;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final entry in items.asMap().entries)
          _OrderItemCard(
            index: entry.key,
            draft: entry.value,
            unitOptions: unitOptions,
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
    required this.unitOptions,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final OrderItemDraft draft;
  final List<String> unitOptions;
  final ValueChanged<OrderItemDraft> onChanged;
  final VoidCallback? onRemove;

  @override
  State<_OrderItemCard> createState() => _OrderItemCardState();
}

class _OrderItemCardState extends State<_OrderItemCard> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _piecesController;
  late final TextEditingController _partNumberController;
  late final TextEditingController _unitController;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.draft.description);
    _piecesController = TextEditingController(text: widget.draft.pieces.toString());
    _partNumberController = TextEditingController(text: widget.draft.partNumber);
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

    if (widget.draft.unit != _unitController.text) {
      _unitController.text = widget.draft.unit;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _piecesController.dispose();
    _partNumberController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  String _piecesLabel(String unit) {
    final normalized = unit.trim().toUpperCase();
    if (normalized == 'PZA' || normalized == 'PZ') return 'Piezas requeridas';
    if (normalized.isEmpty) return 'Cantidad requerida';
    return 'Cantidad requerida ($normalized)';
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final effectiveUnit = _unitController.text.trim();
    final customer = (draft.customer ?? '').trim();

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
            if (customer.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cliente: $customer',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],

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
    final supplier = _cleanText(_cellValue(row, headerMap, 'supplier'));

    final pieces = _parseQuantity(
          _cellValue(row, headerMap, 'quantity'),
        ) ??
        1;

    items.add(
      OrderItemDraft(
        line: items.length + 1,
        pieces: pieces,
        partNumber: partNumber,
        description: description,
        quantity: pieces,
        unit: unit.isEmpty ? 'PZA' : unit,
        supplier: supplier.isEmpty ? null : supplier,
      ),
    );
  }

  if (items.isEmpty) {
    throw const FormatException('El CSV no contiene artículos válidos.');
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

