import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistema_compras/core/extensions.dart';

import 'package:sistema_compras/core/login_identity.dart';
import 'package:sistema_compras/features/auth/data/auth_repository.dart';
import 'package:sistema_compras/features/auth/domain/app_user.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/widgets/app_splash.dart';
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
          child: SizedBox(height: 200, child: AppSplash()),
        );
      }
      return _ProfileContent(user: user);
    },
  );
}

class _ProfileContent extends ConsumerStatefulWidget {
  const _ProfileContent({required this.user});

  final AppUser user;

  @override
  ConsumerState<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends ConsumerState<_ProfileContent> {
  bool _isSigningOut = false;

  @override
  Widget build(BuildContext context) {
    final loginEmail =
        ref.watch(lastLoginEmailProvider).valueOrNull ??
        widget.user.email;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.user.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Correo de acceso: $loginEmail'),
          const SizedBox(height: 8),
          Text('Área: ${widget.user.areaDisplay}'),
          Text('Rol: ${widget.user.role}'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _isSigningOut ? null : _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesion'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(error, stack, context: 'ProfileSheet.signOut');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }
}
