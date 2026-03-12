import 'package:flutter/material.dart';

import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/features/orders/presentation/compras/cotizaciones_dashboard_screen.dart';

class DireccionOrdersScreen extends StatelessWidget {
  const DireccionOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Direccion General'),
      ),
      body: CotizacionesDashboardScreen(
        mode: CotizacionesDashboardMode.direccion,
        embedded: true,
        onOpenOrder: (orderId) => guardedPdfPush(context, '/orders/$orderId/pdf'),
      ),
    );
  }
}
