import 'dart:async';
import 'package:flutter/material.dart';
import '../services/kennzeichen_service.dart';
import '../utils/snackbar_utils.dart';
import 'kennzeichen/editable_kennzeichen_row.dart';
import 'kennzeichen/kennzeichen_edit_dialog.dart';
import 'kennzeichen/kennzeichen_row_filter_sort.dart';
import 'kennzeichen/kennzeichen_rows_controller.dart';
import 'kennzeichen/kennzeichen_table_section.dart';

class KennzeichenView extends StatefulWidget {
  const KennzeichenView({super.key});

  @override
  State<KennzeichenView> createState() => _KennzeichenViewState();
}

class _KennzeichenViewState extends State<KennzeichenView> {
  static const Duration _minimumLoadDuration = Duration(seconds: 1);

  final KennzeichenRowsController _rowsController = KennzeichenRowsController();
  final List<EditableKennzeichenRow> _rows = [];
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isMutating = false;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchQuery = _searchController.text.trim();
    final visibleRows = buildVisibleKennzeichenRows(
      rows: _rows,
      searchQuery: searchQuery,
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
    );

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
          Stack(
            children: [
              AbsorbPointer(
                absorbing: _isMutating,
                child: KennzeichenTableSection(
                  rows: visibleRows,
                  hasAnyRows: _rows.isNotEmpty,
                  searchController: _searchController,
                  searchQuery: searchQuery,
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  isLoading: _isLoading,
                  isRefreshing: _isRefreshing,
                  onSearchChanged: (_) => setState(() {}),
                  onClearSearch: _clearSearch,
                  onSort: _handleSort,
                  onAddRow: _openCreateDialog,
                  onRefresh: () => _loadRows(refreshOnly: true),
                  onEditRow: _editRow,
                  onDeleteRow: _deleteRow,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) {
      return;
    }

    _searchController.clear();
    setState(() {});
  }

  void _handleSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  Future<void> _loadRows({bool refreshOnly = false}) async {
    if (!mounted) {
      return;
    }

    final loadStartedAt = DateTime.now();

    setState(() {
      if (refreshOnly) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final newRows = await _rowsController.loadRows();
      if (!mounted) {
        return;
      }

      setState(() {
        _rows
          ..clear()
          ..addAll(newRows);
      });
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
    } on TimeoutException {
      _showErrorSnackBar('Zeitüberschreitung beim Laden der Kennzeichen.');
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

  Future<void> _openCreateDialog() async {
    final data = await showKennzeichenEditDialog(
      context,
      title: 'Neuen Eintrag anlegen',
      confirmLabel: 'Anlegen',
    );

    if (!mounted || data == null) {
      return;
    }

    setState(() => _isMutating = true);

    try {
      final newRow = await _rowsController.createRow(
        teacherName: data.teacherName,
        licensePlate: data.licensePlate,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _rows.add(newRow);
      });

      showAppSnackBar(context, message: 'Eintrag erstellt.');
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
    } on TimeoutException {
      _showErrorSnackBar('Zeitüberschreitung beim Speichern.');
    } catch (_) {
      _showErrorSnackBar('Speichern fehlgeschlagen.');
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  Future<void> _editRow(EditableKennzeichenRow row) async {
    final data = await showKennzeichenEditDialog(
      context,
      title: 'Eintrag bearbeiten',
      confirmLabel: 'Speichern',
      initialTeacherName: row.teacherName,
      initialLicensePlate: row.licensePlate,
    );

    if (!mounted || data == null) {
      return;
    }

    setState(() {
      row.isBusy = true;
      _isMutating = true;
    });

    try {
      final updatedEntry = await _rowsController.updateRow(
        row: row,
        teacherName: data.teacherName,
        licensePlate: data.licensePlate,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _rowsController.applyUpdatedEntry(row, updatedEntry);
      });

      showAppSnackBar(context, message: 'Eintrag gespeichert.');
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
    } on TimeoutException {
      _showErrorSnackBar('Zeitüberschreitung beim Speichern.');
    } catch (_) {
      _showErrorSnackBar('Speichern fehlgeschlagen.');
    } finally {
      if (mounted) {
        setState(() {
          row.isBusy = false;
          _isMutating = false;
        });
      }
    }
  }

  Future<void> _deleteRow(EditableKennzeichenRow row) async {
    setState(() {
      row.isBusy = true;
      _isMutating = true;
    });

    try {
      await _rowsController.deleteRow(row);
      if (!mounted) {
        return;
      }

      setState(() {
        _rows.remove(row);
      });

      showAppSnackBar(context, message: 'Eintrag gelöscht.');
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
      if (mounted) {
        setState(() => row.isBusy = false);
      }
    } on TimeoutException {
      _showErrorSnackBar('Zeitüberschreitung beim Löschen.');
      if (mounted) {
        setState(() => row.isBusy = false);
      }
    } catch (_) {
      _showErrorSnackBar('Löschen fehlgeschlagen.');
      if (mounted) {
        setState(() => row.isBusy = false);
      }
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) {
      return;
    }

    showAppSnackBar(
      context,
      message: message,
      isError: true,
      withCloseAction: true,
    );
  }
}
