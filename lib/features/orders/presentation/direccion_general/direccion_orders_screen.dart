import 'package:flutter/material.dart';

import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/features/orders/presentation/compras/supplier_quotes_dashboard_screen.dart';

class DireccionOrdersScreen extends StatelessWidget {
  const DireccionOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CotizacionesDashboardScreen(
      mode: CotizacionesDashboardMode.direccion,
      onOpenOrder: (orderId) => guardedPdfPush(context, '/orders/$orderId/pdf'),
    );
  }
}
