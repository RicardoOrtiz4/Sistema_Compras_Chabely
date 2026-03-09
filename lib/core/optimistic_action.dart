import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/legacy.dart';

import 'package:sistema_compras/core/error_reporter.dart';

enum OptimisticActionStatus { pending, failed }

class OptimisticActionEntry {
  const OptimisticActionEntry({
    required this.id,
    required this.label,
    required this.status,
    required this.action,
    required this.startedAt,
    this.successMessage,
    this.errorContext,
  });

  final String id;
  final String label;
  final OptimisticActionStatus status;
  final Future<void> Function() action;
  final DateTime startedAt;
  final String? successMessage;
  final String? errorContext;

  OptimisticActionEntry copyWith({
    OptimisticActionStatus? status,
  }) {
    return OptimisticActionEntry(
      id: id,
      label: label,
      status: status ?? this.status,
      action: action,
      startedAt: startedAt,
      successMessage: successMessage,
      errorContext: errorContext,
    );
  }
}

class OptimisticActionController
    extends StateNotifier<List<OptimisticActionEntry>> {
  OptimisticActionController() : super(const []);

  String start({
    required String label,
    required Future<void> Function() action,
    String? successMessage,
    String? errorContext,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final entry = OptimisticActionEntry(
      id: id,
      label: label,
      status: OptimisticActionStatus.pending,
      action: action,
      startedAt: DateTime.now(),
      successMessage: successMessage,
      errorContext: errorContext,
    );
    state = [...state, entry];
    return id;
  }

  void complete(String id) {
    state = state.where((entry) => entry.id != id).toList();
  }

  void fail(String id) {
    state = [
      for (final entry in state)
        if (entry.id == id)
          entry.copyWith(status: OptimisticActionStatus.failed)
        else
          entry,
    ];
  }

  void remove(String id) {
    state = state.where((entry) => entry.id != id).toList();
  }
}

final optimisticActionsProvider =
    StateNotifierProvider<OptimisticActionController, List<OptimisticActionEntry>>(
  (ref) => OptimisticActionController(),
);

Future<void> runOptimisticAction({
  required BuildContext context,
  required Future<void> Function() action,
  VoidCallback? onNavigate,
  String? pendingLabel,
  String? successMessage,
  String? errorContext,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final controller = container.read(optimisticActionsProvider.notifier);
  final label = pendingLabel ?? successMessage ?? 'Sincronizando cambios...';
  final id = controller.start(
    label: label,
    action: action,
    successMessage: successMessage,
    errorContext: errorContext,
  );
  onNavigate?.call();
  try {
    await action();
    controller.complete(id);
    if (successMessage != null && messenger != null) {
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    }
  } catch (error, stack) {
    controller.fail(id);
    final message = reportError(
      error,
      stack,
      context: errorContext ?? 'OptimisticAction',
    );
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

class OptimisticSyncBanner extends ConsumerWidget {
  const OptimisticSyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(optimisticActionsProvider);
    if (entries.isEmpty) return const SizedBox.shrink();

    final pending = entries
        .where((entry) => entry.status == OptimisticActionStatus.pending)
        .toList();
    final failed = entries
        .where((entry) => entry.status == OptimisticActionStatus.failed)
        .toList();

    final hasFailed = failed.isNotEmpty;
    final pendingCount = pending.length;
    final failedCount = failed.length;

    final message = hasFailed
        ? 'No se pudo sincronizar $failedCount cambio(s).'
            '${pendingCount > 0 ? ' Enviando $pendingCount...' : ''}'
        : 'Sincronizando $pendingCount cambio(s)...';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Material(
          elevation: 2,
          color: hasFailed ? Colors.red.shade50 : Colors.blueGrey.shade50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  hasFailed ? Icons.error_outline : Icons.sync,
                  color: hasFailed ? Colors.red.shade700 : Colors.blueGrey.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: hasFailed ? Colors.red.shade800 : Colors.blueGrey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (hasFailed)
                  TextButton(
                    onPressed: () {
                      final controller =
                          ref.read(optimisticActionsProvider.notifier);
                      for (final entry in failed) {
                        controller.remove(entry.id);
                        unawaited(runOptimisticAction(
                          context: context,
                          action: entry.action,
                          pendingLabel: entry.label,
                          successMessage: entry.successMessage,
                          errorContext: entry.errorContext,
                        ));
                      }
                    },
                    child: const Text('Reintentar'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
