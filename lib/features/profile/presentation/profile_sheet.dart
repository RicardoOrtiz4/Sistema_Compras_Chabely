import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      return _ProfileContent(user: user, ref: ref);
    },
  );
}

class _ProfileContent extends StatefulWidget {
  const _ProfileContent({required this.user, required this.ref});

  final AppUser user;
  final WidgetRef ref;

  @override
  State<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<_ProfileContent> {
  late final TextEditingController _contactEmailController;
  bool _isSaving = false;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    _contactEmailController = TextEditingController(
      text: widget.user.contactEmail ?? '',
    );
  }

  @override
  void dispose() {
    _contactEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.user.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(widget.user.email),
          const SizedBox(height: 8),
          Text('Área: ${widget.user.areaDisplay}'),
          Text('Rol: ${widget.user.role}'),
          const SizedBox(height: 16),
          TextField(
            controller: _contactEmailController,
            decoration: const InputDecoration(
              labelText: 'Correo de contacto',
              hintText: 'correo@ejemplo.com',
              helperText:
                  'Se usa para recibir avisos y preparar correos desde tu app de correo. El sistema no envia correos automaticos por si solo.',
            ),
            keyboardType: TextInputType.emailAddress,
            enabled: !_isSaving,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _isSaving ? null : _saveContactEmail,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: AppSplash(compact: true, size: 18),
                    )
                  : const Text('Guardar correo de contacto'),
            ),
          ),
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

  Future<void> _saveContactEmail() async {
    setState(() => _isSaving = true);
    try {
      await widget.ref
          .read(profileRepositoryProvider)
          .updateContactEmail(
            uid: widget.user.id,
            contactEmail: _contactEmailController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Correo actualizado.')));
    } catch (error, stack) {
      if (!mounted) return;
      final message = reportError(
        error,
        stack,
        context: 'ProfileSheet.saveEmail',
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await widget.ref.read(authRepositoryProvider).signOut();
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
