import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/area_labels.dart';
import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserProfileProvider);
    final currentUser = currentUserAsync.value;
    final isAdmin = currentUser != null && isAdminRole(currentUser.role);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Administrar usuarios'),
        ),
        body: const Center(
          child: Text('No tienes permisos para ver esta pantalla.'),
        ),
      );
    }

    final usersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administrar usuarios'),
      ),
      body: usersAsync.when(
        data: (users) {
          if (users.isEmpty) {
            return const Center(
              child: Text(
                'No hay usuarios registrados.\nLas altas y bajas se hacen manualmente en Firebase Console.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Edicion interna'),
                    subtitle: Text(
                      'La app ya no crea ni elimina usuarios. Aqui solo se editan nombre visible, rol y area.',
                    ),
                  ),
                );
              }
              final user = users[index - 1];
              final roleKey = user.role.toLowerCase();
              final roleLabel = roleLabels[roleKey] ?? user.role;

              return Card(
                child: ListTile(
                  title: Text(user.name),
                  subtitle: Text(
                    'Rol: $roleLabel - Area: ${user.areaDisplay}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar rol y área',
                        onPressed: () =>
                            _showEditDialog(context, ref, user),
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
            'Error al cargar usuarios: ${reportError(error, stack, context: 'AdminUsersScreen')}',
          ),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    const roles = ['usuario', 'administrador'];
    final nameController = TextEditingController(text: user.name);

    final normalizedRole = user.role.toLowerCase();
    var selectedRole = normalizedRole == 'admin' ? 'administrador' : normalizedRole;
    if (!roles.contains(selectedRole)) selectedRole = 'usuario';

    final currentAreaId = user.areaId;
    final currentAreaName = user.areaDisplay;

    String? selectedAreaId = currentAreaId.trim().isEmpty ? null : currentAreaId;
    String? selectedAreaName = currentAreaName;

    String? nameError;
    String? areaError;
    bool isSaving = false;
    bool isSeeding = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, watchRef, _) {
            final areasAsync = watchRef.watch(areasProvider);

            return StatefulBuilder(
              builder: (context, setState) {
                final areas = areasAsync.value ?? const <AreaOption>[];

                final fallbackAreaId =
                    selectedRole == 'administrador' ? adminAreaId : currentAreaId;
                final fallbackAreaName =
                    selectedRole == 'administrador' ? adminAreaId : currentAreaName;

                final missingArea = fallbackAreaId.isNotEmpty &&
                    !areas.any((area) => area.id == fallbackAreaId);

                final areaOptions = _mergeAreas(
                  areas,
                  fallbackId: fallbackAreaId,
                  fallbackName: fallbackAreaName,
                );

                if (selectedRole == 'administrador' && fallbackAreaId.isNotEmpty) {
                  selectedAreaId = fallbackAreaId;
                  final area = areaOptions.firstWhere(
                    (item) => item.id == fallbackAreaId,
                    orElse: () => areaOptions.first,
                  );
                  selectedAreaName = area.name;
                } else if (areaOptions.isNotEmpty &&
                    !areaOptions.any((a) => a.id == selectedAreaId)) {
                  selectedAreaId = areaOptions.first.id;
                  selectedAreaName = areaOptions.first.name;
                }

                final areaLocked = selectedRole == 'administrador';

                final canSave = !isSaving &&
                    !isSeeding &&
                    areaOptions.isNotEmpty &&
                    !areasAsync.isLoading &&
                    !areasAsync.hasError;

                return AlertDialog(
                  title: const Text('Editar usuario'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: nameController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Nombre',
                            errorText: nameError,
                          ),
                          enabled: !isSaving,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedRole,
                          decoration: const InputDecoration(labelText: 'Rol'),
                          items: roles
                              .map(
                                (role) => DropdownMenuItem(
                                  value: role,
                                  child: Text(roleLabels[role] ?? role),
                                ),
                              )
                              .toList(),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() => selectedRole = value);
                                },
                        ),
                        const SizedBox(height: 12),
                        if (areasAsync.isLoading)
                          const SizedBox(height: 80, child: AppSplash(compact: true))
                        else if (areasAsync.hasError)
                          Text(
                            'Error al cargar áreas: ${reportError(areasAsync.error!, areasAsync.stackTrace, context: 'AdminUsersScreen')}',
                          )
                        else if (areaOptions.isEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('No hay áreas registradas.'),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: isSaving || isSeeding
                                    ? null
                                    : () async {
                                        final messenger =
                                            ScaffoldMessenger.of(dialogContext);
                                        setState(() => isSeeding = true);
                                        try {
                                          await ref
                                              .read(profileRepositoryProvider)
                                              .seedAreas();
                                          if (!dialogContext.mounted ||
                                              !messenger.mounted) {
                                            return;
                                          }
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text('Áreas creadas.'),
                                            ),
                                          );
                                        } catch (error, stack) {
                                          if (!dialogContext.mounted ||
                                              !messenger.mounted) {
                                            return;
                                          }
                                          _showErrorSnackBarWithMessenger(
                                            messenger,
                                            error,
                                            stack: stack,
                                            contextLabel:
                                                'AdminUsersScreen.seedAreas',
                                          );
                                        } finally {
                                          if (dialogContext.mounted) {
                                            setState(() => isSeeding = false);
                                          }
                                        }
                                      },
                                icon: isSeeding
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: AppSplash(compact: true, size: 16),
                                      )
                                    : const Icon(Icons.add_business_outlined),
                                label: Text(
                                  isSeeding
                                      ? 'Creando áreas...'
                                      : 'Crear áreas iniciales',
                                ),
                              ),
                            ],
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: selectedAreaId,
                            decoration: InputDecoration(
                              labelText: 'Área',
                              errorText: areaError,
                            ),
                            items: areaOptions.map((area) {
                              final label = missingArea && area.id == fallbackAreaId
                                  ? '${area.name} (no disponible)'
                                  : area.name;
                              return DropdownMenuItem(
                                value: area.id,
                                child: Text(label),
                              );
                            }).toList(),
                            onChanged: isSaving || areaLocked
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    final area = areaOptions.firstWhere(
                                      (item) => item.id == value,
                                      orElse: () => areaOptions.first,
                                    );
                                    setState(() {
                                      selectedAreaId = value;
                                      selectedAreaName = area.name;
                                    });
                                  },
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          isSaving ? null : () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: !canSave
                          ? null
                          : () async {
                              final navigator = Navigator.of(dialogContext);
                              final messenger =
                                  ScaffoldMessenger.of(dialogContext);
                              final name = nameController.text.trim();

                              final areaId = selectedRole == 'administrador'
                                  ? adminAreaId
                                  : (selectedAreaId ?? '');

                              var hasError = false;

                              if (name.isEmpty) {
                                nameError = 'Ingresa un nombre';
                                hasError = true;
                              } else {
                                nameError = null;
                              }

                              if (hasError) {
                                setState(() {});
                                return;
                              }

                              if (areaId.trim().isEmpty) {
                                setState(() => areaError = 'Selecciona un área');
                                return;
                              }

                              setState(() {
                                areaError = null;
                                isSaving = true;
                              });

                              try {
                                await ref
                                    .read(profileRepositoryProvider)
                                    .updateAdminEditableProfile(
                                      uid: user.id,
                                      name: name,
                                      role: selectedRole,
                                      areaId: areaId,
                                      areaName: selectedRole == 'administrador'
                                          ? adminAreaId
                                          : (selectedAreaName ?? ''),
                                    );
                                ref.invalidate(allUsersProvider);
                                ref.invalidate(currentUserProfileProvider);
                                if (!navigator.mounted) return;
                                navigator.pop();
                              } catch (error, stack) {
                                if (!dialogContext.mounted ||
                                    !messenger.mounted) {
                                  return;
                                }
                                setState(() => isSaving = false);
                                _showErrorSnackBarWithMessenger(
                                  messenger,
                                  error,
                                  stack: stack,
                                  contextLabel: 'AdminUsersScreen.updateUser',
                                );
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: AppSplash(compact: true, size: 20),
                            )
                          : const Text('Guardar'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    nameController.dispose();
  }

}
const adminAreaId = adminAreaLabel;

List<AreaOption> _mergeAreas(
  List<AreaOption> areas, {
  required String fallbackId,
  required String fallbackName,
}) {
  final merged = List<AreaOption>.from(areas);
  if (fallbackId.isEmpty) return merged;

  final exists = merged.any((area) => area.id == fallbackId);
  if (!exists) {
    merged.insert(0, AreaOption(id: fallbackId, name: fallbackName));
  }
  return merged;
}

const roleLabels = <String, String>{
  'admin': 'Administrador',
  'usuario': 'Usuario',
  'administrador': 'Administrador',
};

void _showErrorSnackBarWithMessenger(
  ScaffoldMessengerState messenger,
  Object error, {
  StackTrace? stack,
  String? contextLabel,
}) {
  final message = reportError(
    error,
    stack,
    context: contextLabel ?? 'AdminUsersScreen',
  );
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

