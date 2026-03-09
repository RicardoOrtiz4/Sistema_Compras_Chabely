import 'package:flutter/material.dart';

import 'package:sistema_compras/core/navigation_guard.dart';
import 'package:sistema_compras/core/widgets/info_action.dart';
import 'package:sistema_compras/features/orders/presentation/compras/cotizaciones_dashboard_screen.dart';

class DireccionOrdersScreen extends StatelessWidget {
  const DireccionOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Direccion General'),
        actions: [
          infoAction(
            context,
            title: 'Direccion General',
            message:
                'Revisa las cotizaciones enviadas desde el dashboard.\n'
                'Abre una orden para decidir.\n'
                'Las agrupaciones muestran su link asignado.',
          ),
        ],
      ),
      body: CotizacionesDashboardScreen(
        mode: CotizacionesDashboardMode.direccion,
        embedded: true,
        onOpenOrder: (orderId) => guardedPush(context, '/orders/$orderId/pdf'),
      ),
    );
  }
}
