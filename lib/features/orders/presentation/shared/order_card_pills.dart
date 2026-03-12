import 'package:flutter/material.dart';

import 'package:sistema_compras/core/constants.dart';

class OrderFolioPill extends StatelessWidget {
  const OrderFolioPill({required this.folio, super.key});

  final String folio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        folio,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class OrderUrgencyPill extends StatelessWidget {
  const OrderUrgencyPill({required this.urgency, super.key});

  final PurchaseOrderUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final color = urgency.color(Theme.of(context).colorScheme);
    final brightness = ThemeData.estimateBrightnessForColor(color);
    final textColor = brightness == Brightness.dark ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        urgency.label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class OrderTagPill extends StatelessWidget {
  const OrderTagPill({
    required this.label,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    super.key,
  });

  final String label;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
