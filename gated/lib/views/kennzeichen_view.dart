import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/session_expiration.dart';
import '../services/auth_service.dart';
import '../services/kennzeichen_service.dart';
import '../services/realtime_event_subscription.dart';
import '../utils/snackbar_utils.dart';
import 'kennzeichen/editable_kennzeichen_row.dart';
import 'kennzeichen/kennzeichen_edit_dialog.dart';
import 'kennzeichen/kennzeichen_row_filter_sort.dart';
import 'kennzeichen/kennzeichen_rows_controller.dart';
import 'kennzeichen/kennzeichen_table_section.dart';

class KennzeichenView extends StatefulWidget {
  const KennzeichenView({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<KennzeichenView> createState() => _KennzeichenViewState();
}

class _KennzeichenViewState extends State<KennzeichenView> {
  static const Duration _minimumLoadDuration = Duration(seconds: 1);

  final AuthService _authService = const AuthService();
  final KennzeichenRowsController _rowsController = KennzeichenRowsController();
  final List<EditableKennzeichenRow> _rows = [];
  final TextEditingController _searchController = TextEditingController();
  late final RealtimeEventSubscription _realtimeEvents;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isMutating = false;
  bool _isRedirectingToLogin = false;
  bool _hasLoadedOnce = false;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _realtimeEvents = RealtimeEventSubscription(
      authService: _authService,
      path: '/kennzeichen/events',
      canConnect: () => mounted && widget.isActive && !_isRedirectingToLogin,
      onEvent: _handleRealtimeEvent,
    );
    if (widget.isActive) {
      _activateRealtimeUpdates(initialLoad: true);
    }
  }

  @override
  void didUpdateWidget(covariant KennzeichenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) {
      return;
    }

    if (widget.isActive) {
      _activateRealtimeUpdates(initialLoad: !_hasLoadedOnce);
      return;
    }

    _disconnectRealtimeUpdates();
  }

  @override
  void dispose() {
    _realtimeEvents.dispose();
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

    return Stack(
      children: [
        AbsorbPointer(
          absorbing: _isMutating,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kennzeichen', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 20),
                Text(
                  'Lehrer und zugehoerige Kennzeichen verwalten.',
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
                  onSearchChanged: (_) => setState(() {}),
                  onClearSearch: _clearSearch,
                  onSort: _handleSort,
                  onAddRow: _openCreateDialog,
                  onEditRow: _editRow,
                  onDeleteRow: _deleteRow,
                ),
              ],
            ),
          ),
        ),
        if (_isMutating)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            ),
          ),
      ],
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
    if (!mounted || _isRedirectingToLogin) {
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
        _hasLoadedOnce = true;
        _rows
          ..clear()
          ..addAll(newRows);
      });
    } on SessionExpiredException catch (e) {
      await _handleSessionExpired(e);
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
    } on TimeoutException {
      _showErrorSnackBar('Zeitueberschreitung beim Laden der Kennzeichen.');
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
    } on SessionExpiredException catch (e) {
      await _handleSessionExpired(e);
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
    } on TimeoutException {
      _showErrorSnackBar('Zeitueberschreitung beim Speichern.');
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
    } on SessionExpiredException catch (e) {
      if (mounted) {
        setState(() => row.isBusy = false);
      }
      await _handleSessionExpired(e);
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
    } on TimeoutException {
      _showErrorSnackBar('Zeitueberschreitung beim Speichern.');
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

      showAppSnackBar(context, message: 'Eintrag geloescht.');
    } on SessionExpiredException catch (e) {
      if (mounted) {
        setState(() => row.isBusy = false);
      }
      await _handleSessionExpired(e);
    } on KennzeichenException catch (e) {
      _showErrorSnackBar(e.message);
      if (mounted) {
        setState(() => row.isBusy = false);
      }
    } on TimeoutException {
      _showErrorSnackBar('Zeitueberschreitung beim Loeschen.');
      if (mounted) {
        setState(() => row.isBusy = false);
      }
    } catch (_) {
      _showErrorSnackBar('Loeschen fehlgeschlagen.');
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

  Future<void> _handleSessionExpired(SessionExpiredException error) async {
    if (_isRedirectingToLogin || !mounted) {
      return;
    }

    _isRedirectingToLogin = true;
    await redirectToLoginAfterSessionExpired(
      context,
      authService: _authService,
      message: error.message,
      reason: error.reason,
    );
  }

  void _activateRealtimeUpdates({required bool initialLoad}) {
    if (initialLoad) {
      unawaited(_loadRows());
    } else {
      unawaited(_loadRows(refreshOnly: true));
    }

    _realtimeEvents.start();
  }

  void _handleRealtimeEvent() {
    if (!mounted || !widget.isActive || _isRedirectingToLogin) {
      return;
    }

    if (_isLoading || _isRefreshing || _isMutating) {
      return;
    }

    unawaited(_loadRows(refreshOnly: true));
  }

  void _disconnectRealtimeUpdates() {
    _realtimeEvents.stop();
  }
}
