import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'manual_inputs_provider.dart';
import '../../models/manual_input.dart';

class ManualInputsPage extends ConsumerWidget {
  const ManualInputsPage({super.key});

  void _showInputForm(
    BuildContext context,
    WidgetRef ref, [
    ManualInput? input,
  ]) {
    final isEditing = input != null;
    final currentValue = input?.value ?? 0.0;
    final valueFormat = NumberFormat.decimalPattern('ko_KR');
    bool isDeltaMode = false;

    final keyController = TextEditingController(text: input?.keyName);
    final valueController = TextEditingController(
      text: isEditing ? currentValue.toString() : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> save() async {
              final key = keyController.text.trim();
              final raw = valueController.text.trim().replaceAll(',', '');
              final parsed = int.tryParse(raw);
              if (key.isEmpty || parsed == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid key and integer value.'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                return;
              }

              if (isDeltaMode && !isEditing) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Adjust mode requires an existing value.'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                return;
              }

              final nextValue =
                  isDeltaMode ? (currentValue + parsed) : parsed.toDouble();

              final newModel = ManualInput(
                id: input?.id,
                keyName: key,
                value: nextValue,
              );

              try {
                await ref.read(manualInputsServiceProvider).saveInput(newModel);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Save failed: $e'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            }

            final raw = valueController.text.trim().replaceAll(',', '');
            final parsed = int.tryParse(raw);
            final preview = isDeltaMode && isEditing && parsed != null
                ? currentValue + parsed
                : null;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isEditing ? 'Edit Input' : 'New Input',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: [
                      const ButtonSegment(value: false, label: Text('Set total')),
                      ButtonSegment(
                        value: true,
                        label: const Text('Adjust'),
                        enabled: isEditing,
                      ),
                    ],
                    selected: {isDeltaMode},
                    onSelectionChanged: (selection) {
                      setModalState(() {
                        isDeltaMode = selection.first;
                        if (isDeltaMode) {
                          valueController.text = '';
                        } else if (isEditing) {
                          valueController.text = currentValue.toString();
                        }
                        valueController.selection = TextSelection.collapsed(
                          offset: valueController.text.length,
                        );
                      });
                    },
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Current: ${valueFormat.format(currentValue)}',
                      style: const TextStyle(color: Colors.blueGrey),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: keyController,
                    decoration: const InputDecoration(
                      labelText: 'Key Name (e.g. KRW_USD)',
                      border: OutlineInputBorder(),
                    ),
                    enabled:
                        !isEditing,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: valueController,
                    decoration: InputDecoration(
                      labelText: isDeltaMode
                          ? 'Change (+/-)'
                          : 'Value (e.g. 1350)',
                      helperText: isDeltaMode ? 'Example: +1000 or -500 (integers only)' : 'Integers only',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                    ],
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setModalState(() {}),
                    onSubmitted: (_) => save(),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'After: ${valueFormat.format(preview)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: save,
                    child: Text(isDeltaMode ? 'Apply Change' : 'Save'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inputsAsync = ref.watch(manualInputsProvider);
    final valueFormat = NumberFormat.decimalPattern('ko_KR');

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showInputForm(context, ref),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(manualInputsProvider.future),
        child: inputsAsync.when(
          data: (inputs) {
            if (inputs.isEmpty) {
              return ListView(
                // ListView allows RefreshIndicator to work even when empty
                children: const [
                  SizedBox(
                    height: 300,
                    child: Center(child: Text('No manual inputs found.')),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: inputs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final input = inputs[index];
                final updatedText = input.updatedAt != null
                    ? ' Updated ${DateFormat('MM/dd HH:mm').format(input.updatedAt!)}'
                    : '';
                return Dismissible(
                  key: ValueKey(input.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete input?'),
                            content: Text('Delete "${input.keyName}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                  },
                  background: Container(
                    padding: const EdgeInsets.only(right: 20),
                    alignment: Alignment.centerRight,
                    color: Colors.redAccent,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    if (input.id == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Delete failed: missing id.'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      ref.invalidate(manualInputsProvider);
                      return;
                    }
                    try {
                      await ref
                          .read(manualInputsServiceProvider)
                          .deleteInput(input.id!);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Deleted: ${input.keyName}'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Delete failed: $e'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      ref.invalidate(manualInputsProvider);
                    }
                  },
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      title: Text(
                        input.keyName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Value: ${valueFormat.format(input.value)}$updatedText',
                      ),
                      trailing: const Icon(
                        Icons.edit,
                        size: 20,
                        color: Colors.blueGrey,
                      ),
                      onTap: () => _showInputForm(context, ref, input),
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
        ),
      ),
    );
  }
}
