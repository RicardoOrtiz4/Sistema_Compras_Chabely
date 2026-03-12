import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/extensions.dart';
import 'package:sistema_compras/core/providers.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/partners/data/partner_repository.dart';

class PartnerManagementScreen extends ConsumerWidget {
  const PartnerManagementScreen({required this.type, super.key});

  final PartnerType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(
      type == PartnerType.supplier ? userSuppliersProvider : userClientsProvider,
    );

    final title = type == PartnerType.supplier
        ? 'Gestión de proveedores'
        : 'Gestión de clientes';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUpsertDialog(context, ref, type),
        icon: const Icon(Icons.add),
        label: Text('Nuevo ${type.label.toLowerCase()}'),
      ),
      body: partnersAsync.when(
        data: (partners) {
          if (partners.isEmpty) {
            return Center(
              child: Text('Sin ${type.pluralLabel.toLowerCase()} registrados.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: partners.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final partner = partners[index];
              final updatedAt = partner.updatedAt ?? partner.createdAt;
              final subtitle = updatedAt == null
                  ? null
                  : 'Actualizado: ${updatedAt.toFullDateTime()}';

              return Card(
                child: ListTile(
                  title: Text(partner.name),
                  subtitle: subtitle == null ? null : Text(subtitle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar',
                        onPressed: () => _showUpsertDialog(
                          context,
                          ref,
                          type,
                          entry: partner,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Eliminar',
                        color: Theme.of(context).colorScheme.error,
                        onPressed: () => _showDeleteDialog(
                          context,
                          ref,
                          type,
                          partner,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const AppSplash(),
        error: (error, stack) => Center(
          child: Text(
            'Error al cargar ${type.pluralLabel.toLowerCase()}: '
            '${reportError(error, stack, context: 'PartnerManagementScreen')}',
          ),
        ),
      ),
    );
  }
}

Future<void> _showUpsertDialog(
  BuildContext context,
  WidgetRef ref,
  PartnerType type, {
  PartnerEntry? entry,
}) async {
  final controller = TextEditingController(text: entry?.name ?? '');
  String? errorText;
  bool isSaving = false;

  final repo = ref.read(partnerRepositoryProvider);
  final uid = ref.read(currentUserIdProvider);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              entry == null ? 'Nuevo ${type.label}' : 'Editar ${type.label}',
            ),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: type.label,
                errorText: errorText,
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (errorText != null) setState(() => errorText = null);
              },
              enabled: !isSaving,
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = controller.text.trim();

                        if (name.isEmpty) {
                          setState(() => errorText = 'Nombre requerido');
                          return;
                        }

                        if (uid == null) {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Usuario no disponible.')),
                            );
                          }
                          return;
                        }

                        setState(() => isSaving = true);

                        try {
                          if (entry == null) {
                            await repo.createPartner(
                              uid: uid,
                              type: type,
                              name: name,
                            );
                          } else {
                            await repo.updatePartner(
                              uid: uid,
                              type: type,
                              id: entry.id,
                              name: name,
                            );
                          }

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (error, stack) {
                          if (dialogContext.mounted) {
                            final message = reportError(
                              error,
                              stack,
                              context: 'PartnerManagementScreen.save',
                            );
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text(message)),
                            );
                            setState(() => isSaving = false);
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: AppSplash(compact: true, size: 18),
                      )
                    : const Text('Guardar'),
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
}

Future<void> _showDeleteDialog(
  BuildContext context,
  WidgetRef ref,
  PartnerType type,
  PartnerEntry entry,
) async {
  bool isDeleting = false;

  final repo = ref.read(partnerRepositoryProvider);
  final uid = ref.read(currentUserIdProvider);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Eliminar ${type.label.toLowerCase()}'),
            content: Text('Se eliminará ${entry.name}.'),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: isDeleting
                    ? null
                    : () async {
                        if (uid == null) {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Usuario no disponible.')),
                            );
                          }
                          return;
                        }

                        setState(() => isDeleting = true);

                        try {
                          await repo.deletePartner(
                            uid: uid,
                            type: type,
                            id: entry.id,
                          );

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (error, stack) {
                          if (dialogContext.mounted) {
                            final message = reportError(
                              error,
                              stack,
                              context: 'PartnerManagementScreen.delete',
                            );
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text(message)),
                            );
                            setState(() => isDeleting = false);
                          }
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                icon: isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: AppSplash(compact: true, size: 18),
                      )
                    : const Icon(Icons.delete_outline),
                label: const Text('Eliminar'),
              ),
            ],
          );
        },
      );
    },
  );
}
