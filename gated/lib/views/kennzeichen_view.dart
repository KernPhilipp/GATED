import 'package:flutter/material.dart';
import '../services/kennzeichen_service.dart';
import '../utils/snackbar_utils.dart';
import 'kennzeichen/editable_kennzeichen_row.dart';
import 'kennzeichen/kennzeichen_table_section.dart';

class KennzeichenView extends StatefulWidget {
  const KennzeichenView({super.key});

  @override
  State<KennzeichenView> createState() => _KennzeichenViewState();
}

class _KennzeichenViewState extends State<KennzeichenView> {
  static const Duration _minimumLoadDuration = Duration(seconds: 1);

  final KennzeichenService _kennzeichenService = const KennzeichenService();
  final List<EditableKennzeichenRow> _rows = [];

  bool _isLoading = true;
  bool _isRefreshing = false;
  int _nextLocalRowId = 0;

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kennzeichen', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 20),
          Text(
            'Lehrer und zugehörige Kennzeichen verwalten.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          KennzeichenTableSection(
            rows: _rows,
            isLoading: _isLoading,
            isRefreshing: _isRefreshing,
            onAddRow: _addEmptyRow,
            onRefresh: () => _loadRows(refreshOnly: true),
            onSaveRow: _saveRow,
            onDeleteRow: _deleteRow,
          ),
        ],
      ),
    );
  }

  Future<void> _loadRows({bool refreshOnly = false}) async {
    if (!mounted) return;
    final loadStartedAt = DateTime.now();

    setState(() {
      if (refreshOnly) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final entries = await _kennzeichenService.fetchEntries();
      if (!mounted) return;

      final newRows = entries
          .map(
            (entry) => EditableKennzeichenRow(
              localRowId: _nextLocalRowId++,
              id: entry.id,
              teacherName: entry.teacherName,
              licensePlate: entry.licensePlate,
            ),
          )
          .toList();

      for (final row in _rows) {
        row.dispose();
      }

      setState(() {
        _rows
          ..clear()
          ..addAll(newRows);
      });
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (_) {
      _showErrorSnackBar('Laden der Kennzeichen fehlgeschlagen.');
    } finally {
      final elapsed = DateTime.now().difference(loadStartedAt);
      final remaining = _minimumLoadDuration - elapsed;
      if (remaining > Duration.zero) {
        await Future.delayed(remaining);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  void _addEmptyRow() {
    setState(() {
      _rows.add(
        EditableKennzeichenRow(
          localRowId: _nextLocalRowId++,
          teacherName: '',
          licensePlate: '',
        ),
      );
    });
  }

  Future<void> _saveRow(EditableKennzeichenRow row) async {
    final teacherName = row.teacherController.text.trim();
    final licensePlate = row.licensePlateController.text.trim().toUpperCase();
    final isCreate = row.id == null;

    if (teacherName.isEmpty || licensePlate.isEmpty) {
      _showErrorSnackBar('Bitte Lehrername und/oder Kennzeichen ausfüllen.');
      return;
    }

    setState(() => row.isBusy = true);

    try {
      final saved = isCreate
          ? await _kennzeichenService.createEntry(
              teacherName: teacherName,
              licensePlate: licensePlate,
            )
          : await _kennzeichenService.updateEntry(
              id: row.id!,
              teacherName: teacherName,
              licensePlate: licensePlate,
            );

      if (!mounted) return;

      setState(() {
        row.id = saved.id;
        row.teacherController.text = saved.teacherName;
        row.licensePlateController.text = saved.licensePlate;
      });

      showAppSnackBar(
        context,
        message: isCreate ? 'Eintrag erstellt.' : 'Eintrag gespeichert.',
      );
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (_) {
      _showErrorSnackBar('Speichern fehlgeschlagen.');
    } finally {
      if (mounted) {
        setState(() => row.isBusy = false);
      }
    }
  }

  Future<void> _deleteRow(EditableKennzeichenRow row) async {
    if (row.id == null) {
      setState(() {
        _rows.remove(row);
      });
      row.dispose();
      return;
    }

    setState(() => row.isBusy = true);

    try {
      await _kennzeichenService.deleteEntry(row.id!);
      if (!mounted) return;

      setState(() {
        _rows.remove(row);
      });
      row.dispose();

      showAppSnackBar(context, message: 'Eintrag gelöscht.');
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
      if (mounted) {
        setState(() => row.isBusy = false);
      }
    } catch (_) {
      _showErrorSnackBar('Löschen fehlgeschlagen.');
      if (mounted) {
        setState(() => row.isBusy = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: message,
      isError: true,
      withCloseAction: true,
    );
  }
}
