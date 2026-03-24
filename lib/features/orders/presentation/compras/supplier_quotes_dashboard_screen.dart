import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_status_duration.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_builder.dart';
import 'package:sistema_compras/features/orders/presentation/preview/supplier_quote_pdf_view_screen.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';
import 'package:url_launcher/url_launcher.dart';

enum CotizacionesDashboardMode { compras, direccion }

class CotizacionesDashboardScreen extends ConsumerStatefulWidget {
  const CotizacionesDashboardScreen({
    required this.mode,
    this.embedded = false,
    this.onOpenOrder,
    super.key,
  });

  final CotizacionesDashboardMode mode;
  final bool embedded;
  final ValueChanged<String>? onOpenOrder;

  @override
  ConsumerState<CotizacionesDashboardScreen> createState() =>
      _CotizacionesDashboardScreenState();
}

class _CotizacionesDashboardScreenState
    extends ConsumerState<CotizacionesDashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _linksController = TextEditingController();
  final TextEditingController _comprasCommentController =
      TextEditingController();
  bool _isBusy = false;
  String? _selectedSupplier;
  String? _scheduledPdfCacheKey;
  String _searchQuery = '';
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  DateTimeRange? _createdDateRangeFilter;

  bool get _isDireccion => widget.mode == CotizacionesDashboardMode.direccion;

  @override
  void dispose() {
    _searchController.dispose();
    _linksController.dispose();
    _comprasCommentController.dispose();
    super.dispose();
  }

  void _updateSearch(String value) {
    setState(() => _searchQuery = value);
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _setUrgencyFilter(OrderUrgencyFilter filter) {
    setState(() => _urgencyFilter = filter);
  }

  Future<void> _pickCreatedDateFilter() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      currentDate: now,
      initialDateRange: _createdDateRangeFilter,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _createdDateRangeFilter = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day),
      );
    });
  }

  void _clearCreatedDateFilter() {
    if (_createdDateRangeFilter == null) return;
    setState(() => _createdDateRangeFilter = null);
  }

  @override
  Widget build(BuildContext context) {
    final completedOrdersAsync = ref.watch(dataCompleteOrdersProvider);
    final operationalOrdersAsync = ref.watch(operationalOrdersProvider);
    final quotesAsync = ref.watch(supplierQuotesProvider);
    final actor = ref.watch(currentUserProfileProvider).value;
    final branding = ref.watch(currentBrandingProvider);
    final titleOrders =
        operationalOrdersAsync.valueOrNull ?? const <PurchaseOrder>[];
    final titleQuotes = _isDireccion
        ? (quotesAsync.valueOrNull ?? const <SupplierQuote>[])
            .where(
              (quote) => quote.status == SupplierQuoteStatus.pendingDireccion,
            )
            .toList(growable: false)
        : const <SupplierQuote>[];
    final compactAppBar = useCompactOrderModuleAppBar(context);
    final body = completedOrdersAsync.when(
      data: (completedOrders) => operationalOrdersAsync.when(
        data: (allOrders) => quotesAsync.when(
          data: (quotes) {
            final editableQuotes = _isDireccion
                ? quotes
                    .where(
                      (quote) =>
                          quote.status == SupplierQuoteStatus.pendingDireccion,
                    )
                    .toList(growable: false)
                : quotes
                    .where(
                      (quote) =>
                          quote.status == SupplierQuoteStatus.draft ||
                          quote.status == SupplierQuoteStatus.rejected,
                      )
                    .toList(growable: false);
            final editableQuotesBySupplier = _quotesBySupplier(editableQuotes);
            final supplierOptions = _isDireccion
                ? const <String>[]
                : _supplierOptions(
                    completedOrders,
                    editableQuotesBySupplier,
                  );
            final supplierOptionsSet = supplierOptions.toSet();
            final activeEditableQuotes = _isDireccion
                ? editableQuotes
                : editableQuotes
                    .where(
                      (quote) => supplierOptionsSet.contains(quote.supplier.trim()),
                    )
                    .toList(growable: false);
            final activeEditableQuotesBySupplier = _isDireccion
                ? const <String, SupplierQuote>{}
                : _quotesBySupplier(activeEditableQuotes);

            if (!_isDireccion &&
                _selectedSupplier != null &&
                !supplierOptions.contains(_selectedSupplier)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _setSelectedSupplier(null, null);
              });
            }
            if (!_isDireccion &&
                _selectedSupplier == null &&
                supplierOptions.length == 1) {
              final singleSupplier = supplierOptions.first;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _selectedSupplier != null) return;
                _setSelectedSupplier(
                  singleSupplier,
                  activeEditableQuotesBySupplier[singleSupplier],
                );
              });
            }

            final selectedQuote = !_isDireccion && _selectedSupplier != null
                ? activeEditableQuotesBySupplier[_selectedSupplier!]
                : null;
            final visibleQuotes = _isDireccion
                ? editableQuotes
                    .where(
                      (quote) => _matchesDireccionQuoteFilters(
                        quote: quote,
                        allOrders: allOrders,
                        query: _searchQuery,
                        filter: _urgencyFilter,
                        range: _createdDateRangeFilter,
                      ),
                    )
                    .toList(growable: false)
                : activeEditableQuotes;
            final supplierItems = !_isDireccion && _selectedSupplier != null
                ? _collectSupplierItems(
                    orders: completedOrders,
                    supplier: _selectedSupplier!,
                    editableQuoteId: selectedQuote?.id,
                  )
                : const <_SupplierGroupedItem>[];
            final pendingDashboardOrders = _isDireccion
                ? const <_PendingDashboardOrder>[]
                : _buildPendingDashboardOrders(
                    allOrders: allOrders,
                    selectedSupplier: _selectedSupplier,
                    selectedQuoteId: selectedQuote?.id,
                  );
            final quoteSendStates = _buildQuoteSendStates(
              quotes: visibleQuotes,
              orders: allOrders,
            );
            final selectedLinks = _parseLinks(_linksController.text);
            _schedulePdfCache(
              _buildCacheCandidates(
                allOrders: allOrders,
                branding: branding,
                actor: actor,
                visibleQuotes: visibleQuotes,
                selectedSupplier: _selectedSupplier,
                selectedItems: supplierItems,
                selectedLinks: selectedLinks,
                selectedQuote: selectedQuote,
                selectedComprasComment: _comprasCommentController.text.trim(),
              ),
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_isDireccion) ...[
                  _DireccionQuotesFilters(
                    searchController: _searchController,
                    searchQuery: _searchQuery,
                    selectedRange: _createdDateRangeFilter,
                    onSearchChanged: _updateSearch,
                    onClearSearch: _clearSearch,
                    onPickDate: _pickCreatedDateFilter,
                    onClearDate: _clearCreatedDateFilter,
                  ),
                  const SizedBox(height: 16),
                ],
                if (!_isDireccion && supplierOptions.isNotEmpty) ...[
                  _SupplierWorkPanel(
                    supplierOptions: supplierOptions,
                    selectedSupplier: _selectedSupplier,
                    workingQuote: selectedQuote,
                    items: supplierItems,
                    quoteLinkCount: selectedLinks.length,
                    comprasCommentController: _comprasCommentController,
                    isBusy: _isBusy,
                    onSupplierChanged: (supplier) => _setSelectedSupplier(
                      supplier,
                      supplier == null
                          ? null
                          : activeEditableQuotesBySupplier[supplier],
                    ),
                    onViewOrderPdf: _openOrderPdf,
                    onManageLinks: _selectedSupplier == null
                        ? null
                        : _manageQuoteLinks,
                    onViewPdf: supplierItems.isEmpty
                        ? null
                        : () => _openSelectionPdf(
                              supplier: _selectedSupplier!,
                              items: supplierItems,
                              allOrders: allOrders,
                              branding: branding,
                              actor: actor,
                              quote: selectedQuote,
                            ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!_isDireccion &&
                    supplierOptions.isEmpty &&
                    visibleQuotes.isEmpty &&
                    pendingDashboardOrders.isEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No hay ordenes disponibles en este momento.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _QuotesPanel(
                  quotes: visibleQuotes,
                  allOrders: allOrders,
                  pendingOrders: pendingDashboardOrders,
                  quoteSendStates: quoteSendStates,
                  isDireccion: _isDireccion,
                  onOpenOrder: widget.onOpenOrder,
                  onViewOrderPdf: _openOrderPdf,
                  onViewPdf: (quote) => _openStoredQuotePdf(
                    quote: quote,
                    allOrders: allOrders,
                    branding: branding,
                    actor: actor,
                  ),
                  onCancel: _isDireccion ? null : _cancelQuote,
                  onApprove: _isDireccion ? _approveQuoteFromCard : null,
                  onReject: _isDireccion ? _rejectQuoteFromCard : null,
                ),
              ],
            );
          },
          loading: () => const AppSplash(),
          error: (error, stack) => _ErrorText(
            message: reportError(error, stack, context: 'SupplierQuotes.quotes'),
          ),
        ),
        loading: () => const AppSplash(),
        error: (error, stack) => _ErrorText(
          message: reportError(error, stack, context: 'SupplierQuotes.orders'),
        ),
      ),
      loading: () => const AppSplash(),
      error: (error, stack) => _ErrorText(
        message: reportError(
          error,
          stack,
          context: 'SupplierQuotes.completedOrders',
        ),
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: _isDireccion
            ? (compactAppBar
                ? const Text(paymentAuthorizationLabel)
                : OrderModuleAppBarTitle(
                    title: paymentAuthorizationLabel,
                    counts: _direccionQuoteCounts(
                      quotes: titleQuotes,
                      allOrders: titleOrders,
                    ),
                    filter: _urgencyFilter,
                    onSelected: _setUrgencyFilter,
                  ))
            : const Text('Mesa de compras'),
        bottom: !_isDireccion || !compactAppBar
            ? null
            : OrderModuleAppBarBottom(
                counts: _direccionQuoteCounts(
                  quotes: titleQuotes,
                  allOrders: titleOrders,
                ),
                filter: _urgencyFilter,
                onSelected: _setUrgencyFilter,
              ),
      ),
      body: body,
    );
  }

  void _setSelectedSupplier(String? supplier, SupplierQuote? quote) {
    setState(() {
      _selectedSupplier = supplier;
      _linksController.text = quote == null ? '' : quote.links.join('\n');
      _comprasCommentController.text = (quote?.comprasComment ?? '').trim();
    });
  }

  void _openOrderPdf(String orderId) {
    context.push('/orders/$orderId/pdf');
  }

  Future<void> _openSelectionPdf({
    required String supplier,
    required List<_SupplierGroupedItem> items,
    required List<PurchaseOrder> allOrders,
    required CompanyBranding branding,
    required AppUser? actor,
    required SupplierQuote? quote,
  }) async {
    final data = _buildPdfData(
      branding: branding,
      allOrders: allOrders,
      supplier: supplier,
      quoteId: _selectionPreviewQuoteId(supplier, quote),
      links: _parseLinks(_linksController.text),
      refs: _refsFromGroupedItems(items),
      comprasComment: _comprasCommentController.text.trim(),
      createdAt: quote?.createdAt,
      processedByName: actor?.name,
      processedByArea: actor?.areaDisplay,
    );
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SupplierQuotePdfViewScreen(
          data: data,
          primaryActionLabel: 'Enviar a autorizacion de pago',
          primaryActionEnabled: _parseLinks(_linksController.text).isNotEmpty,
          closeOnPrimaryAction: true,
          onPrimaryAction: () => _sendSelectionToDireccionFromPdf(
            supplier: supplier,
            items: items,
            quote: quote,
          ),
        ),
      ),
    );
  }

  Future<void> _openStoredQuotePdf({
    required SupplierQuote quote,
    required List<PurchaseOrder> allOrders,
    required CompanyBranding branding,
    required AppUser? actor,
  }) async {
    final data = _buildPdfData(
      branding: branding,
      allOrders: allOrders,
      supplier: quote.supplier,
      quoteId: quote.displayId,
      links: quote.links,
      refs: quote.items,
      comprasComment: quote.comprasComment,
      createdAt: quote.createdAt,
      processedByName: quote.processedByName ?? actor?.name,
      processedByArea: quote.processedByArea ?? actor?.areaDisplay,
      authorizedByName: quote.approvedByName,
      authorizedByArea: quote.approvedByArea,
    );
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SupplierQuotePdfViewScreen(
          data: data,
          primaryActionLabel: _isDireccion
              ? null
              : 'Enviar a autorizacion de pago',
          primaryActionEnabled: _isDireccion ? true : quote.links.isNotEmpty,
          closeOnPrimaryAction: !_isDireccion,
          onPrimaryAction: _isDireccion
              ? null
              : () => _sendStoredQuoteToDireccionFromPdf(quote),
        ),
      ),
    );
  }

  Future<bool> _sendSelectionToDireccionFromPdf({
    required String supplier,
    required List<_SupplierGroupedItem> items,
    required SupplierQuote? quote,
  }) async {
    return _sendSelectionToDireccion(
      supplier: supplier,
      items: items,
      quote: quote,
    );
  }

  Future<bool> _sendStoredQuoteToDireccionFromPdf(SupplierQuote quote) async {
    return _sendQuoteToDireccion(quote);
  }

  Future<bool> _sendSelectionToDireccion({
    required String supplier,
    required List<_SupplierGroupedItem> items,
    required SupplierQuote? quote,
  }) async {
    final links = _parseLinks(_linksController.text);
    if (links.isEmpty) {
      _showMessage(
        'Agrega al menos un link de compra antes de enviar a autorizacion de pago.',
      );
      return false;
    }
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return false;
    }
    setState(() => _isBusy = true);
    try {
      final storedQuote = await _upsertSelectedQuote(
        supplier: supplier,
        items: items,
        quote: quote,
      );
      await ref.read(purchaseOrderRepositoryProvider).sendSupplierQuoteToDireccion(
            quote: storedQuote,
            actor: actor,
          );
      if (!mounted) return false;
      setState(() {
        _selectedSupplier = null;
        _linksController.clear();
        _comprasCommentController.clear();
      });
      _showMessage('Compra enviada para autorizacion de pago.');
      return true;
    } catch (error, stack) {
      _showMessage(reportError(error, stack, context: 'SupplierQuotes.sendSelection'));
      return false;
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<SupplierQuote> _upsertSelectedQuote({
    required String supplier,
    required List<_SupplierGroupedItem> items,
    required SupplierQuote? quote,
  }) async {
    final repo = ref.read(purchaseOrderRepositoryProvider);
    final links = _parseLinks(_linksController.text);
    final comprasComment = _comprasCommentController.text.trim();
    final refs = _refsFromGroupedItems(items);
    final actor = ref.read(currentUserProfileProvider).value;

    if (quote == null) {
      return repo.createSupplierQuote(
        supplier: supplier,
        items: refs,
        links: links,
        comprasComment: comprasComment,
        actor: actor,
      );
    }

    await repo.updateSupplierQuoteDraft(
      quote: quote,
      items: refs,
      links: links,
      comprasComment: comprasComment,
      actor: actor,
    );
    return SupplierQuote(
      id: quote.id,
      folio: quote.folio,
      supplier: quote.supplier,
      items: refs,
      links: links,
      facturaLinks: quote.facturaLinks,
      paymentLinks: quote.paymentLinks,
      comprasComment: comprasComment,
      status: SupplierQuoteStatus.draft,
      createdAt: quote.createdAt,
      updatedAt: quote.updatedAt,
      version: quote.version + 1,
    );
  }

  Future<bool> _sendQuoteToDireccion(SupplierQuote quote) async {
    if (quote.links.isEmpty) {
      _showMessage(
        'Agrega al menos un link de compra antes de enviar a autorizacion de pago.',
      );
      return false;
    }
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return false;
    }
    try {
      await ref.read(purchaseOrderRepositoryProvider).sendSupplierQuoteToDireccion(
            quote: quote,
            actor: actor,
          );
      _showMessage('Compra enviada para autorizacion de pago.');
      return true;
    } catch (error, stack) {
      _showMessage(reportError(error, stack, context: 'SupplierQuotes.send'));
      return false;
    }
  }

  Future<void> _cancelQuote(SupplierQuote quote) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancelar compra ${quote.supplier}'),
        content: const Text(
          'La compra se eliminara y las ordenes relacionadas volveran a pendientes para editarse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await ref.read(purchaseOrderRepositoryProvider).cancelSupplierQuoteToCotizaciones(
            quote: quote,
            actor: actor,
          );
      if (!mounted) return;
      if (_selectedSupplier == quote.supplier) {
        setState(() {
          _selectedSupplier = null;
          _linksController.clear();
          _comprasCommentController.clear();
        });
      }
      _showMessage('Compra cancelada. Las ordenes volvieron a pendientes.');
    } catch (error, stack) {
      _showMessage(reportError(error, stack, context: 'SupplierQuotes.cancel'));
    }
  }

  Future<void> _approveQuoteFromCard(SupplierQuote quote) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }
    if (!_canAuthorizeQuote(actor)) {
      _showMessage('Solo Direccion General puede autorizar esta compra.');
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Autorizar compra'),
        content: Text(
          'Se autorizara la compra ${quote.displayId}. Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Autorizar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    setState(() => _isBusy = true);
    try {
      await ref.read(purchaseOrderRepositoryProvider).approveSupplierQuote(
            quote: quote,
            actor: actor,
          );
      _showMessage('Compra autorizada.');
    } catch (error, stack) {
      _showMessage(
        reportError(error, stack, context: 'SupplierQuotes.direccionApprove'),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _rejectQuoteFromCard(SupplierQuote quote) async {
    final actor = ref.read(currentUserProfileProvider).value;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }
    if (!_canAuthorizeQuote(actor)) {
      _showMessage('Solo Direccion General puede rechazar esta compra.');
      return;
    }

    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar compra'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Motivo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (accepted != true) {
      controller.dispose();
      return;
    }

    setState(() => _isBusy = true);
    try {
      await ref.read(purchaseOrderRepositoryProvider).rejectSupplierQuote(
            quote: quote,
            comment: controller.text,
            actor: actor,
          );
      _showMessage('Compra rechazada.');
    } catch (error, stack) {
      _showMessage(
        reportError(error, stack, context: 'SupplierQuotes.direccionReject'),
      );
    } finally {
      controller.dispose();
      if (mounted) setState(() => _isBusy = false);
    }
  }

  List<String> _parseLinks(String raw) {
    return raw
        .split(RegExp(r'[\r\n]+'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _openLink(String raw) async {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.isAbsolute) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _manageQuoteLinks() async {
    final result = await showDialog<_SupplierQuoteLinkEditorResult>(
      context: context,
      builder: (context) => _SupplierQuoteLinkEditorDialog(
        initialLinks: _parseLinks(_linksController.text),
        onOpenLink: _openLink,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _linksController.text = result.links.join('\n');
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _selectionPreviewQuoteId(String supplier, SupplierQuote? quote) {
    if (quote != null) return quote.displayId;
    final normalized = supplier.trim().replaceAll(RegExp(r'\s+'), '-');
    return 'COTIZACION-$normalized';
  }

  void _schedulePdfCache(List<SupplierQuotePdfData> dataList) {
    if (dataList.isEmpty) {
      _scheduledPdfCacheKey = null;
      return;
    }
    final cacheKey = dataList
        .map(supplierQuotePdfCacheKey)
        .join('||');
    if (_scheduledPdfCacheKey == cacheKey) return;
    _scheduledPdfCacheKey = cacheKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scheduledPdfCacheKey != cacheKey) return;
      cacheSupplierQuotePdfs(dataList, limit: dataList.length);
    });
  }
}

class _SupplierWorkPanel extends StatelessWidget {
  const _SupplierWorkPanel({
    required this.supplierOptions,
    required this.selectedSupplier,
    required this.workingQuote,
    required this.items,
    required this.quoteLinkCount,
    required this.comprasCommentController,
    required this.isBusy,
    required this.onSupplierChanged,
    required this.onViewOrderPdf,
    required this.onManageLinks,
    this.onViewPdf,
  });

  final List<String> supplierOptions;
  final String? selectedSupplier;
  final SupplierQuote? workingQuote;
  final List<_SupplierGroupedItem> items;
  final int quoteLinkCount;
  final TextEditingController comprasCommentController;
  final bool isBusy;
  final ValueChanged<String?> onSupplierChanged;
  final ValueChanged<String>? onViewOrderPdf;
  final VoidCallback? onManageLinks;
  final VoidCallback? onViewPdf;

  @override
  Widget build(BuildContext context) {
    if (supplierOptions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedSupplier,
              decoration: InputDecoration(
                labelText: 'Proveedor',
                suffixIcon: selectedSupplier == null
                    ? null
                    : IconButton(
                        onPressed: isBusy ? null : () => onSupplierChanged(null),
                        icon: const Icon(Icons.close),
                        tooltip: 'Limpiar proveedor',
                      ),
              ),
              items: [
                for (final supplier in supplierOptions)
                  DropdownMenuItem<String>(
                    value: supplier,
                    child: Text(supplier),
                  ),
              ],
              onChanged: isBusy ? null : onSupplierChanged,
            ),
            if (selectedSupplier != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      quoteLinkCount == 0
                          ? 'Aun no hay links de compra agregados.'
                          : '$quoteLinkCount link(s) de compra agregados.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : onManageLinks,
                    icon: const Icon(Icons.link),
                    label: Text(
                      quoteLinkCount == 0 ? 'Agregar links' : 'Editar links',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Los links se agregan en el editor y quedan guardados al cerrar con "Guardar y cerrar".',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: comprasCommentController,
                decoration: const InputDecoration(
                  labelText: 'Comentario general del area de compras',
                ),
                minLines: 2,
                maxLines: 4,
                enabled: !isBusy,
              ),
              const SizedBox(height: 6),
              Text(
                'Este comentario solo se mostrara en el PDF general de la compra por proveedor.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (workingQuote != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Compra cargada: ${workingQuote!.id}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Text('No hay items pendientes para este proveedor.')
              else ...[
                for (final item in items) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.item.description),
                    subtitle: Text(
                      'Orden ${item.orderId} - ${item.requesterName} - ${_money(item.amount)}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Ver PDF de la orden',
                          onPressed: onViewOrderPdf == null
                              ? null
                              : () => onViewOrderPdf!(item.orderId),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: isBusy ? null : onViewPdf,
                  child: const Text('Ver PDF general'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SupplierQuoteLinkEditorResult {
  const _SupplierQuoteLinkEditorResult({required this.links});

  final List<String> links;
}

class _SupplierQuoteLinkEditorDialog extends StatefulWidget {
  const _SupplierQuoteLinkEditorDialog({
    required this.initialLinks,
    required this.onOpenLink,
  });

  final List<String> initialLinks;
  final Future<void> Function(String raw) onOpenLink;

  @override
  State<_SupplierQuoteLinkEditorDialog> createState() =>
      _SupplierQuoteLinkEditorDialogState();
}

class _SupplierQuoteLinkEditorDialogState
    extends State<_SupplierQuoteLinkEditorDialog> {
  late final TextEditingController _linkController;
  late final List<String> _links;

  @override
  void initState() {
    super.initState();
    _linkController = TextEditingController();
    _links = List<String>.from(widget.initialLinks);
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar links de compra'),
      content: SizedBox(
        width: 640,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Agrega uno o varios links de compra, uno por uno.'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _linkController,
                      decoration: const InputDecoration(
                        labelText: 'Link de compra',
                        prefixIcon: Icon(Icons.link),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      onSubmitted: (_) => _addLink(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _addLink,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 260,
                child: _links.isEmpty
                    ? const Center(child: Text('Aún no hay links agregados.'))
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final link in _links)
                            Card(
                              child: ListTile(
                                title: Text(
                                  link,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                leading: const Icon(Icons.link),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _editLink(link),
                                    ),
                                    IconButton(
                                      tooltip: 'Abrir link',
                                      icon: const Icon(Icons.open_in_new),
                                      onPressed: () => widget.onOpenLink(link),
                                    ),
                                    IconButton(
                                      tooltip: 'Quitar',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _removeLink(link),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
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
          onPressed: () => Navigator.pop(
            context,
            _SupplierQuoteLinkEditorResult(links: List<String>.from(_links)),
          ),
          child: const Text('Guardar y cerrar'),
        ),
      ],
    );
  }

  void _addLink() {
    final normalized = _validateLink(_linkController.text, showErrors: true);
    if (normalized == null) return;
    setState(() {
      _links.add(normalized);
      _linkController.clear();
    });
  }

  void _removeLink(String link) {
    setState(() => _links.remove(link));
  }

  Future<void> _editLink(String link) async {
    final urlController = TextEditingController(text: link);
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar link de compra'),
        content: TextFormField(
          controller: urlController,
          decoration: const InputDecoration(
            labelText: 'Link de compra',
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final normalized = _validateLink(
                urlController.text,
                exclude: link,
                showErrors: true,
              );
              if (normalized == null) return;
              Navigator.pop(context, normalized);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    urlController.dispose();
    if (updated == null) return;
    final index = _links.indexOf(link);
    if (index < 0) return;
    setState(() => _links[index] = updated);
  }

  String? _validateLink(String raw, {String? exclude, bool showErrors = false}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      if (showErrors) {
        _showDialogMessage('Ingresa un link antes de agregarlo.');
      }
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      if (showErrors) {
        _showDialogMessage('El link debe ser una URL http o https válida.');
      }
      return null;
    }
    final normalized = uri.toString();
    final duplicate = _links.any(
      (link) => link == normalized && link != (exclude ?? ''),
    );
    if (duplicate) {
      if (showErrors) {
        _showDialogMessage('Ese link ya está agregado.');
      }
      return null;
    }
    return normalized;
  }

  void _showDialogMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _QuotesPanel extends StatelessWidget {
  const _QuotesPanel({
    required this.quotes,
    required this.allOrders,
    required this.pendingOrders,
    required this.quoteSendStates,
    required this.isDireccion,
    required this.onOpenOrder,
    required this.onViewOrderPdf,
    this.onViewPdf,
    this.onCancel,
    this.onApprove,
    this.onReject,
  });

  final List<SupplierQuote> quotes;
  final List<PurchaseOrder> allOrders;
  final List<_PendingDashboardOrder> pendingOrders;
  final Map<String, _QuoteSendState> quoteSendStates;
  final bool isDireccion;
  final ValueChanged<String>? onOpenOrder;
  final ValueChanged<String>? onViewOrderPdf;
  final ValueChanged<SupplierQuote>? onViewPdf;
  final ValueChanged<SupplierQuote>? onCancel;
  final ValueChanged<SupplierQuote>? onApprove;
  final ValueChanged<SupplierQuote>? onReject;

  @override
  Widget build(BuildContext context) {
    if (!isDireccion && quotes.isEmpty && pendingOrders.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isDireccion && quotes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No hay compras con ese filtro.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        else
          for (final quote in quotes) ...[
            _QuoteCard(
              quote: quote,
              allOrders: allOrders,
              sendState: quoteSendStates[quote.id] ?? const _QuoteSendState(),
              isDireccion: isDireccion,
              onOpenOrder: onOpenOrder,
              onViewPdf: onViewPdf == null ? null : () => onViewPdf!(quote),
              onCancel: onCancel == null ? null : () => onCancel!(quote),
              onApprove: onApprove == null ? null : () => onApprove!(quote),
              onReject: onReject == null ? null : () => onReject!(quote),
            ),
            const SizedBox(height: 12),
          ],
        if (!isDireccion && pendingOrders.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Ordenes con items pendientes por completar compra',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final pendingOrder in pendingOrders) ...[
            _PendingDashboardOrderCard(
              order: pendingOrder,
              onViewOrderPdf: onViewOrderPdf,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.allOrders,
    required this.sendState,
    required this.isDireccion,
    this.onOpenOrder,
    this.onViewPdf,
    this.onCancel,
    this.onApprove,
    this.onReject,
  });

  final SupplierQuote quote;
  final List<PurchaseOrder> allOrders;
  final _QuoteSendState sendState;
  final bool isDireccion;
  final ValueChanged<String>? onOpenOrder;
  final VoidCallback? onViewPdf;
  final VoidCallback? onCancel;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final relatedOrders = _relatedOrdersForQuote(quote, allOrders);
    final orderCount = relatedOrders.length;
    final canManageQuote = !isDireccion;
    final amountTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  quote.supplier,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Chip(label: Text(quote.status.label)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Folio ${quote.displayId}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text('${quote.items.length} item(s) - $orderCount orden(es)'),
          if (relatedOrders.isNotEmpty) ...[
            const SizedBox(height: 8),
            PreviousStatusDurationPill(
              orderIds: [for (final order in relatedOrders) order.id],
              fromStatus: isDireccion
                  ? PurchaseOrderStatus.dataComplete
                  : PurchaseOrderStatus.cotizaciones,
              toStatus: isDireccion
                  ? PurchaseOrderStatus.authorizedGerencia
                  : PurchaseOrderStatus.dataComplete,
              label: isDireccion
                  ? 'Tiempo en dashboard de compras'
                  : 'Tiempo en pendientes de compras',
              alignRight: false,
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDireccion
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDireccion ? 'Monto total a pagar' : 'Monto total',
                  style: amountTheme.labelLarge?.copyWith(
                    color: isDireccion
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _money(quote.totalAmount),
                  style: amountTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isDireccion
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (canManageQuote) ...[
            const SizedBox(height: 6),
            Text(
              sendState.canSend
                  ? 'Lista para enviar a autorizacion de pago.'
                  : sendState.message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (quote.links.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${quote.links.length} link(s) disponibles',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (quote.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Ordenes utilizadas',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final order in relatedOrders)
                  Tooltip(
                    message: 'ver pdf de la orden',
                    child: FilledButton.tonalIcon(
                      onPressed: onOpenOrder == null
                          ? null
                          : () => onOpenOrder!(order.id),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        _orderNeedsMoreQuotes(order)
                            ? '${order.id} (faltan items)'
                            : order.id,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isDireccion)
                OutlinedButton.icon(
                  onPressed: quote.links.isEmpty
                      ? null
                      : () => _openLinks(context, quote.links),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(quote.links.length > 1 ? 'Abrir links' : 'Abrir link'),
                ),
              if (isDireccion)
                OutlinedButton.icon(
                  onPressed: onViewPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Ver PDF general'),
                ),
              if (isDireccion)
                OutlinedButton(
                  onPressed: onReject,
                  child: const Text('Rechazar'),
                ),
              if (isDireccion)
                FilledButton(
                  onPressed: onApprove,
                  child: const Text('Autorizar'),
                )
              else ...[
                OutlinedButton(
                  onPressed: onViewPdf,
                  child: const Text('Ver PDF general'),
                ),
                OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Cancelar'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.isAbsolute) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openLinks(BuildContext context, List<String> links) async {
    if (links.isEmpty) return;
    if (links.length == 1) {
      await _openLink(links.first);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Links disponibles'),
            ),
            for (var index = 0; index < links.length; index++)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(
                  'Link ${index + 1}',
                ),
                subtitle: Text(
                  links[index],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _openLink(links[index]);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PendingDashboardOrderCard extends StatelessWidget {
  const _PendingDashboardOrderCard({
    required this.order,
    this.onViewOrderPdf,
  });

  final _PendingDashboardOrder order;
  final ValueChanged<String>? onViewOrderPdf;

  @override
  Widget build(BuildContext context) {
    final suppliersLabel = order.suppliers.isEmpty
        ? 'sin proveedor asignado'
        : order.suppliers.join(', ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orden ${order.order.id}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${order.pendingItems} item(s) pendientes por completar compra.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Ya aparece en: $suppliersLabel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                PreviousStatusDurationPill(
                  orderIds: [order.order.id],
                  fromStatus: PurchaseOrderStatus.cotizaciones,
                  toStatus: PurchaseOrderStatus.dataComplete,
                  label: 'Tiempo en pendientes de compras',
                  alignRight: false,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: onViewOrderPdf == null
                    ? null
                    : () => onViewOrderPdf!(order.order.id),
                child: const Text('Ver PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}

class _QuoteSendState {
  const _QuoteSendState({
    this.canSend = false,
    this.message =
        'Completa las compras pendientes para enviar a autorizacion de pago.',
  });

  final bool canSend;
  final String message;
}

class _SupplierGroupedItem {
  const _SupplierGroupedItem({
    required this.orderId,
    required this.requesterName,
    required this.areaName,
    required this.item,
    required this.amount,
  });

  final String orderId;
  final String requesterName;
  final String areaName;
  final PurchaseOrderItem item;
  final num amount;
}

class _PendingDashboardOrder {
  const _PendingDashboardOrder({
    required this.order,
    required this.suppliers,
    required this.pendingItems,
  });

  final PurchaseOrder order;
  final List<String> suppliers;
  final int pendingItems;
}

class _DireccionQuotesFilters extends StatelessWidget {
  const _DireccionQuotesFilters({
    required this.searchController,
    required this.searchQuery,
    required this.selectedRange,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onPickDate,
    required this.onClearDate,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final DateTimeRange? selectedRange;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        final searchField = TextField(
          controller: searchController,
          decoration: InputDecoration(
            labelText: 'Buscar por proveedor, folio, solicitante, cliente...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchQuery.isEmpty
                ? null
                : IconButton(
                    onPressed: onClearSearch,
                    icon: const Icon(Icons.clear),
                  ),
          ),
          onChanged: onSearchChanged,
        );
        final dateFilter = OrderDateRangeFilterButton(
          selectedRange: selectedRange,
          onPickDate: onPickDate,
          onClearDate: onClearDate,
        );
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: dateFilter,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 12),
            dateFilter,
          ],
        );
      },
    );
  }
}

Map<String, SupplierQuote> _quotesBySupplier(List<SupplierQuote> quotes) {
  final bySupplier = <String, SupplierQuote>{};
  for (final quote in quotes) {
    final supplier = quote.supplier.trim();
    if (supplier.isEmpty || bySupplier.containsKey(supplier)) continue;
    bySupplier[supplier] = quote;
  }
  return bySupplier;
}

OrderUrgencyCounts _direccionQuoteCounts({
  required List<SupplierQuote> quotes,
  required List<PurchaseOrder> allOrders,
}) {
  var normal = 0;
  var urgente = 0;
  for (final quote in quotes) {
    switch (_quoteUrgency(quote, allOrders)) {
      case PurchaseOrderUrgency.normal:
        normal += 1;
        break;
      case PurchaseOrderUrgency.urgente:
        urgente += 1;
        break;
    }
  }
  return OrderUrgencyCounts(
    total: quotes.length,
    normal: normal,
    urgente: urgente,
  );
}

bool _matchesDireccionQuoteFilters({
  required SupplierQuote quote,
  required List<PurchaseOrder> allOrders,
  String query = '',
  OrderUrgencyFilter filter = OrderUrgencyFilter.all,
  DateTimeRange? range,
}) {
  if (!_quoteMatchesSearch(quote: quote, allOrders: allOrders, query: query)) {
    return false;
  }
  final quoteUrgency = _quoteUrgency(quote, allOrders);
  final urgencyMatches = switch (filter) {
    OrderUrgencyFilter.all => true,
    OrderUrgencyFilter.normal => quoteUrgency == PurchaseOrderUrgency.normal,
    OrderUrgencyFilter.urgente => quoteUrgency == PurchaseOrderUrgency.urgente,
  };
  if (!urgencyMatches) return false;
  if (range == null) return true;
  final createdAt = quote.createdAt;
  if (createdAt == null) return false;
  final createdDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  return !createdDate.isBefore(start) && !createdDate.isAfter(end);
}

bool _quoteMatchesSearch({
  required SupplierQuote quote,
  required List<PurchaseOrder> allOrders,
  required String query,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  final buffer = StringBuffer();

  void addValue(Object? value) {
    if (value == null) return;
    final text = value.toString().trim();
    if (text.isEmpty) return;
    buffer.write(text.toLowerCase());
    buffer.write(' ');
  }

  addValue(quote.id);
  addValue(quote.displayId);
  addValue(quote.supplier);
  addValue(quote.status.label);
  for (final item in quote.items) {
    addValue(item.orderId);
    addValue(item.orderFolio);
    addValue(item.description);
    addValue(item.partNumber);
    addValue(item.quantity);
    addValue(item.unit);
    addValue(item.amount);
  }
  for (final order in _relatedOrdersForQuote(quote, allOrders)) {
    addValue(order.id);
    addValue(order.requesterName);
    addValue(order.areaName);
    addValue(order.urgency.label);
    addValue(order.clientNote);
    addValue(order.supplier);
    addValue(order.internalOrder);
    for (final item in order.items) {
      addValue(item.description);
      addValue(item.customer);
      addValue(item.internalOrder);
      addValue(item.partNumber);
      addValue(item.supplier);
      addValue(item.quantity);
      addValue(item.unit);
    }
  }

  final haystack = buffer.toString();
  final tokens = normalized
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty);
  for (final token in tokens) {
    if (!haystack.contains(token)) return false;
  }
  return true;
}

PurchaseOrderUrgency _quoteUrgency(
  SupplierQuote quote,
  List<PurchaseOrder> allOrders,
) {
  final relatedOrders = _relatedOrdersForQuote(quote, allOrders);
  if (relatedOrders.any((order) => order.urgency == PurchaseOrderUrgency.urgente)) {
    return PurchaseOrderUrgency.urgente;
  }
  return PurchaseOrderUrgency.normal;
}

List<PurchaseOrder> _relatedOrdersForQuote(
  SupplierQuote quote,
  List<PurchaseOrder> allOrders,
) {
  final relatedIds = quote.orderIds.toSet();
  final related = allOrders
      .where((order) => relatedIds.contains(order.id))
      .toList(growable: false)
    ..sort((a, b) => a.id.compareTo(b.id));
  return related;
}

List<_PendingDashboardOrder> _buildPendingDashboardOrders({
  required List<PurchaseOrder> allOrders,
  required String? selectedSupplier,
  required String? selectedQuoteId,
}) {
  final pendingOrders = <_PendingDashboardOrder>[];
  for (final order in allOrders) {
    if (order.status != PurchaseOrderStatus.dataComplete) continue;
    final pendingItems = _pendingQuoteItemsCount(order);
    if (pendingItems <= 0) continue;
    if (_shouldHidePendingDashboardOrderForSelectedSupplier(
      order: order,
      selectedSupplier: selectedSupplier,
      selectedQuoteId: selectedQuoteId,
    )) {
      continue;
    }
    final suppliers = <String>{
      for (final item in order.items)
        if ((item.supplier ?? '').trim().isNotEmpty && (item.budget ?? 0) > 0)
          (item.supplier ?? '').trim(),
    };
    pendingOrders.add(
      _PendingDashboardOrder(
        order: order,
        suppliers: suppliers.toList(growable: false)..sort(),
        pendingItems: pendingItems,
      ),
    );
  }
  pendingOrders.sort((a, b) => a.order.id.compareTo(b.order.id));
  return pendingOrders;
}

bool _shouldHidePendingDashboardOrderForSelectedSupplier({
  required PurchaseOrder order,
  required String? selectedSupplier,
  required String? selectedQuoteId,
}) {
  final supplier = selectedSupplier?.trim() ?? '';
  if (supplier.isEmpty) return false;

  var hasPendingItemsForSelectedSupplier = false;
  var hasPendingItemsForOtherSuppliers = false;

  for (final item in order.items) {
    final itemSupplier = (item.supplier ?? '').trim();
    final amount = item.budget ?? 0;
    final missingAssignment = itemSupplier.isEmpty || amount <= 0;
    final quoteId = item.quoteId?.trim() ?? '';
    final missingQuote =
        quoteId.isEmpty ||
        quoteId == selectedQuoteId ||
        item.quoteStatus == PurchaseOrderItemQuoteStatus.rejected;

    if (!missingAssignment && !missingQuote) {
      continue;
    }

    if (itemSupplier == supplier) {
      hasPendingItemsForSelectedSupplier = true;
    } else {
      hasPendingItemsForOtherSuppliers = true;
    }
  }

  return hasPendingItemsForSelectedSupplier && !hasPendingItemsForOtherSuppliers;
}

List<String> _supplierOptions(
  List<PurchaseOrder> orders,
  Map<String, SupplierQuote> editableQuotesBySupplier,
) {
  final suppliers = <String>{};
  for (final order in orders) {
    for (final item in order.items) {
      final supplier = (item.supplier ?? '').trim();
      final amount = item.budget ?? 0;
      if (supplier.isEmpty || amount <= 0) continue;
      if (!_supplierHasDashboardItems(
        orders: orders,
        supplier: supplier,
        editableQuoteId: editableQuotesBySupplier[supplier]?.id,
      )) {
        continue;
      }
      suppliers.add(supplier);
    }
  }
  return suppliers.toList(growable: false)..sort();
}

bool _supplierHasDashboardItems({
  required List<PurchaseOrder> orders,
  required String supplier,
  required String? editableQuoteId,
}) {
  return _collectSupplierItems(
    orders: orders,
    supplier: supplier,
    editableQuoteId: editableQuoteId,
  ).isNotEmpty;
}

List<_SupplierGroupedItem> _collectSupplierItems({
  required List<PurchaseOrder> orders,
  required String supplier,
  required String? editableQuoteId,
}) {
  final items = <_SupplierGroupedItem>[];
  for (final order in orders) {
    for (final item in order.items) {
      final itemSupplier = (item.supplier ?? '').trim();
      final amount = item.budget ?? 0;
      final quoteId = item.quoteId?.trim();
      final include =
          itemSupplier == supplier &&
          amount > 0 &&
          (quoteId == null ||
              quoteId.isEmpty ||
              quoteId == editableQuoteId ||
              item.quoteStatus == PurchaseOrderItemQuoteStatus.rejected);
      if (!include) continue;
      items.add(
        _SupplierGroupedItem(
          orderId: order.id,
          requesterName: order.requesterName,
          areaName: order.areaName,
          item: item,
          amount: amount,
        ),
      );
    }
  }

  items.sort((a, b) {
    final orderCompare = a.orderId.compareTo(b.orderId);
    if (orderCompare != 0) return orderCompare;
    return a.item.line.compareTo(b.item.line);
  });
  return items;
}

List<SupplierQuoteItemRef> _refsFromGroupedItems(List<_SupplierGroupedItem> items) {
  return [
    for (final item in items)
      SupplierQuoteItemRef(
        orderId: item.orderId,
        orderFolio: item.orderId,
        line: item.item.line,
        description: item.item.description,
        quantity: item.item.quantity,
        unit: item.item.unit,
        partNumber: item.item.partNumber,
        amount: item.amount,
      ),
  ];
}

SupplierQuotePdfData _buildPdfData({
  required CompanyBranding branding,
  required List<PurchaseOrder> allOrders,
  required String supplier,
  required String quoteId,
  required List<String> links,
  required List<SupplierQuoteItemRef> refs,
  String? comprasComment,
  DateTime? createdAt,
  String? processedByName,
  String? processedByArea,
  String? authorizedByName,
  String? authorizedByArea,
}) {
  final refsByOrder = <String, Map<int, SupplierQuoteItemRef>>{};
  for (final ref in refs) {
    refsByOrder.putIfAbsent(ref.orderId, () => <int, SupplierQuoteItemRef>{})[ref.line] = ref;
  }

  final orders = <SupplierQuotePdfOrderData>[];
  for (final order in allOrders) {
    final orderRefs = refsByOrder[order.id];
    if (orderRefs == null || orderRefs.isEmpty) continue;

    final items = <SupplierQuotePdfItemData>[];
    for (final item in order.items) {
      final selectedRef = orderRefs[item.line];
      items.add(
        SupplierQuotePdfItemData(
          line: item.line,
          description: item.description,
          quantity: item.quantity,
          unit: item.unit,
          selected: selectedRef != null,
          partNumber: item.partNumber,
          customer: item.customer,
          amount: selectedRef?.amount ?? item.budget,
          etaDate: item.deliveryEtaDate,
        ),
      );
    }

    orders.add(
      SupplierQuotePdfOrderData(
        orderId: order.id,
        requesterName: order.requesterName,
        areaName: order.areaName,
        items: items,
      ),
    );
  }

  orders.sort((a, b) => a.orderId.compareTo(b.orderId));
  return SupplierQuotePdfData(
    branding: branding,
    quoteId: quoteId,
    supplier: supplier,
    links: links,
    orders: orders,
    comprasComment: comprasComment,
    createdAt: createdAt,
    processedByName: processedByName,
    processedByArea: processedByArea,
    authorizedByName: authorizedByName,
    authorizedByArea: authorizedByArea,
  );
}

Map<String, _QuoteSendState> _buildQuoteSendStates({
  required List<SupplierQuote> quotes,
  required List<PurchaseOrder> orders,
}) {
  final states = <String, _QuoteSendState>{};
  final ordersById = {
    for (final order in orders) order.id: order,
  };

  for (final quote in quotes) {
    if (quote.items.isEmpty) {
      states[quote.id] = const _QuoteSendState(
        message: 'No hay items cargados para esta compra.',
      );
      continue;
    }
    if (quote.links.isEmpty) {
      states[quote.id] = const _QuoteSendState(
        message: 'Agrega al menos un link de compra.',
      );
      continue;
    }

    String? blockingMessage;
    for (final ref in quote.items) {
      final orderId = ref.orderId.trim();
      if (orderId.isEmpty) continue;
      final order = ordersById[orderId];
      if (order == null) {
        blockingMessage = 'No se encontro la orden $orderId.';
        break;
      }
      final orderProblem = _validateQuoteItemForDireccion(
        order: order,
        quote: quote,
        line: ref.line,
      );
      if (orderProblem != null) {
        blockingMessage = 'Orden $orderId item ${ref.line}: $orderProblem';
        break;
      }
    }

    states[quote.id] = blockingMessage == null
        ? const _QuoteSendState(
            canSend: true,
            message: 'Lista para enviar a autorizacion de pago.',
          )
        : _QuoteSendState(message: blockingMessage);
  }

  return states;
}

String? _validateQuoteItemForDireccion({
  required PurchaseOrder order,
  required SupplierQuote quote,
  required int line,
}) {
  for (final item in order.items) {
    if (item.line != line) continue;
    if (!_itemHasCompleteQuoteData(item)) {
      return 'faltan proveedor o presupuesto.';
    }
    final quoteId = item.quoteId?.trim() ?? '';
    if (quoteId != quote.id ||
        item.quoteStatus == PurchaseOrderItemQuoteStatus.rejected) {
      return 'no esta ligado correctamente a esta compra.';
    }
    return null;
  }
  return 'no se encontro en la orden.';
}

bool _itemHasCompleteQuoteData(PurchaseOrderItem item) {
  final supplier = (item.supplier ?? '').trim();
  final amount = item.budget ?? 0;
  return supplier.isNotEmpty && amount > 0;
}

bool _orderNeedsMoreQuotes(PurchaseOrder order) {
  return _pendingQuoteItemsCount(order) > 0;
}

String _money(num value) {
  return '\$${value.toDouble().toStringAsFixed(2)}';
}

int _pendingQuoteItemsCount(PurchaseOrder order) {
  var pending = 0;
  for (final item in order.items) {
    final supplier = (item.supplier ?? '').trim();
    final amount = item.budget ?? 0;
    final missingAssignment = supplier.isEmpty || amount <= 0;
    final missingQuote =
        item.quoteId == null ||
        item.quoteStatus == PurchaseOrderItemQuoteStatus.rejected;
    if (missingAssignment || missingQuote) {
      pending += 1;
    }
  }
  return pending;
}

List<SupplierQuotePdfData> _buildCacheCandidates({
  required List<PurchaseOrder> allOrders,
  required CompanyBranding branding,
  required AppUser? actor,
  required List<SupplierQuote> visibleQuotes,
  required String? selectedSupplier,
  required List<_SupplierGroupedItem> selectedItems,
  required List<String> selectedLinks,
  required SupplierQuote? selectedQuote,
  required String selectedComprasComment,
}) {
  final dataList = <SupplierQuotePdfData>[];

  if (selectedSupplier != null && selectedItems.isNotEmpty) {
    dataList.add(
      _buildPdfData(
        branding: branding,
        allOrders: allOrders,
        supplier: selectedSupplier,
        quoteId: selectedQuote?.id ?? 'COTIZACION-${selectedSupplier.replaceAll(RegExp(r'\s+'), '-')}',
        links: selectedLinks,
        refs: _refsFromGroupedItems(selectedItems),
        comprasComment: selectedComprasComment,
        createdAt: selectedQuote?.createdAt,
        processedByName: actor?.name,
        processedByArea: actor?.areaDisplay,
      ),
    );
  }

  for (final quote in visibleQuotes.take(2)) {
    dataList.add(
      _buildPdfData(
        branding: branding,
        allOrders: allOrders,
        supplier: quote.supplier,
        quoteId: quote.id,
        links: quote.links,
        refs: quote.items,
        comprasComment: quote.comprasComment,
        createdAt: quote.createdAt,
        processedByName: quote.processedByName ?? actor?.name,
        processedByArea: quote.processedByArea ?? actor?.areaDisplay,
        authorizedByName: quote.approvedByName,
        authorizedByArea: quote.approvedByArea,
      ),
    );
  }

  return dataList;
}

bool _canAuthorizeQuote(AppUser actor) {
  return isAdminRole(actor.role) || isDireccionGeneralLabel(actor.areaDisplay);
}
