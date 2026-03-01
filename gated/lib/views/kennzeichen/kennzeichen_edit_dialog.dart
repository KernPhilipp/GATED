import 'package:flutter/material.dart';

class KennzeichenEditDialogResult {
  const KennzeichenEditDialogResult({
    required this.teacherName,
    required this.licensePlate,
  });

  final String teacherName;
  final String licensePlate;
}

Future<KennzeichenEditDialogResult?> showKennzeichenEditDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialTeacherName = '',
  String initialLicensePlate = '',
}) {
  return showDialog<KennzeichenEditDialogResult>(
    context: context,
    builder: (_) => _KennzeichenEditDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialTeacherName: initialTeacherName,
      initialLicensePlate: initialLicensePlate,
    ),
  );
}

class _KennzeichenEditDialog extends StatefulWidget {
  const _KennzeichenEditDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialTeacherName,
    required this.initialLicensePlate,
  });

  final String title;
  final String confirmLabel;
  final String initialTeacherName;
  final String initialLicensePlate;

  @override
  State<_KennzeichenEditDialog> createState() => _KennzeichenEditDialogState();
}

class _KennzeichenEditDialogState extends State<_KennzeichenEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _teacherController;
  late final TextEditingController _licensePlateController;

  @override
  void initState() {
    super.initState();
    _teacherController = TextEditingController(text: widget.initialTeacherName);
    _licensePlateController = TextEditingController(
      text: widget.initialLicensePlate,
    );
  }

  @override
  void dispose() {
    _teacherController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }

  void _submit() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    Navigator.of(context).pop(
      KennzeichenEditDialogResult(
        teacherName: _teacherController.text.trim(),
        licensePlate: _licensePlateController.text
            .trim()
            .toUpperCase()
            .replaceAll(' ', ''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _teacherController,
                decoration: const InputDecoration(
                  labelText: 'Lehrer',
                  hintText: 'z.B. Max Mustermann',
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Bitte Lehrername eingeben.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _licensePlateController,
                decoration: const InputDecoration(
                  labelText: 'Kennzeichen',
                  hintText: 'z.B. HA123AB',
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  final raw = (value ?? '').trim();
                  if (raw.isEmpty) {
                    return 'Bitte Kennzeichen eingeben.';
                  }
                  final normalized = raw.replaceAll(' ', '');
                  final onlyLettersAndDigits = RegExp(r'^[A-Za-z0-9]+$');
                  if (!onlyLettersAndDigits.hasMatch(normalized)) {
                    return 'Nur Buchstaben und Zahlen erlaubt.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
