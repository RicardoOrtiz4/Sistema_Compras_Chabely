import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/constants.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
import 'package:sistema_compras/core/widgets/info_action.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserProfileProvider);
    final currentUser = currentUserAsync.value;
    final isAdmin = currentUser != null && isAdminRole(currentUser.role);
    final currentUserId = currentUser?.id;
    final scheme = Theme.of(context).colorScheme;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Administrar usuarios'),
          actions: [
            infoAction(
              context,
              title: 'Administrar usuarios',
              message:
                  'Gestiona cuentas, roles y areas.\n'
                  'Crear agrega un usuario nuevo.\n'
                  'Editar cambia rol y area.\n'
                  'Eliminar quita el acceso.',
            ),
          ],
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
        actions: [
          infoAction(
            context,
            title: 'Administrar usuarios',
            message:
                'Gestiona cuentas, roles y areas.\n'
                'Crear agrega un usuario nuevo.\n'
                'Editar cambia rol y area.\n'
                'Eliminar quita el acceso.',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Nuevo usuario'),
      ),
      body: usersAsync.when(
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('No hay usuarios registrados.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final user = users[index];
              final roleKey = user.role.toLowerCase();
              final roleLabel = roleLabels[roleKey] ?? user.role;
              final isSelf = currentUserId == user.id;

              return Card(
                child: ListTile(
                  title: Text(user.name),
                  subtitle: Text(
                    '${user.email}\nRol: $roleLabel - Área: ${user.areaDisplay}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar rol y área',
                        onPressed: () => _showEditDialog(context, ref, user),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: isSelf
                            ? 'No puedes eliminar tu usuario'
                            : 'Eliminar usuario',
                        color: isSelf ? null : scheme.error,
                        onPressed:
                            isSelf ? null : () => _showDeleteDialog(context, ref, user),
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

    final normalizedRole = user.role.toLowerCase();
    var selectedRole = normalizedRole == 'admin' ? 'administrador' : normalizedRole;
    if (!roles.contains(selectedRole)) selectedRole = 'usuario';

    final currentAreaId = user.areaId;
    final currentAreaName = user.areaDisplay;

    String? selectedAreaId = currentAreaId.trim().isEmpty ? null : currentAreaId;
    String? selectedAreaName = currentAreaName;

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
                        Text(
                          user.email,
                          style: Theme.of(context).textTheme.bodySmall,
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

                              final areaId = selectedRole == 'administrador'
                                  ? adminAreaId
                                  : (selectedAreaId ?? '');
                              final areaName = selectedRole == 'administrador'
                                  ? adminAreaId
                                  : (selectedAreaName ?? '');

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
                                    .updateUserProfile(
                                      uid: user.id,
                                      role: selectedRole,
                                      areaId: areaId,
                                      areaName: areaName,
                                    );
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
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    const roles = ['usuario', 'administrador'];

    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    var selectedRole = 'usuario';
    String? selectedAreaId;

    String? nameError;
    String? emailError;
    String? passwordError;
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
                    selectedRole == 'administrador' ? adminAreaId : (selectedAreaId ?? '');
                final fallbackAreaName =
                    selectedRole == 'administrador' ? adminAreaId : '';

                final missingArea = fallbackAreaId.isNotEmpty &&
                    !areas.any((area) => area.id == fallbackAreaId);

                final areaOptions = _mergeAreas(
                  areas,
                  fallbackId: fallbackAreaId,
                  fallbackName: fallbackAreaName,
                );

                if (selectedRole == 'administrador') {
                  selectedAreaId = fallbackAreaId;
                } else if (areaOptions.isNotEmpty &&
                    !areaOptions.any((a) => a.id == selectedAreaId)) {
                  selectedAreaId = areaOptions.first.id;
                }

                final areaLocked = selectedRole == 'administrador';

                final canSave = !isSaving &&
                    !isSeeding &&
                    areaOptions.isNotEmpty &&
                    !areasAsync.isLoading &&
                    !areasAsync.hasError;

                return AlertDialog(
                  title: const Text('Nuevo usuario'),
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
                        const SizedBox(height: 12),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Correo',
                            errorText: emailError,
                          ),
                          enabled: !isSaving,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passwordController,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            errorText: passwordError,
                          ),
                          enabled: !isSaving,
                        ),
                        const SizedBox(height: 12),
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
                                    setState(() => selectedAreaId = value);
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
                              final email = emailController.text.trim();
                              final password = passwordController.text;

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

                              if (email.isEmpty || !email.contains('@')) {
                                emailError = 'Ingresa un correo válido';
                                hasError = true;
                              } else {
                                emailError = null;
                              }

                              if (password.length < 6) {
                                passwordError =
                                    'La contraseña debe tener 6 caracteres o más';
                                hasError = true;
                              } else {
                                passwordError = null;
                              }

                              if (areaId.trim().isEmpty) {
                                areaError = 'Selecciona un área';
                                hasError = true;
                              } else {
                                areaError = null;
                              }

                              if (hasError) {
                                setState(() {});
                                return;
                              }

                              setState(() => isSaving = true);

                              try {
                                await ref
                                    .read(profileRepositoryProvider)
                                    .createUserWithRole(
                                      name: name,
                                      email: email,
                                      password: password,
                                      role: selectedRole,
                                      areaId: areaId,
                                    );

                                if (!navigator.mounted) return;
                                navigator.pop();

                                if (messenger.mounted) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Usuario creado correctamente.'),
                                    ),
                                  );
                                }
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
                                  contextLabel: 'AdminUsersScreen.createUser',
                                );
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: AppSplash(compact: true, size: 20),
                            )
                          : const Text('Crear'),
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
    emailController.dispose();
    passwordController.dispose();
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    bool isDeleting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Eliminar usuario'),
              content: Text(
                'Se eliminará el usuario ${user.name} (${user.email}).',
              ),
              actions: [
                TextButton(
                  onPressed:
                      isDeleting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          final navigator = Navigator.of(dialogContext);
                          final messenger =
                              ScaffoldMessenger.of(dialogContext);

                          setState(() => isDeleting = true);

                          try {
                            await ref
                                .read(profileRepositoryProvider)
                                .deleteUser(uid: user.id);

                            if (!navigator.mounted || !messenger.mounted) return;

                            navigator.pop();
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Usuario eliminado.')),
                            );
                          } catch (error, stack) {
                            setState(() => isDeleting = false);
                            if (!messenger.mounted) return;
                            _showErrorSnackBarWithMessenger(
                              messenger,
                              error,
                              stack: stack,
                              contextLabel: 'AdminUsersScreen.deleteUser',
                            );
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  icon: isDeleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: AppSplash(compact: true, size: 20),
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
}

const adminAreaId = 'Software';

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


