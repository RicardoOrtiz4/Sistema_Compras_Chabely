import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/company_branding.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/orders/application/order_providers.dart';
import 'package:sistema_compras/features/orders/domain/purchase_order.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_mapper.dart';
import 'package:sistema_compras/features/orders/presentation/shared/order_search.dart';

class RejectedOrdersScreen extends ConsumerStatefulWidget {
  const RejectedOrdersScreen({super.key});

  @override
  ConsumerState<RejectedOrdersScreen> createState() =>
      _RejectedOrdersScreenState();
}

class _RejectedOrdersScreenState extends ConsumerState<RejectedOrdersScreen> {
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(rejectedOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Órdenes rechazadas')),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No hay órdenes rechazadas.'));
          }

          final filtered = orders
              .where((order) => orderMatchesSearch(order, _searchQuery))
              .toList();

          final branding = ref.read(currentBrandingProvider);
          // Prefetch para que los thumbnails / PDFs carguen más rápido.
          prefetchOrderPdfsForOrders(filtered, branding: branding);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText:
                        'Buscar por folio (000001), solicitante, cliente, fecha...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Las limpiezas se ejecutan de forma anual mediante un programa externo. '
                  'Considera respaldar las órdenes rechazadas si las necesitas.',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No hay órdenes con ese filtro.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = filtered[index];
                          return _RejectedOrderCard(order: order);
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error: ${reportError(error, stack, context: 'RejectedOrdersScreen')}',
          ),
        ),
      ),
    );
  }
}

class _RejectedOrderCard extends ConsumerWidget {
  const _RejectedOrderCard({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pdfRoute = '/orders/${order.id}/pdf';
    final copyRoute =
        '/orders/create?copyFromId=${Uri.encodeComponent(order.id)}';

    final reason = (order.lastReturnReason ?? '').trim();
    final maxCorrectionsReached = order.returnCount >= _maxCorrections;

    final eventsAsync = ref.watch(orderEventsProvider(order.id));
    final rejectedBy = eventsAsync.maybeWhen(
      data: (events) {
        PurchaseOrderEvent? lastReturn;
        for (final event in events) {
          if (event.type == 'return') {
            lastReturn = event; // quedarnos con el último
          }
        }
        return _rejectedByLabel(lastReturn?.byRole);
      },
      orElse: () => 'Compras',
    );

    return Card(
      child: InkWell(
        onTap: () => context.push(pdfRoute),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Chip(label: Text('Rechazada por $rejectedBy')),
                ],
              ),
              const SizedBox(height: 8),
              Text('Motivo: ${reason.isEmpty ? 'Sin comentario' : reason}'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (maxCorrectionsReached)
                      OutlinedButton.icon(
                        onPressed: () => context.push(copyRoute),
                        icon: const Icon(Icons.content_copy_outlined),
                        label: const Text('Volver a generar'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _rejectedByLabel(String? rawRole) {
  final trimmed = (rawRole ?? '').trim();
  if (trimmed.isEmpty) {
    return 'Compras';
  }

  final normalized = normalizeAreaLabel(trimmed);

  if (isComprasLabel(normalized)) {
    return 'Compras';
  }
  if (isDireccionGeneralLabel(normalized)) {
    return 'Dirección General';
  }

  return normalized;
}

const int _maxCorrections = 3;
