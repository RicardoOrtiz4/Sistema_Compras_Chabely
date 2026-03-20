import 'package:flutter/material.dart';
import 'package:sistema_compras/core/constants.dart';

import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/features/orders/application/create_order_controller.dart';
import 'package:sistema_compras/features/orders/presentation/preview/order_pdf_builder.dart';

class OrderPreviewWidget extends StatelessWidget {
  const OrderPreviewWidget({required this.data, super.key});

  final OrderPdfData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeaderCard(data: data),
        const SizedBox(height: 12),
        _MetaCard(data: data),
        const SizedBox(height: 12),
        _ItemsCard(data: data),
        if (data.observations.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Observaciones',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(data.observations),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _SignaturesCard(data: data),
        const SizedBox(height: 12),
        Text(
          'Vista previa rápida. El PDF final se genera al enviar.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.data});

  final OrderPdfData data;

  @override
  Widget build(BuildContext context) {
    final branding = data.branding;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Image.asset(branding.logoAsset, height: 56, fit: BoxFit.contain),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    branding.pdfHeaderLine1,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    branding.pdfHeaderLine2,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    branding.pdfTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.data});

  final OrderPdfData data;

  @override
  Widget build(BuildContext context) {
    final urgentJustification = (data.urgentJustification ?? '').trim();
    final urgencyValue =
        data.urgency == PurchaseOrderUrgency.urgente &&
            urgentJustification.isNotEmpty
        ? '${data.urgency.label} - $urgentJustification'
        : data.urgency.label;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetaRow(
              label: 'Solicitante / Area',
              value: '${data.requesterName} | ${data.areaName}',
            ),
            _MetaRow(label: 'Urgencia', value: urgencyValue),
            _MetaRow(label: 'Fecha', value: data.createdAt.toFullDateTime()),
          ],
        ),
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.data});

  final OrderPdfData data;

  @override
  Widget build(BuildContext context) {
    final items = data.items;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Artículos (${items.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...items.map((item) => _ItemTile(item: item)),
          ],
        ),
      ),
    );
  }
}

class _SignaturesCard extends StatelessWidget {
  const _SignaturesCard({required this.data});

  final OrderPdfData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Firmas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _MetaRow(label: 'Solicito', value: data.requesterName),
            _MetaRow(
              label: 'Proceso',
              value: _signatureValue(data.processedByName, data.processedByArea),
            ),
            _MetaRow(
              label: 'Autorizo',
              value: _signatureValue(
                data.direccionGeneralName ?? data.comprasReviewerName,
                data.direccionGeneralArea ?? data.comprasReviewerArea,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _signatureValue(String? name, String? area) {
    final trimmedName = (name ?? '').trim();
    final trimmedArea = (area ?? '').trim();
    if (trimmedName.isEmpty && trimmedArea.isEmpty) return '-';
    if (trimmedArea.isEmpty) return trimmedName;
    if (trimmedName.isEmpty) return trimmedArea;
    return '$trimmedName | $trimmedArea';
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final OrderItemDraft item;

  @override
  Widget build(BuildContext context) {
    final customer = (item.customer ?? '').trim();
    final supplier = (item.supplier ?? '').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Artículo ${item.line}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                item.description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _MetaChip(label: 'Piezas', value: item.pieces.toString()),
                  _MetaChip(label: 'Unidad', value: item.unit),
                  if (item.partNumber.trim().isNotEmpty)
                    _MetaChip(label: 'No. parte', value: item.partNumber),
                  if (customer.isNotEmpty)
                    _MetaChip(label: 'Cliente', value: customer),
                  if (supplier.isNotEmpty)
                    _MetaChip(label: 'Proveedor', value: supplier),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}
