import 'package:flutter/material.dart';

Future<String?> showSearchableSelect({
  required BuildContext context,
  required String title,
  required List<String> options,
  String addLabel = 'Agregar',
  Future<String?> Function(String query)? onAdd,
}) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setState) {
              final query = controller.text.trim().toLowerCase();
              final filtered = options
                  .where((value) => value.toLowerCase().contains(query))
                  .toList();
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Buscar',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    if (onAdd != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilledButton.icon(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            final result = await onAdd(controller.text.trim());
                            final trimmed = result?.trim() ?? '';
                            if (!navigator.mounted || trimmed.isEmpty) return;
                            navigator.pop(trimmed);
                          },
                          icon: const Icon(Icons.add),
                          label: Text(addLabel),
                        ),
                      ),
                    if (options.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('Sin opciones registradas.'),
                      )
                    else if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('Sin coincidencias.'),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final value = filtered[index];
                            return ListTile(
                              title: Text(value),
                              onTap: () => Navigator.pop(context, value),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}
