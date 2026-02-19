import 'package:flutter/material.dart';

@Deprecated('Pantalla eliminada: órdenes autorizadas.')
class AuthorizedOrdersScreen extends StatelessWidget {
  const AuthorizedOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Pantalla eliminada.'),
      ),
    );
  }
}

@Deprecated('Pantalla eliminada: órdenes autorizadas.')
class AuthorizedOrderDetailScreen extends StatelessWidget {
  const AuthorizedOrderDetailScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Pantalla eliminada.'),
      ),
    );
  }
}
