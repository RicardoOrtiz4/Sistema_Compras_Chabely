import 'package:flutter/material.dart';

Widget infoAction(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return Tooltip(
    message: 'Informacion',
    child: IconButton(
      icon: const Icon(Icons.info_outline),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _InfoScreen(title: title, message: message),
          ),
        );
      },
    ),
  );
}

class _InfoScreen extends StatelessWidget {
  const _InfoScreen({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informacion'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(title, style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
