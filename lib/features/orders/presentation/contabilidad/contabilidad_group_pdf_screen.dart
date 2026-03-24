import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/presentation/contabilidad/contabilidad_group_support.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_inline_view.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_inline_view.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class ContabilidadGroupPdfScreen extends ConsumerStatefulWidget {
  const ContabilidadGroupPdfScreen({
    required this.quoteId,
    super.key,
  });

  final String quoteId;

  @override
  ConsumerState<ContabilidadGroupPdfScreen> createState() =>
      _ContabilidadGroupPdfScreenState();
}

class _ContabilidadGroupPdfScreenState
    extends ConsumerState<ContabilidadGroupPdfScreen> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final quoteAsync = ref.watch(supplierQuoteByIdProvider(widget.quoteId));
    final ordersAsync = ref.watch(operationalOrdersProvider);
    final allQuotesAsync = ref.watch(supplierQuotesProvider);
    final actor = ref.watch(currentUserProfileProvider).value;
    final branding = ref.watch(currentBrandingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ver PDF'),
      ),
      body: quoteAsync.when(
        data: (quote) => ordersAsync.when(
          data: (orders) => allQuotesAsync.when(
            data: (_) {
              if (quote == null) {
                return const Center(child: Text('Agrupacion no encontrada.'));
              }
              final group = buildContabilidadGroup(quote, orders);
              if (group == null) {
                return const Center(
                  child: Text('Esta agrupacion ya no tiene ordenes pendientes.'),
                );
              }
              final pdfData = buildContabilidadQuotePdfData(
                quote: quote,
                allOrders: orders,
                branding: branding,
                actor: actor,
              );
              final totalItems = group.orders.fold<int>(
                0,
                (total, order) => total + order.items.length,
              );
              final internalOrdersCount = group.orders.fold<int>(
                0,
                (total, order) =>
                    total +
                    order.items
                        .where(
                          (item) => (item.internalOrder ?? '').trim().isNotEmpty,
                        )
                        .length,
              );
              final missingInternalOrders = group.orders.any(
                (order) => !hasAllInternalOrders(order),
              );
              return Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SupplierQuotePdfInlineView(data: pdfData),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '$internalOrdersCount/$totalItems OC internas capturadas.',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            missingInternalOrders
                                ? 'Falta al menos una OC interna para concluir.'
                                : 'Todas las OC internas ya fueron capturadas.',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${quote.facturaLinks.length} link(s) de factura y '
                            '${quote.paymentLinks.length} link(s) de pago registrados.',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => _editInternalOrders(group.orders),
                            icon: const Icon(Icons.confirmation_number_outlined),
                            label: const Text('Agregar OC interna'),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : () => _finalizeGroup(
                                      quoteId: quote.id,
                                      initialOrders: group.orders,
                                    ),
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: const Text('Finalizar orden'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const AppSplash(),
            error: (error, stack) => Center(
              child: Text(
                reportError(
                  error,
                  stack,
                  context: 'ContabilidadGroupPdfScreen.allQuotes',
                ),
              ),
            ),
          ),
          loading: () => const AppSplash(),
          error: (error, stack) => Center(
            child: Text(
              reportError(
                error,
                stack,
                context: 'ContabilidadGroupPdfScreen.orders',
              ),
            ),
          ),
        ),
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            reportError(
              error,
              stack,
              context: 'ContabilidadGroupPdfScreen.quote',
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _editInternalOrders(List<PurchaseOrder> orders) async {
    final missingOrders = orders
        .where((order) => !hasAllInternalOrders(order))
        .toList(growable: false);
    if (missingOrders.isEmpty) return true;
    final branding = ref.read(currentBrandingProvider);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _ContabilidadInternalOrdersFlowScreen(
          orders: missingOrders,
          branding: branding,
        ),
      ),
    );
    return saved == true;
  }

  Future<void> _finalizeGroup({
    required String quoteId,
    required List<PurchaseOrder> initialOrders,
  }) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }

    final quote = ref.read(supplierQuoteByIdProvider(quoteId)).valueOrNull;
    if (quote == null) {
      _showMessage('La agrupacion ya no esta disponible.');
      return;
    }
    if (quote.facturaLinks.isEmpty || quote.paymentLinks.isEmpty) {
      _showMessage(
        'Agrega al menos un link de factura y un link de pago antes de finalizar.',
      );
      return;
    }

    final repo = ref.read(purchaseOrderRepositoryProvider);
    final refreshedOrders = <PurchaseOrder>[];
    for (final order in initialOrders) {
      final refreshed = await repo.fetchOrderById(order.id);
      if (refreshed != null) {
        refreshedOrders.add(refreshed);
      }
    }

    final blockedOrders = refreshedOrders
        .where((order) => !canFinalizeOrder(order))
        .map((order) => order.id)
        .toList(growable: false);
    if (blockedOrders.isNotEmpty) {
      _showMessage(
        'No se puede finalizar aun. Faltan items por llegar a Contabilidad en: '
        '${blockedOrders.join(', ')}.',
      );
      return;
    }

    final missingInternalOrders = refreshedOrders
        .where((order) => !hasAllInternalOrders(order))
        .toList(growable: false);
    if (missingInternalOrders.isNotEmpty) {
      final savedAll = await _editInternalOrders(refreshedOrders);
      if (!savedAll) return;
    }

    final finalizedOrders = <PurchaseOrder>[];
    for (final order in refreshedOrders) {
      final latest = await repo.fetchOrderById(order.id);
      if (latest == null) continue;
      if (!hasAllInternalOrders(latest)) {
        _showMessage(
          'Falta capturar la OC interna de todos los articulos antes de finalizar.',
        );
        return;
      }
      finalizedOrders.add(latest);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar orden'),
        content: Text(
          'Se finalizaran ${finalizedOrders.length} orden(es) de esta agrupacion '
          'y el solicitante podra verlas en Ordenes en proceso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final List<SupplierQuote> quotes =
          ref.read(supplierQuotesProvider).valueOrNull ??
          const <SupplierQuote>[];
      for (final order in finalizedOrders) {
        final facturaLinks = collectOrderFacturaLinks(order.id, quotes);
        if (facturaLinks.isEmpty) {
          throw StateError(
            'La orden ${order.id} aun no tiene links de factura disponibles.',
          );
        }
        await repo.completeFromContabilidad(
          order: order,
          facturaUrls: facturaLinks,
          actor: actor,
          items: order.items,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${finalizedOrders.length} orden(es) con llegada registrada y notificadas correctamente.',
          ),
        ),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        guardedGo(context, '/orders/contabilidad');
      }
    } catch (error, stack) {
      _showMessage(
        reportError(
          error,
          stack,
          context: 'ContabilidadGroupPdfScreen.finalize',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ContabilidadInternalOrdersFlowScreen extends ConsumerStatefulWidget {
  const _ContabilidadInternalOrdersFlowScreen({
    required this.orders,
    required this.branding,
  });

  final List<PurchaseOrder> orders;
  final CompanyBranding branding;

  @override
  ConsumerState<_ContabilidadInternalOrdersFlowScreen> createState() =>
      _ContabilidadInternalOrdersFlowScreenState();
}

class _ContabilidadInternalOrdersFlowScreenState
    extends ConsumerState<_ContabilidadInternalOrdersFlowScreen> {
  final Map<int, TextEditingController> _controllers =
      <int, TextEditingController>{};
  final Map<int, String> _appliedValues = <int, String>{};
  int _currentIndex = 0;
  bool _isSaving = false;
  bool _panelVisible = false;

  PurchaseOrder get _currentOrder => widget.orders[_currentIndex];

  List<PurchaseOrderItem> get _missingItems => _currentOrder.items
      .where((item) => (item.internalOrder ?? '').trim().isEmpty)
      .toList(growable: false);

  bool get _hasMissingItems => _missingItems.isNotEmpty;

  bool get _allFieldsCompleted => _missingItems.every(
        (item) => (_controllers[item.line]?.text.trim() ?? '').isNotEmpty,
      );

  bool get _previewIsCurrent =>
      mapEquals(_appliedValues, _currentDraftInternalOrders);

  Map<int, String> get _currentDraftInternalOrders => <int, String>{
        for (final item in _missingItems)
          item.line: (_controllers[item.line]?.text.trim() ?? ''),
      };

  @override
  void initState() {
    super.initState();
    _loadOrder();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _panelVisible = true);
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _loadOrder() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _appliedValues.clear();
    for (final item in _missingItems) {
      final initial = (item.internalOrder ?? '').trim();
      _controllers[item.line] = TextEditingController(text: initial);
      if (initial.isNotEmpty) {
        _appliedValues[item.line] = initial;
      }
    }
  }

  OrderPdfData _buildPdfPreviewData() {
    final draftItems = _currentOrder.items.map((item) {
      final applied = _appliedValues[item.line];
      if (applied == null) return OrderItemDraft.fromModel(item);
      return OrderItemDraft.fromModel(item).copyWith(internalOrder: applied);
    }).toList(growable: false);
    return buildPdfDataFromOrder(
      _currentOrder,
      branding: widget.branding,
      items: draftItems,
      cacheSalt:
          'contabilidad-oc-${_currentOrder.id}-${_appliedValues.values.join('|')}',
    );
  }

  void _applyChangesToPreview() {
    if (!_allFieldsCompleted) {
      _showMessage('Captura todas las OC internas faltantes antes de actualizar el PDF.');
      return;
    }
    setState(() {
      _appliedValues
        ..clear()
        ..addAll(_currentDraftInternalOrders);
    });
  }

  Future<void> _saveCurrentOrderAndContinue() async {
    if (!_allFieldsCompleted) {
      _showMessage('Falta capturar la OC interna de todos los articulos.');
      return;
    }
    if (!_previewIsCurrent) {
      _showMessage('Actualiza el PDF para revisar las OCs antes de continuar.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(purchaseOrderRepositoryProvider).saveInternalOrdersForItems(
            order: _currentOrder,
            internalOrdersByLine: _currentDraftInternalOrders,
          );
      if (!mounted) return;
      final isLastOrder = _currentIndex >= widget.orders.length - 1;
      if (isLastOrder) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _currentIndex += 1;
      });
      _loadOrder();
    } catch (error, stack) {
      _showMessage(
        reportError(
          error,
          stack,
          context: 'ContabilidadInternalOrdersFlowScreen.save',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentStep = _currentIndex + 1;
    final totalSteps = widget.orders.length;
    final pdfData = _buildPdfPreviewData();

    return Scaffold(
      appBar: AppBar(
        title: Text('Agregar OC interna $currentStep/$totalSteps'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wideLayout = constraints.maxWidth >= 1080;
          final pdfView = Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: OrderPdfInlineView(
                  data: pdfData,
                  skipCache: true,
                ),
              ),
            ),
          );
          final panel = _ContabilidadInternalOrdersPanel(
            order: _currentOrder,
            currentStep: currentStep,
            totalSteps: totalSteps,
            missingItems: _missingItems,
            controllers: _controllers,
            isSaving: _isSaving,
            canApplyPreview: _hasMissingItems && _allFieldsCompleted,
            previewIsCurrent: _previewIsCurrent,
            onFieldChanged: () => setState(() {}),
            onApplyPreview: _applyChangesToPreview,
            onSaveAndContinue: _saveCurrentOrderAndContinue,
          );

          if (wideLayout) {
            return Row(
              children: [
                Expanded(child: pdfView),
                AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  offset: _panelVisible ? Offset.zero : const Offset(1, 0),
                  child: SizedBox(
                    width: 380,
                    child: panel,
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              Expanded(child: pdfView),
              AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                offset: _panelVisible ? Offset.zero : const Offset(0, 1),
                child: SizedBox(
                  height: 320,
                  child: panel,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ContabilidadInternalOrdersPanel extends StatelessWidget {
  const _ContabilidadInternalOrdersPanel({
    required this.order,
    required this.currentStep,
    required this.totalSteps,
    required this.missingItems,
    required this.controllers,
    required this.isSaving,
    required this.canApplyPreview,
    required this.previewIsCurrent,
    required this.onFieldChanged,
    required this.onApplyPreview,
    required this.onSaveAndContinue,
  });

  final PurchaseOrder order;
  final int currentStep;
  final int totalSteps;
  final List<PurchaseOrderItem> missingItems;
  final Map<int, TextEditingController> controllers;
  final bool isSaving;
  final bool canApplyPreview;
  final bool previewIsCurrent;
  final VoidCallback onFieldChanged;
  final VoidCallback onApplyPreview;
  final VoidCallback onSaveAndContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      elevation: 8,
      child: SafeArea(
        left: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Orden ${order.id}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text('Paso $currentStep de $totalSteps'),
              const SizedBox(height: 6),
              Text(
                'Captura las OC internas faltantes sin salir del PDF.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (missingItems.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Esta orden ya no tiene articulos pendientes de OC interna.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: missingItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = missingItems[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Item ${item.line}',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(item.description),
                              const SizedBox(height: 4),
                              Text(
                                'Cantidad: ${item.quantity} ${item.unit}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: controllers[item.line],
                                decoration: const InputDecoration(
                                  labelText: 'OC interna',
                                  prefixIcon: Icon(
                                    Icons.confirmation_number_outlined,
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) => onFieldChanged(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                previewIsCurrent
                    ? 'El PDF ya refleja las OCs capturadas.'
                    : 'Actualiza el PDF antes de continuar para revisar las OCs.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: canApplyPreview ? onApplyPreview : null,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Actualizar PDF'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: isSaving ? null : onSaveAndContinue,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        currentStep >= totalSteps
                            ? Icons.check_circle_outline
                            : Icons.arrow_forward,
                      ),
                label: Text(
                  currentStep >= totalSteps
                      ? 'Aceptar y cerrar'
                      : 'Aceptar y siguiente',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
