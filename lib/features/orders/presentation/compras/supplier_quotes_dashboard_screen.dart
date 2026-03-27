import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/session_drafts.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/data/purchase_order_repository.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/domain/supplier_quote.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_urgency_controls.dart';
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
    extends ConsumerState<CotizacionesDashboardScreen>
    with RouteAware, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _linksController = TextEditingController();
  final TextEditingController _comprasCommentController =
      TextEditingController();
  bool _isBusy = false;
  bool _isLoading = true;
  String? _selectedSupplier;
  String _searchQuery = '';
  OrderUrgencyFilter _urgencyFilter = OrderUrgencyFilter.all;
  DateTimeRange? _createdDateRangeFilter;
  String? _loadError;
  _DashboardSnapshot? _snapshot;
  int _loadToken = 0;
  bool _isRouteSubscribed = false;

  bool get _isDireccion => widget.mode == CotizacionesDashboardMode.direccion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await SessionDraftStore.ensureInitialized();
      if (mounted) {
        _reloadDashboard(clearSelection: false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      if (_isRouteSubscribed) {
        routeObserver.unsubscribe(this);
      }
      routeObserver.subscribe(this, route);
      _isRouteSubscribed = true;
    }
  }

  @override
  void dispose() {
    if (_isRouteSubscribed) {
      routeObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _linksController.dispose();
    _comprasCommentController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    if (!mounted) return;
    _reloadDashboard(clearSelection: false, preferIncremental: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _reloadDashboard(clearSelection: false, preferIncremental: true);
    }
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
    final compactAppBar = useCompactOrderModuleAppBar(context);
    final snapshot = _snapshot;
    final titleOrders = snapshot?.allOrders ?? const <PurchaseOrder>[];
    final titleQuotes = _isDireccion && snapshot != null
        ? _withoutDraftQuotes(snapshot.quotes)
            .where(
              (quote) => quote.status == SupplierQuoteStatus.pendingDireccion,
            )
            .toList(growable: false)
        : const <SupplierQuote>[];
    final body = _buildDashboardBody(snapshot);

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
        actions: [
          IconButton(
            onPressed: _isLoading ? null : () => _reloadDashboard(clearSelection: false),
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
          ),
        ],
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

  Widget _buildDashboardBody(_DashboardSnapshot? snapshot) {
    if (_isLoading && snapshot == null) {
      return const AppSplash();
    }
    if (_loadError != null && snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _reloadDashboard(clearSelection: false),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (snapshot == null) {
      return const AppSplash();
    }

    final completedOrders = snapshot.completedOrders;
    final allOrders = snapshot.allOrders;
    final quotes = snapshot.quotes;
    final blockedQuoteItemKeys = _buildBlockedQuoteItemKeys(quotes);
    final actor = snapshot.actor;
    final branding = snapshot.branding;
    final filteredQuotes = _withoutDraftQuotes(quotes);
    final editableQuotes = _isDireccion
        ? filteredQuotes
            .where(
              (quote) => quote.status == SupplierQuoteStatus.pendingDireccion,
            )
            .toList(growable: false)
        : filteredQuotes
            .where(
              (quote) => quote.status == SupplierQuoteStatus.rejected,
            )
            .toList(growable: false);
    final supplierOptions = _isDireccion
        ? const <String>[]
        : _supplierOptions(
            completedOrders,
            blockedQuoteItemKeys: blockedQuoteItemKeys,
          );
    const SupplierQuote? selectedQuote = null;
    const Set<String> selectedQuoteItemKeys = <String>{};
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
        : editableQuotes;
    final supplierItems = !_isDireccion && _selectedSupplier != null
        ? _collectSupplierItems(
            orders: completedOrders,
            supplier: _selectedSupplier!,
            editableQuoteItemKeys: selectedQuoteItemKeys,
            blockedQuoteItemKeys: blockedQuoteItemKeys,
          )
        : const <_SupplierGroupedItem>[];
    final pendingDashboardOrders = _isDireccion
        ? const <_PendingDashboardOrder>[]
        : _buildPendingDashboardOrders(
            allOrders: allOrders,
            selectedSupplier: _selectedSupplier,
            selectedQuoteItemKeys: selectedQuoteItemKeys,
            blockedQuoteItemKeys: blockedQuoteItemKeys,
          );
    final quoteSendStates = _buildQuoteSendStates(
      quotes: visibleQuotes,
      orders: allOrders,
    );
    final selectedLinks = _parseLinks(_linksController.text);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_loadError != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_loadError!),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_isLoading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
        ],
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
              null,
            ),
            onViewOrderPdf: _openOrderPdf,
            onManageLinks: _selectedSupplier == null ? null : _manageQuoteLinks,
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
          onEdit: _isDireccion ? null : _editQuote,
          onApprove: _isDireccion ? _approveQuoteFromCard : null,
          onReject: _isDireccion ? _rejectQuoteFromCard : null,
        ),
      ],
    );
  }

  void _setSelectedSupplier(String? supplier, SupplierQuote? quote) {
    final cachedDraft = supplier == null
        ? null
        : SessionDraftStore.supplierDashboard(supplier);
    final draftHasLocalState = cachedDraft != null &&
        (cachedDraft.links.isNotEmpty || cachedDraft.comprasComment.trim().isNotEmpty);
    setState(() {
      _selectedSupplier = supplier;
      _linksController.text = draftHasLocalState
          ? cachedDraft.links.join('\n')
          : (quote?.links.join('\n') ?? '');
      _comprasCommentController.text =
          (draftHasLocalState
                  ? cachedDraft.comprasComment
                  : (quote?.comprasComment ?? ''))
              .trim();
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
    const runActionInsidePdf = false;
    final shouldSend = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SupplierQuotePdfViewScreen(
          data: data,
          primaryActionLabel: 'Enviar a autorizacion de pago',
          primaryActionEnabled: _parseLinks(_linksController.text).isNotEmpty,
          closeOnPrimaryAction: runActionInsidePdf,
          returnPrimaryActionResult: !runActionInsidePdf,
          onPrimaryAction: runActionInsidePdf
              ? () => _sendSelectionToDireccionFromPdf(
                    supplier: supplier,
                    items: items,
                    quote: quote,
                  )
              : null,
        ),
      ),
    );
    if (shouldSend == true && !runActionInsidePdf) {
      await _waitForPdfRouteToSettle();
      await _sendSelectionToDireccionFromPdf(
        supplier: supplier,
        items: items,
        quote: quote,
      );
    }
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
    const runActionInsidePdf = false;
    final shouldSend = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SupplierQuotePdfViewScreen(
          data: data,
          primaryActionLabel: _isDireccion
              ? null
              : 'Enviar a autorizacion de pago',
          primaryActionEnabled: _isDireccion ? true : quote.links.isNotEmpty,
          closeOnPrimaryAction: runActionInsidePdf,
          returnPrimaryActionResult: !_isDireccion && !runActionInsidePdf,
          onPrimaryAction: runActionInsidePdf
              ? () => _sendStoredQuoteToDireccionFromPdf(quote)
              : null,
        ),
      ),
    );
    if (shouldSend == true && !_isDireccion && !runActionInsidePdf) {
      await _waitForPdfRouteToSettle();
      await _sendStoredQuoteToDireccionFromPdf(quote);
    }
  }

  void _logDashboard(String message) {
    // Crash investigation instrumentation removed.
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
    _logDashboard(
      'enviar seleccion supplier=$supplier quoteId=${quote?.id ?? 'N/A'} '
      'items=${items.length} links=${links.length}',
    );
    final actor = _snapshot?.actor;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return false;
    }
    if (useManualOrderRefreshOnWindowsRelease) {
      return _sendSelectionToDireccionDetached(
        supplier: supplier,
        items: items,
        quote: quote,
        actor: actor,
        links: links,
      );
    }
    setState(() => _isBusy = true);
    try {
      final repository = ref.read(purchaseOrderRepositoryProvider);
      final itemRefs = _refsFromGroupedItems(items);
      SupplierQuote storedQuote;
      List<PurchaseOrder> resolvedOrders = const <PurchaseOrder>[];
      if (useManualOrderRefreshOnWindowsRelease) {
        final relatedOrders = _resolveOrdersForQuoteMutation(
          <String>{
            for (final ref in itemRefs) ref.orderId,
            ...?quote?.orderIds,
          },
        );
        final result = await _runDashboardStage<SupplierQuoteSubmissionResult>(
          label: 'enviar la compra a autorizacion de pago',
          action: () => repository.submitSupplierQuoteForDireccionWithResolvedOrders(
            existingQuote: quote,
            supplier: supplier,
            items: itemRefs,
            links: links,
            comprasComment: _comprasCommentController.text.trim(),
            actor: actor,
            relatedOrders: relatedOrders,
          ),
        );
        storedQuote = result.quote;
        resolvedOrders = result.updatedOrders;
      } else {
        storedQuote = await _runDashboardStage<SupplierQuote>(
          label: 'enviar la compra a autorizacion de pago',
          action: () => repository.submitSupplierQuoteForDireccion(
            existingQuote: quote,
            supplier: supplier,
            items: itemRefs,
            links: links,
            comprasComment: _comprasCommentController.text.trim(),
            actor: actor,
          ),
        );
      }
      if (!useManualOrderRefreshOnWindowsRelease) {
        refreshOrderModuleTransitionData(
          ref,
          quoteId: storedQuote.id,
          orderIds: storedQuote.orderIds,
        );
        await _refreshDashboardSnapshotForOrders(
          clearSelection: true,
          upsertQuote: storedQuote,
          touchedOrderIds: storedQuote.orderIds,
          resolvedOrders: resolvedOrders,
        );
      } else {
        _commitResolvedDashboardMutation(
          clearSelection: true,
          upsertQuote: storedQuote,
          resolvedOrders: resolvedOrders,
        );
      }
      SessionDraftStore.clearSupplierDashboard(supplier);
      _logDashboard('seleccion enviada a DG supplier=$supplier quote=${storedQuote.id}');
      if (!mounted) return true;
      _showMessage('Compra enviada para autorizacion de pago.');
      return true;
    } catch (error, stack) {
      _logDashboard('error enviando seleccion supplier=$supplier error=$error');
      _showMessage(reportError(error, stack, context: 'SupplierQuotes.sendSelection'));
      return false;
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool> _sendSelectionToDireccionDetached({
    required String supplier,
    required List<_SupplierGroupedItem> items,
    required SupplierQuote? quote,
    required AppUser actor,
    required List<String> links,
  }) async {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    final itemRefs = _refsFromGroupedItems(items);
    final relatedOrders = _resolveOrdersForQuoteMutation(
      <String>{
        for (final ref in itemRefs) ref.orderId,
        ...?quote?.orderIds,
      },
    );
    final result = await Navigator.of(context).push<SupplierQuoteSubmissionResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _DetachedDashboardActionScreen<SupplierQuoteSubmissionResult>(
          title: 'Enviando a Direccion General',
          progressLabel: 'Enviando compra a autorizacion de pago...',
          action: () => _runDashboardStage<SupplierQuoteSubmissionResult>(
            label: 'enviar la compra a autorizacion de pago',
            action: () => repository.submitSupplierQuoteForDireccionWithResolvedOrders(
              existingQuote: quote,
              supplier: supplier,
              items: itemRefs,
              links: links,
              comprasComment: _comprasCommentController.text.trim(),
              actor: actor,
              relatedOrders: relatedOrders,
            ),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return false;
    _commitResolvedDashboardMutation(
      clearSelection: true,
      upsertQuote: result.quote,
      resolvedOrders: result.updatedOrders,
    );
    refreshQuoteWorkflowCounts(
      ref,
      quoteId: result.quote.id,
    );
    SessionDraftStore.clearSupplierDashboard(supplier);
    _showMessage('Compra enviada para autorizacion de pago.');
    return true;
  }

  Future<bool> _sendQuoteToDireccion(SupplierQuote quote) async {
    if (quote.links.isEmpty) {
      _showMessage(
        'Agrega al menos un link de compra antes de enviar a autorizacion de pago.',
      );
      return false;
    }
    _logDashboard(
      'enviar quote ${quote.id} links=${quote.links.length} status=${quote.status.name}',
    );
    final actor = _snapshot?.actor;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return false;
    }
    if (useManualOrderRefreshOnWindowsRelease) {
      return _sendQuoteToDireccionDetached(
        quote: quote,
        actor: actor,
      );
    }
    setState(() => _isBusy = true);
    try {
      final repository = ref.read(purchaseOrderRepositoryProvider);
      SupplierQuote submittedQuote;
      List<PurchaseOrder> resolvedOrders = const <PurchaseOrder>[];
      if (useManualOrderRefreshOnWindowsRelease) {
        final result = await _runDashboardStage<SupplierQuoteSubmissionResult>(
          label: 'enviar la compra a autorizacion de pago',
          action: () => repository.submitSupplierQuoteForDireccionWithResolvedOrders(
            existingQuote: quote,
            supplier: quote.supplier,
            items: quote.items,
            links: quote.links,
            comprasComment: quote.comprasComment,
            actor: actor,
            relatedOrders: _resolveOrdersForQuoteMutation(quote.orderIds),
          ),
        );
        submittedQuote = result.quote;
        resolvedOrders = result.updatedOrders;
      } else {
        submittedQuote = await _runDashboardStage<SupplierQuote>(
          label: 'enviar la compra a autorizacion de pago',
          action: () => repository.submitSupplierQuoteForDireccion(
            existingQuote: quote,
            supplier: quote.supplier,
            items: quote.items,
            links: quote.links,
            comprasComment: quote.comprasComment,
            actor: actor,
          ),
        );
      }
      if (!useManualOrderRefreshOnWindowsRelease) {
        refreshOrderModuleTransitionData(
          ref,
          quoteId: submittedQuote.id,
          orderIds: submittedQuote.orderIds,
        );
        await _refreshDashboardSnapshotForOrders(
          clearSelection: false,
          upsertQuote: submittedQuote,
          touchedOrderIds: submittedQuote.orderIds,
          resolvedOrders: resolvedOrders,
        );
      } else {
        _commitResolvedDashboardMutation(
          clearSelection: false,
          upsertQuote: submittedQuote,
          resolvedOrders: resolvedOrders,
        );
      }
      SessionDraftStore.clearSupplierDashboard(submittedQuote.supplier);
      _logDashboard('quote ${submittedQuote.id} enviada a DG');
      if (!mounted) return true;
      _showMessage('Compra enviada para autorizacion de pago.');
      return true;
    } catch (error, stack) {
      _logDashboard('error enviando quote ${quote.id} error=$error');
      _showMessage(reportError(error, stack, context: 'SupplierQuotes.send'));
      return false;
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool> _sendQuoteToDireccionDetached({
    required SupplierQuote quote,
    required AppUser actor,
  }) async {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    final result = await Navigator.of(context).push<SupplierQuoteSubmissionResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _DetachedDashboardActionScreen<SupplierQuoteSubmissionResult>(
          title: 'Enviando a Direccion General',
          progressLabel: 'Enviando compra a autorizacion de pago...',
          action: () => _runDashboardStage<SupplierQuoteSubmissionResult>(
            label: 'enviar la compra a autorizacion de pago',
            action: () => repository.submitSupplierQuoteForDireccionWithResolvedOrders(
              existingQuote: quote,
              supplier: quote.supplier,
              items: quote.items,
              links: quote.links,
              comprasComment: quote.comprasComment,
              actor: actor,
              relatedOrders: _resolveOrdersForQuoteMutation(quote.orderIds),
            ),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return false;
    _commitResolvedDashboardMutation(
      clearSelection: false,
      upsertQuote: result.quote,
      resolvedOrders: result.updatedOrders,
    );
    refreshQuoteWorkflowCounts(
      ref,
      quoteId: result.quote.id,
    );
    SessionDraftStore.clearSupplierDashboard(result.quote.supplier);
    _showMessage('Compra enviada para autorizacion de pago.');
    return true;
  }

  Future<T> _runDashboardStage<T>({
    required String label,
    required Future<T> Function() action,
  }) async {
    try {
      return await action();
    } catch (error, stack) {
      throw AppError(
        'No se pudo $label.',
        cause: error,
        stack: stack,
      );
    }
  }

  Future<void> _waitForPdfRouteToSettle() async {
    _logDashboard('esperando cierre completo de la vista PDF');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await WidgetsBinding.instance.endOfFrame;
    _logDashboard('vista PDF cerrada, continuando con envio');
  }

  Future<void> _cancelQuote(SupplierQuote quote) async {
    final actor = _snapshot?.actor;
    if (actor == null) {
      _showMessage('Perfil no disponible.');
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Desarmar compra ${quote.supplier}'),
        content: const Text(
          'La cotizacion desaparecera y los items volveran a estar disponibles para reutilizarse. Mientras no se desarme, esos items seguiran bloqueados para evitar duplicados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desarmar'),
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
      refreshOrderModuleTransitionData(
        ref,
        quoteId: quote.id,
        orderIds: quote.orderIds,
      );
      await _refreshDashboardSnapshotForOrders(
        clearSelection: _selectedSupplier == quote.supplier,
        removeQuoteId: quote.id,
        touchedOrderIds: quote.orderIds,
      );
      refreshQuoteWorkflowCounts(
        ref,
        quoteId: quote.id,
      );
      SessionDraftStore.clearSupplierDashboard(quote.supplier);
      if (!mounted) return;
      _showMessage('Compra desarmada. Los items quedaron disponibles otra vez.');
    } catch (error, stack) {
      _showMessage(reportError(error, stack, context: 'SupplierQuotes.cancel'));
    }
  }

  Future<void> _editQuote(SupplierQuote quote) async {
    _setSelectedSupplier(quote.supplier, quote);
    final relatedOrders = _relatedOrdersForQuote(
      quote,
      _snapshot?.allOrders ?? const <PurchaseOrder>[],
    );
    final result = await showModalBottomSheet<_QuoteEditAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _RejectedQuoteActionsSheet(
        quote: quote,
        relatedOrders: relatedOrders,
      ),
    );
    if (!mounted || result == null) return;

    if (result.kind == _QuoteEditActionKind.links) {
      await _manageQuoteLinks();
      if (!mounted) return;
      await _persistEditedQuote(
        quote,
      );
      return;
    }

    final order = result.order;
    if (order == null) return;
    final saveResult = await guardedPush<Object?>(
      context,
      '/orders/cotizaciones/${order.id}',
    );
    if (!mounted || saveResult == null) return;
    await _persistEditedQuote(
      quote,
    );
  }

  Future<void> _persistEditedQuote(SupplierQuote quote) async {
    final repository = ref.read(purchaseOrderRepositoryProvider);
    final refreshedOrders = await repository.fetchOrdersByIds(quote.orderIds);
    final updatedQuote = _rebuildEditableQuote(
      quote: quote,
      orders: refreshedOrders,
      links: _parseLinks(_linksController.text),
      comprasComment: _comprasCommentController.text.trim(),
    );
    final storedQuote = await repository.updateRejectedSupplierQuote(
      quote: updatedQuote,
      supplier: updatedQuote.supplier,
      items: updatedQuote.items,
      links: updatedQuote.links,
      comprasComment: updatedQuote.comprasComment,
    );
    _commitResolvedDashboardMutation(
      clearSelection: false,
      upsertQuote: storedQuote,
      resolvedOrders: refreshedOrders,
    );
    refreshQuoteWorkflowCounts(
      ref,
      quoteId: quote.id,
    );
    if (!mounted) return;
    _showMessage('Compra actualizada.');
  }

  Future<void> _approveQuoteFromCard(SupplierQuote quote) async {
    final actor = _snapshot?.actor;
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
      final repository = ref.read(purchaseOrderRepositoryProvider);
      final resolvedOrders = _resolveOrdersForQuoteMutation(quote.orderIds);
      late final SupplierQuoteMutationResult mutation;
      if (useManualOrderRefreshOnWindowsRelease) {
        mutation = await repository.approveSupplierQuoteWithResolvedOrders(
          quote: quote,
          actor: actor,
          relatedOrders: resolvedOrders,
        );
      } else {
        await repository.approveSupplierQuote(
          quote: quote,
          actor: actor,
        );
        mutation = SupplierQuoteMutationResult(
          quote: _buildApprovedQuoteForSnapshot(
            quote: quote,
            actor: actor,
          ),
          updatedOrders: const <PurchaseOrder>[],
        );
      }
      if (!useManualOrderRefreshOnWindowsRelease) {
        refreshOrderModuleTransitionData(
          ref,
          quoteId: quote.id,
          orderIds: quote.orderIds,
        );
        await _refreshDashboardSnapshotForOrders(
          clearSelection: false,
          upsertQuote: mutation.quote,
          touchedOrderIds: quote.orderIds,
          resolvedOrders: mutation.updatedOrders,
        );
      } else {
        _commitResolvedDashboardMutation(
          clearSelection: false,
          upsertQuote: mutation.quote,
          resolvedOrders: mutation.updatedOrders,
        );
      }
      refreshQuoteWorkflowCounts(
        ref,
        quoteId: quote.id,
      );
      if (!mounted) return;
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
    final actor = _snapshot?.actor;
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
      final repository = ref.read(purchaseOrderRepositoryProvider);
      final resolvedOrders = _resolveOrdersForQuoteMutation(quote.orderIds);
      late final SupplierQuoteMutationResult mutation;
      if (useManualOrderRefreshOnWindowsRelease) {
        mutation = await repository.rejectSupplierQuoteWithResolvedOrders(
          quote: quote,
          comment: controller.text,
          actor: actor,
          relatedOrders: resolvedOrders,
        );
      } else {
        await repository.rejectSupplierQuote(
          quote: quote,
          comment: controller.text,
          actor: actor,
        );
        mutation = SupplierQuoteMutationResult(
          quote: _buildRejectedQuoteForSnapshot(
            quote: quote,
            actor: actor,
            comment: controller.text,
          ),
          updatedOrders: const <PurchaseOrder>[],
        );
      }
      if (!useManualOrderRefreshOnWindowsRelease) {
        refreshOrderModuleTransitionData(
          ref,
          quoteId: quote.id,
          orderIds: quote.orderIds,
        );
        await _refreshDashboardSnapshotForOrders(
          clearSelection: false,
          upsertQuote: mutation.quote,
          touchedOrderIds: quote.orderIds,
          resolvedOrders: mutation.updatedOrders,
        );
      } else {
        _commitResolvedDashboardMutation(
          clearSelection: false,
          upsertQuote: mutation.quote,
          resolvedOrders: mutation.updatedOrders,
        );
      }
      refreshQuoteWorkflowCounts(
        ref,
        quoteId: quote.id,
      );
      if (!mounted) return;
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

  Future<void> _reloadDashboard({
    required bool clearSelection,
    bool preferIncremental = false,
  }) async {
    final loadToken = ++_loadToken;
    if (mounted) {
      setState(() {
        _isLoading = true;
        if (clearSelection) {
          _selectedSupplier = null;
          _linksController.clear();
          _comprasCommentController.clear();
        }
      });
    }

    try {
      final repository = ref.read(purchaseOrderRepositoryProvider);
      final currentSnapshot = preferIncremental ? _snapshot : null;
      late final AppUser? actor;
      late final List<PurchaseOrder> allOrders;
      late final List<SupplierQuote> quotes;

      if (currentSnapshot != null) {
        final existingOrderIds = currentSnapshot.allOrders
            .map((order) => order.id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false);
        final results = await Future.wait<Object?>([
          _resolveActor(),
          repository.fetchSupplierQuotes(),
          existingOrderIds.isEmpty
              ? Future<List<PurchaseOrder>>.value(const <PurchaseOrder>[])
              : repository.fetchOrdersByIds(existingOrderIds),
        ]);

        actor = results[0] as AppUser?;
        quotes = results[1]! as List<SupplierQuote>;
        final fetchedOrders = results[2]! as List<PurchaseOrder>;
        final fetchedOrderIds = fetchedOrders
            .map((order) => order.id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        final missingQuoteOrderIds = <String>{
          for (final quote in quotes)
            for (final orderId in quote.orderIds)
              if (orderId.trim().isNotEmpty && !fetchedOrderIds.contains(orderId.trim()))
                orderId.trim(),
        };
        if (missingQuoteOrderIds.isEmpty) {
          allOrders = fetchedOrders;
        } else {
          final missingOrders = await repository.fetchOrdersByIds(missingQuoteOrderIds);
          final mergedOrders = <String, PurchaseOrder>{
            for (final order in fetchedOrders) order.id: order,
            for (final order in missingOrders) order.id: order,
          };
          allOrders = mergedOrders.values.toList(growable: false);
        }
      } else {
        final results = await Future.wait<Object?>([
          _resolveActor(),
          repository.fetchAllOrders(),
          repository.fetchSupplierQuotes(),
        ]);
        actor = results[0] as AppUser?;
        allOrders = results[1]! as List<PurchaseOrder>;
        quotes = results[2]! as List<SupplierQuote>;
      }

      if (!mounted || loadToken != _loadToken) return;
      final completedOrders = _isDireccion
          ? const <PurchaseOrder>[]
          : _completedOrdersFromDashboardSnapshot(
              allOrders,
              quotes: quotes,
            );

      final snapshot = _DashboardSnapshot(
        actor: actor,
        branding: ref.read(currentBrandingProvider),
        completedOrders: List<PurchaseOrder>.unmodifiable(completedOrders),
        allOrders: List<PurchaseOrder>.unmodifiable(allOrders),
        quotes: List<SupplierQuote>.unmodifiable(quotes),
      );

      _commitDashboardSnapshot(
        snapshot,
        clearSelection: clearSelection,
      );
    } catch (error, stack) {
      if (!mounted || loadToken != _loadToken) return;
      setState(() {
        _loadError = reportError(
          error,
          stack,
          context: 'SupplierQuotes.reload',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshDashboardSnapshotForOrders({
    required bool clearSelection,
    SupplierQuote? upsertQuote,
    String? removeQuoteId,
    Iterable<String> touchedOrderIds = const <String>[],
    Iterable<PurchaseOrder> resolvedOrders = const <PurchaseOrder>[],
  }) async {
    final currentSnapshot = _snapshot;
    if (currentSnapshot == null) {
      await _reloadDashboard(clearSelection: clearSelection);
      return;
    }

    final orderIds = touchedOrderIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final repository = ref.read(purchaseOrderRepositoryProvider);
    final resolvedOrdersById = <String, PurchaseOrder>{
      for (final order in resolvedOrders) order.id: order,
    };
    final missingOrderIds = orderIds
        .where((orderId) => !resolvedOrdersById.containsKey(orderId))
        .toList(growable: false);
    final fetchedOrders = missingOrderIds.isEmpty
        ? const <PurchaseOrder>[]
        : await repository.fetchOrdersByIds(missingOrderIds);

    final nextOrdersById = <String, PurchaseOrder>{
      for (final order in currentSnapshot.allOrders) order.id: order,
    };
    for (final order in resolvedOrdersById.values) {
      nextOrdersById[order.id] = order;
    }
    for (final order in fetchedOrders) {
      nextOrdersById[order.id] = order;
    }

    final nextQuotesById = <String, SupplierQuote>{
      for (final quote in currentSnapshot.quotes) quote.id: quote,
    };
    final trimmedRemoveQuoteId = removeQuoteId?.trim() ?? '';
    if (trimmedRemoveQuoteId.isNotEmpty) {
      nextQuotesById.remove(trimmedRemoveQuoteId);
    }
    if (upsertQuote != null) {
      nextQuotesById[upsertQuote.id] = upsertQuote;
    }

    final nextAllOrders = nextOrdersById.values.toList(growable: false)
      ..sort(_sortOrdersByRecency);
    final nextQuotes = nextQuotesById.values.toList(growable: false)
      ..sort(_sortQuotesByRecency);
    final nextSnapshot = _DashboardSnapshot(
      actor: currentSnapshot.actor,
      branding: currentSnapshot.branding,
      completedOrders: List<PurchaseOrder>.unmodifiable(
        _isDireccion
            ? const <PurchaseOrder>[]
            : _completedOrdersFromDashboardSnapshot(
                nextAllOrders,
                quotes: nextQuotes,
              ),
      ),
      allOrders: List<PurchaseOrder>.unmodifiable(nextAllOrders),
      quotes: List<SupplierQuote>.unmodifiable(nextQuotes),
    );

    if (!mounted) return;
    _commitDashboardSnapshot(nextSnapshot, clearSelection: clearSelection);
  }

  void _commitResolvedDashboardMutation({
    required bool clearSelection,
    SupplierQuote? upsertQuote,
    String? removeQuoteId,
    Iterable<PurchaseOrder> resolvedOrders = const <PurchaseOrder>[],
  }) {
    final currentSnapshot = _snapshot;
    if (currentSnapshot == null) return;

    final nextOrdersById = <String, PurchaseOrder>{
      for (final order in currentSnapshot.allOrders) order.id: order,
    };
    for (final order in resolvedOrders) {
      nextOrdersById[order.id] = order;
    }

    final nextQuotesById = <String, SupplierQuote>{
      for (final quote in currentSnapshot.quotes) quote.id: quote,
    };
    final trimmedRemoveQuoteId = removeQuoteId?.trim() ?? '';
    if (trimmedRemoveQuoteId.isNotEmpty) {
      nextQuotesById.remove(trimmedRemoveQuoteId);
    }
    if (upsertQuote != null) {
      nextQuotesById[upsertQuote.id] = upsertQuote;
    }

    final nextAllOrders = nextOrdersById.values.toList(growable: false)
      ..sort(_sortOrdersByRecency);
    final nextQuotes = nextQuotesById.values.toList(growable: false)
      ..sort(_sortQuotesByRecency);
    final nextSnapshot = _DashboardSnapshot(
      actor: currentSnapshot.actor,
      branding: currentSnapshot.branding,
      completedOrders: List<PurchaseOrder>.unmodifiable(
        _isDireccion
            ? const <PurchaseOrder>[]
            : _completedOrdersFromDashboardSnapshot(
                nextAllOrders,
                quotes: nextQuotes,
              ),
      ),
      allOrders: List<PurchaseOrder>.unmodifiable(nextAllOrders),
      quotes: List<SupplierQuote>.unmodifiable(nextQuotes),
    );

    if (!mounted) return;
    _commitDashboardSnapshot(nextSnapshot, clearSelection: clearSelection);
  }

  List<PurchaseOrder> _resolveOrdersForQuoteMutation(Iterable<String> orderIds) {
    final snapshot = _snapshot;
    if (snapshot == null) return const <PurchaseOrder>[];
    final ids = orderIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return const <PurchaseOrder>[];
    return [
      for (final order in snapshot.allOrders)
        if (ids.contains(order.id)) order,
    ];
  }

  void _commitDashboardSnapshot(
    _DashboardSnapshot snapshot, {
    required bool clearSelection,
  }) {
    _applySelectionAfterReload(snapshot, clearSelection: clearSelection);
    setState(() {
      _snapshot = snapshot;
      _loadError = null;
      _isLoading = false;
    });
  }

  Future<AppUser?> _resolveActor() async {
    final current = ref.read(currentUserProfileProvider).valueOrNull;
    if (current != null) return current;
    return ref.read(currentUserProfileProvider.future);
  }

  void _applySelectionAfterReload(
    _DashboardSnapshot snapshot, {
    required bool clearSelection,
  }) {
    if (_isDireccion) return;

    final filteredQuotes = _withoutDraftQuotes(snapshot.quotes);
    final blockedQuoteItemKeys = _buildBlockedQuoteItemKeys(snapshot.quotes);
    final editableQuotes = filteredQuotes
        .where((quote) => quote.status == SupplierQuoteStatus.rejected)
        .toList(growable: false);
    final supplierOptions = _supplierOptions(
      snapshot.completedOrders,
      blockedQuoteItemKeys: blockedQuoteItemKeys,
    );

    if (clearSelection) {
      _selectedSupplier = null;
      _linksController.clear();
      _comprasCommentController.clear();
      return;
    }

    final nextSupplier = supplierOptions.contains(_selectedSupplier)
        ? _selectedSupplier
        : (supplierOptions.length == 1 ? supplierOptions.first : null);
    _selectedSupplier = nextSupplier;

    final cachedDraft = nextSupplier == null
        ? null
        : SessionDraftStore.supplierDashboard(nextSupplier);
    _linksController.text = cachedDraft?.links.join('\n') ?? '';
    _comprasCommentController.text = (cachedDraft?.comprasComment ?? '').trim();
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
    _persistSupplierDashboardDraft();
  }

  void _persistSupplierDashboardDraft() {
    final supplier = _selectedSupplier?.trim() ?? '';
    if (supplier.isEmpty) return;
    final links = _parseLinks(_linksController.text);
    final comprasComment = _comprasCommentController.text.trim();
    if (links.isEmpty && comprasComment.isEmpty) {
      SessionDraftStore.clearSupplierDashboard(supplier);
      return;
    }
    SessionDraftStore.saveSupplierDashboard(
      supplier,
      SupplierDashboardDraft(
        links: links,
        comprasComment: comprasComment,
      ),
    );
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

}

class _DashboardSnapshot {
  const _DashboardSnapshot({
    required this.actor,
    required this.branding,
    required this.completedOrders,
    required this.allOrders,
    required this.quotes,
  });

  final AppUser? actor;
  final CompanyBranding branding;
  final List<PurchaseOrder> completedOrders;
  final List<PurchaseOrder> allOrders;
  final List<SupplierQuote> quotes;
}

class _QuoteEditAction {
  const _QuoteEditAction._({
    required this.kind,
    this.order,
  });

  const _QuoteEditAction.links() : this._(kind: _QuoteEditActionKind.links);

  const _QuoteEditAction.order(PurchaseOrder order)
      : this._(kind: _QuoteEditActionKind.order, order: order);

  final _QuoteEditActionKind kind;
  final PurchaseOrder? order;
}

enum _QuoteEditActionKind { links, order }

class _RejectedQuoteActionsSheet extends StatelessWidget {
  const _RejectedQuoteActionsSheet({
    required this.quote,
    required this.relatedOrders,
  });

  final SupplierQuote quote;
  final List<PurchaseOrder> relatedOrders;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editar compra rechazada',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Mientras esta agrupacion exista, sus items quedan bloqueados para evitar duplicados. Puedes editar links o ajustar datos por orden sin desarmarla.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, const _QuoteEditAction.links()),
              icon: const Icon(Icons.link),
              label: const Text('Editar links y comentario'),
            ),
            if (relatedOrders.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Editar datos por orden',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final order in relatedOrders) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(order.id),
                  subtitle: Text('${order.requesterName} | ${order.areaName}'),
                  trailing: FilledButton.tonal(
                    onPressed: () =>
                        Navigator.pop(context, _QuoteEditAction.order(order)),
                    child: const Text('Editar datos'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DetachedDashboardActionScreen<T> extends StatefulWidget {
  const _DetachedDashboardActionScreen({
    required this.title,
    required this.progressLabel,
    required this.action,
  });

  final String title;
  final String progressLabel;
  final Future<T> Function() action;

  @override
  State<_DetachedDashboardActionScreen<T>> createState() =>
      _DetachedDashboardActionScreenState<T>();
}

class _DetachedDashboardActionScreenState<T>
    extends State<_DetachedDashboardActionScreen<T>> {
  bool _running = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _run();
    });
  }

  Future<void> _run() async {
    if (!_running) {
      setState(() {
        _running = true;
        _errorMessage = null;
      });
    }
    try {
      final result = await widget.action();
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error, stack) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _errorMessage = reportError(
          error,
          stack,
          context: 'SupplierQuotes.detachedAction',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _running
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      widget.progressLabel,
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _errorMessage ?? 'No se pudo completar la accion.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _run,
                      child: const Text('Reintentar'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

SupplierQuote _buildApprovedQuoteForSnapshot({
  required SupplierQuote quote,
  required AppUser actor,
}) {
  final now = DateTime.now();
  return SupplierQuote(
    id: quote.id,
    folio: quote.folio,
    supplier: quote.supplier,
    items: quote.items,
    status: SupplierQuoteStatus.approved,
    links: quote.links,
    facturaLinks: quote.facturaLinks,
    paymentLinks: quote.paymentLinks,
    createdAt: quote.createdAt,
    updatedAt: now,
    comprasComment: quote.comprasComment,
    processedByName: quote.processedByName,
    processedByArea: quote.processedByArea,
    sentToDireccionAt: quote.sentToDireccionAt,
    approvedAt: now,
    approvedByName: actor.name,
    approvedByArea: actor.areaDisplay,
    rejectionComment: null,
    rejectedAt: null,
    rejectedByName: null,
    rejectedByArea: null,
    version: quote.version + 1,
  );
}

SupplierQuote _buildRejectedQuoteForSnapshot({
  required SupplierQuote quote,
  required AppUser actor,
  required String comment,
}) {
  final now = DateTime.now();
  final trimmedComment = comment.trim();
  return SupplierQuote(
    id: quote.id,
    folio: quote.folio,
    supplier: quote.supplier,
    items: quote.items,
    status: SupplierQuoteStatus.rejected,
    links: quote.links,
    facturaLinks: quote.facturaLinks,
    paymentLinks: quote.paymentLinks,
    createdAt: quote.createdAt,
    updatedAt: now,
    comprasComment: quote.comprasComment,
    processedByName: quote.processedByName,
    processedByArea: quote.processedByArea,
    sentToDireccionAt: quote.sentToDireccionAt,
    approvedAt: null,
    approvedByName: null,
    approvedByArea: null,
    rejectionComment: trimmedComment.isEmpty ? null : trimmedComment,
    rejectedAt: now,
    rejectedByName: actor.name,
    rejectedByArea: actor.areaDisplay,
    version: quote.version + 1,
  );
}

SupplierQuote _rebuildEditableQuote({
  required SupplierQuote quote,
  required List<PurchaseOrder> orders,
  required List<String> links,
  String? comprasComment,
}) {
  final ordersById = {
    for (final order in orders) order.id: order,
  };
  final supplierCandidates = <String>{};
  final refs = <SupplierQuoteItemRef>[];

  for (final ref in quote.items) {
    final order = ordersById[ref.orderId];
    if (order == null) {
      refs.add(ref);
      continue;
    }
    PurchaseOrderItem? matchingItem;
    for (final candidate in order.items) {
      if (candidate.line == ref.line) {
        matchingItem = candidate;
        break;
      }
    }
    if (matchingItem == null) {
      refs.add(ref);
      continue;
    }
    final supplier = (matchingItem.supplier ?? '').trim();
    if (supplier.isNotEmpty) {
      supplierCandidates.add(supplier);
    }
    refs.add(
      SupplierQuoteItemRef(
        orderId: ref.orderId,
        orderFolio: ref.orderFolio ?? ref.orderId,
        line: matchingItem.line,
        description: matchingItem.description,
        quantity: matchingItem.quantity,
        unit: matchingItem.unit,
        partNumber: matchingItem.partNumber,
        amount: matchingItem.budget ?? ref.amount,
      ),
    );
  }

  final normalizedSupplier = supplierCandidates.length == 1
      ? supplierCandidates.first
      : quote.supplier;

  return SupplierQuote(
    id: quote.id,
    folio: quote.folio,
    supplier: normalizedSupplier,
    items: refs,
    status: quote.status,
    links: links,
    facturaLinks: quote.facturaLinks,
    paymentLinks: quote.paymentLinks,
    createdAt: quote.createdAt,
    updatedAt: DateTime.now(),
    comprasComment: comprasComment,
    processedByName: quote.processedByName,
    processedByArea: quote.processedByArea,
    sentToDireccionAt: quote.sentToDireccionAt,
    approvedAt: quote.approvedAt,
    approvedByName: quote.approvedByName,
    approvedByArea: quote.approvedByArea,
    rejectionComment: quote.rejectionComment,
    rejectedAt: quote.rejectedAt,
    rejectedByName: quote.rejectedByName,
    rejectedByArea: quote.rejectedByArea,
    version: quote.version,
  );
}

int _sortOrdersByRecency(PurchaseOrder left, PurchaseOrder right) {
  final leftTime =
      (left.updatedAt ?? left.createdAt)?.millisecondsSinceEpoch ?? 0;
  final rightTime =
      (right.updatedAt ?? right.createdAt)?.millisecondsSinceEpoch ?? 0;
  return rightTime.compareTo(leftTime);
}

int _sortQuotesByRecency(SupplierQuote left, SupplierQuote right) {
  final leftTime =
      (left.updatedAt ?? left.createdAt)?.millisecondsSinceEpoch ?? 0;
  final rightTime =
      (right.updatedAt ?? right.createdAt)?.millisecondsSinceEpoch ?? 0;
  return rightTime.compareTo(leftTime);
}

List<PurchaseOrder> _completedOrdersFromDashboardSnapshot(
  List<PurchaseOrder> allOrders, {
  required List<SupplierQuote> quotes,
}) {
  final rejectedOrderIds = <String>{
    for (final quote in quotes)
      if (quote.status == SupplierQuoteStatus.rejected) ...quote.orderIds,
  };
  return allOrders
      .where(
        (order) =>
            order.status == PurchaseOrderStatus.dataComplete ||
            rejectedOrderIds.contains(order.id),
      )
      .toList(growable: false);
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
    this.onEdit,
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
  final ValueChanged<SupplierQuote>? onEdit;
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
              onEdit: onEdit == null ? null : () => onEdit!(quote),
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
    this.onEdit,
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
  final VoidCallback? onEdit;
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
                  onPressed: onEdit,
                  child: const Text('Editar'),
                ),
                OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Desarmar'),
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

class _QuoteSendState {
  const _QuoteSendState({
    this.canSend = false,
    this.message =
        'Completa las compras pendientes para enviar a autorizacion de pago.',
  });

  final bool canSend;
  final String message;
}

List<SupplierQuote> _withoutDraftQuotes(List<SupplierQuote> quotes) {
  return quotes
      .where((quote) => quote.status != SupplierQuoteStatus.draft)
      .toList(growable: false);
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
  required Set<String> selectedQuoteItemKeys,
  required Set<String> blockedQuoteItemKeys,
}) {
  final pendingOrders = <_PendingDashboardOrder>[];
  for (final order in allOrders) {
    if (order.status != PurchaseOrderStatus.dataComplete) continue;
    final pendingItems = _pendingQuoteItemsCount(
      order,
      blockedQuoteItemKeys: blockedQuoteItemKeys,
    );
    if (pendingItems <= 0) continue;
    if (_shouldHidePendingDashboardOrderForSelectedSupplier(
      order: order,
      selectedSupplier: selectedSupplier,
      selectedQuoteItemKeys: selectedQuoteItemKeys,
      blockedQuoteItemKeys: blockedQuoteItemKeys,
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
  required Set<String> selectedQuoteItemKeys,
  required Set<String> blockedQuoteItemKeys,
}) {
  final supplier = selectedSupplier?.trim() ?? '';
  if (supplier.isEmpty) return false;

  var hasPendingItemsForSelectedSupplier = false;
  var hasPendingItemsForOtherSuppliers = false;

  for (final item in order.items) {
    if (blockedQuoteItemKeys.contains(_quoteItemKey(order.id, item.line))) {
      continue;
    }
    final itemSupplier = (item.supplier ?? '').trim();
    final amount = item.budget ?? 0;
    final missingAssignment = itemSupplier.isEmpty || amount <= 0;
    final itemKey = _quoteItemKey(order.id, item.line);
    final quoteId = item.quoteId?.trim() ?? '';
    final missingQuote =
        quoteId.isEmpty ||
        selectedQuoteItemKeys.contains(itemKey) ||
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
  {required Set<String> blockedQuoteItemKeys,}
) {
  final suppliers = <String>{};
  for (final order in orders) {
    for (final item in order.items) {
      final itemKey = _quoteItemKey(order.id, item.line);
      if (blockedQuoteItemKeys.contains(itemKey)) {
        continue;
      }
      final supplier = (item.supplier ?? '').trim();
      final amount = item.budget ?? 0;
      if (supplier.isEmpty || amount <= 0) continue;
      if (!_supplierHasDashboardItems(
        orders: orders,
        supplier: supplier,
        editableQuoteItemKeys: const <String>{},
        blockedQuoteItemKeys: blockedQuoteItemKeys,
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
  required Set<String> editableQuoteItemKeys,
  required Set<String> blockedQuoteItemKeys,
}) {
  return _collectSupplierItems(
    orders: orders,
    supplier: supplier,
    editableQuoteItemKeys: editableQuoteItemKeys,
    blockedQuoteItemKeys: blockedQuoteItemKeys,
  ).isNotEmpty;
}

List<_SupplierGroupedItem> _collectSupplierItems({
  required List<PurchaseOrder> orders,
  required String supplier,
  required Set<String> editableQuoteItemKeys,
  required Set<String> blockedQuoteItemKeys,
}) {
  final items = <_SupplierGroupedItem>[];
  for (final order in orders) {
    for (final item in order.items) {
      final itemKey = _quoteItemKey(order.id, item.line);
      if (blockedQuoteItemKeys.contains(itemKey) &&
          !editableQuoteItemKeys.contains(itemKey)) {
        continue;
      }
      final itemSupplier = (item.supplier ?? '').trim();
      final amount = item.budget ?? 0;
      final quoteId = item.quoteId?.trim();
      final include =
          itemSupplier == supplier &&
          amount > 0 &&
          (editableQuoteItemKeys.contains(itemKey) ||
              quoteId == null ||
              quoteId.isEmpty ||
              editableQuoteItemKeys.contains(itemKey) ||
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
    if (useManualOrderRefreshOnWindowsRelease) {
      return null;
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

Set<String> _buildBlockedQuoteItemKeys(List<SupplierQuote> quotes) {
  final keys = <String>{};
  for (final quote in quotes) {
    for (final ref in quote.items) {
      keys.add(_quoteItemKey(ref.orderId, ref.line));
    }
  }
  return keys;
}

String _quoteItemKey(String orderId, int line) => '${orderId.trim()}#$line';

Set<String> _quoteItemKeysFromRefs(List<SupplierQuoteItemRef> refs) {
  return {
    for (final ref in refs) _quoteItemKey(ref.orderId, ref.line),
  };
}

bool _orderNeedsMoreQuotes(PurchaseOrder order) {
  return _pendingQuoteItemsCount(order) > 0;
}

String _money(num value) {
  return '\$${value.toDouble().toStringAsFixed(2)}';
}

int _pendingQuoteItemsCount(
  PurchaseOrder order, {
  Set<String> blockedQuoteItemKeys = const <String>{},
}) {
  var pending = 0;
  for (final item in order.items) {
    if (blockedQuoteItemKeys.contains(_quoteItemKey(order.id, item.line))) {
      continue;
    }
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


bool _canAuthorizeQuote(AppUser actor) {
  return isAdminRole(actor.role) || isDireccionGeneralLabel(actor.areaDisplay);
}
