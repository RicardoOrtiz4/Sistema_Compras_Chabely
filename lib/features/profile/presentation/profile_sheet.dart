import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/features/auth/data/auth_repository.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/features/profile/data/profile_repository.dart';

Future<void> showProfileSheet(BuildContext context, WidgetRef ref) async {
  final userAsync = ref.read(currentUserProfileProvider);
  final user = userAsync.value;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      if (user == null) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return _ProfileContent(user: user, ref: ref);
    },
  );
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.user, required this.ref});

  final AppUser user;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(user.email),
          const SizedBox(height: 8),
          Text('Área: ${user.areaDisplay}'),
          Text('Rol: ${user.role}'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ref.read(authRepositoryProvider).signOut();
              navigator.pop();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
