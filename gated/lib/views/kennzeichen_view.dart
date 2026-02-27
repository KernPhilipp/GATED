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
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isRefreshing = false;
  int _nextLocalRowId = 0;
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
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleRows = _buildVisibleRows();
    final searchQuery = _searchController.text.trim();

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
            rows: visibleRows,
            hasAnyRows: _rows.isNotEmpty,
            searchController: _searchController,
            searchQuery: searchQuery,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            isLoading: _isLoading,
            isRefreshing: _isRefreshing,
            onSearchChanged: (_) => _handleSearchChanged(),
            onClearSearch: _clearSearch,
            onSort: _handleSort,
            onRowChanged: _handleRowChanged,
            onAddRow: _addEmptyRow,
            onRefresh: () => _loadRows(refreshOnly: true),
            onSaveRow: _saveRow,
            onDeleteRow: _deleteRow,
          ),
        ],
      ),
    );
  }

  List<EditableKennzeichenRow> _buildVisibleRows() {
    final searchQuery = _searchController.text.trim().toLowerCase();
    final visibleRows = searchQuery.isEmpty
        ? List<EditableKennzeichenRow>.from(_rows)
        : _rows.where((row) {
            final teacher = row.teacherController.text.trim().toLowerCase();
            final licensePlate = row.licensePlateController.text
                .trim()
                .toLowerCase();
            return teacher.contains(searchQuery) ||
                licensePlate.contains(searchQuery);
          }).toList();

    if (_sortColumnIndex == null) {
      return visibleRows;
    }

    visibleRows.sort((a, b) {
      final result = switch (_sortColumnIndex) {
        0 => a.teacherController.text.trim().toLowerCase().compareTo(
          b.teacherController.text.trim().toLowerCase(),
        ),
        1 => a.licensePlateController.text.trim().toLowerCase().compareTo(
          b.licensePlateController.text.trim().toLowerCase(),
        ),
        _ => a.localRowId.compareTo(b.localRowId),
      };

      return _sortAscending ? result : -result;
    });

    return visibleRows;
  }

  void _handleSearchChanged() {
    setState(() {});
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

  void _handleRowChanged() {
    if (_searchController.text.trim().isEmpty && _sortColumnIndex == null) {
      return;
    }

    setState(() {});
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
