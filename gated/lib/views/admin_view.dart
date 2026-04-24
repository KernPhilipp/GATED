import 'package:flutter/material.dart';

import '../services/admin_service.dart';
import '../services/email_draft_service.dart';
import '../utils/snackbar_utils.dart';

class AdminView extends StatefulWidget {
  const AdminView({
    super.key,
    required this.adminService,
    required this.emailDraftService,
  });

  final AdminService adminService;
  final EmailDraftService emailDraftService;

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  final TextEditingController _searchController = TextEditingController();
  final List<AdminUser> _users = [];

  bool _isLoading = true;
  bool _isMutating = false;
  String? _loadError;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
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
    final visibleUsers = _buildVisibleUsers(searchQuery);

    return Stack(
      children: [
        AbsorbPointer(
          absorbing: _isMutating,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 20),
                Text(
                  'Benutzerdaten zentral verwalten. Admin-Konten bleiben '
                  'sichtbar, koennen aber nicht bearbeitet oder geloescht werden.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _buildToolbar(),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _buildContent(visibleUsers, searchQuery),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isMutating)
          const Positioned.fill(
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

  Widget _buildToolbar() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Benutzer suchen',
              hintText: 'Nach E-Mail oder Rolle filtern',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Suche leeren',
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : () => _loadUsers(forceRefresh: true),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Aktualisieren'),
        ),
      ],
    );
  }

  Widget _buildContent(List<AdminUser> visibleUsers, String searchQuery) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Benutzerdaten konnten nicht geladen werden.'),
          const SizedBox(height: 8),
          Text(_loadError!),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _loadUsers(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Erneut versuchen'),
          ),
        ],
      );
    }

    if (_users.isEmpty) {
      return const Text('Noch keine Benutzer vorhanden.');
    }

    if (visibleUsers.isEmpty) {
      return Text('Keine Treffer fuer "$searchQuery".');
    }

    return _AdminUsersTable(
      users: visibleUsers,
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
      onSort: _handleSort,
      onDelete: _confirmDeleteUser,
      onResetPassword: _resetPasswordForUser,
    );
  }

  List<AdminUser> _buildVisibleUsers(String searchQuery) {
    final normalizedQuery = searchQuery.toLowerCase();
    final filteredUsers = _users.where((user) {
      if (normalizedQuery.isEmpty) {
        return true;
      }

      return user.email.toLowerCase().contains(normalizedQuery) ||
          user.roleLabel.toLowerCase().contains(normalizedQuery);
    }).toList();

    int compare(AdminUser a, AdminUser b) {
      switch (_sortColumnIndex) {
        case 1:
          return a.roleLabel.compareTo(b.roleLabel);
        case 2:
          final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return aTime.compareTo(bTime);
        case 0:
        default:
          return a.email.toLowerCase().compareTo(b.email.toLowerCase());
      }
    }

    filteredUsers.sort(compare);
    if (!_sortAscending) {
      return filteredUsers.reversed.toList();
    }

    return filteredUsers;
  }

  void _handleSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) {
      return;
    }

    _searchController.clear();
    setState(() {});
  }

  Future<void> _loadUsers({bool forceRefresh = false}) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      if (forceRefresh) {
        _loadError = null;
      }
    });

    try {
      final users = await widget.adminService.fetchUsers();
      if (!mounted) {
        return;
      }

      setState(() {
        _users
          ..clear()
          ..addAll(users);
        _isLoading = false;
        _loadError = null;
      });
    } on AdminException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _loadError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _loadError = 'Benutzerdaten konnten nicht geladen werden.';
      });
    }
  }

  Future<void> _confirmDeleteUser(AdminUser user) async {
    if (user.isAdmin) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Benutzer loeschen'),
          content: Text(
            'Soll der Account ${user.email} wirklich geloescht werden?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Loeschen'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() => _isMutating = true);
    try {
      await widget.adminService.deleteUser(user.id);
      if (!mounted) {
        return;
      }

      setState(() {
        _users.removeWhere((entry) => entry.id == user.id);
      });
      showAppSnackBar(context, message: 'Benutzer geloescht.');
    } on AdminException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Benutzer konnte nicht geloescht werden.');
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  Future<void> _resetPasswordForUser(AdminUser user) async {
    if (user.isAdmin) {
      return;
    }

    setState(() => _isMutating = true);
    try {
      final result = await widget.adminService.resetPassword(user.id);
      final draftOpened = await widget.emailDraftService.openDraft(
        EmailDraft(
          to: result.email,
          subject: 'GATED Zugangsdaten',
          body:
              'Hallo,\n\n'
              'dein GATED-Zugang wurde von einem Administrator aktualisiert.\n\n'
              'E-Mail-Adresse: ${result.email}\n'
              'Temporaeres Passwort: ${result.temporaryPassword}\n\n'
              'Bitte melde dich damit an und aendere dein Passwort anschliessend '
              'direkt in GATED.\n\n'
              'Viele Gruesse',
        ),
      );

      if (!mounted) {
        return;
      }

      if (draftOpened) {
        showAppSnackBar(
          context,
          message:
              'Temporaeres Passwort erstellt und E-Mail-Entwurf geoeffnet.',
        );
      } else {
        await _showPasswordFallbackDialog(result);
      }
    } on AdminException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Temporaeres Passwort konnte nicht erstellt werden.');
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  Future<void> _showPasswordFallbackDialog(
    AdminPasswordResetResult result,
  ) async {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('E-Mail konnte nicht geoeffnet werden'),
          content: Text(
            'Der E-Mail-Entwurf konnte nicht automatisch geoeffnet werden.\n\n'
            'Benutzer: ${result.email}\n'
            'Temporaeres Passwort: ${result.temporaryPassword}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Schliessen'),
            ),
          ],
        );
      },
    );
  }

  void _showError(String message) {
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

class _AdminUsersTable extends StatelessWidget {
  const _AdminUsersTable({
    required this.users,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
    required this.onDelete,
    required this.onResetPassword,
  });

  final List<AdminUser> users;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending) onSort;
  final ValueChanged<AdminUser> onDelete;
  final ValueChanged<AdminUser> onResetPassword;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minTableWidth = 640.0;
        const actionColumnWidth = 170.0;
        const columnCount = 4;
        final tableWidth = constraints.maxWidth < minTableWidth
            ? minTableWidth
            : constraints.maxWidth;
        final flexibleColumnWidth =
            (tableWidth - actionColumnWidth) / (columnCount - 1);
        final borderColor = Theme.of(context).dividerColor;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: tableWidth),
            child: DataTable(
              horizontalMargin: 0,
              columnSpacing: 0,
              headingRowHeight: 50,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 72,
              sortColumnIndex: sortColumnIndex,
              sortAscending: sortAscending,
              border: TableBorder(
                top: BorderSide(color: borderColor, width: 3),
                right: BorderSide(color: borderColor, width: 3),
                bottom: BorderSide(color: borderColor, width: 3),
                left: BorderSide(color: borderColor, width: 3),
                horizontalInside: BorderSide(color: borderColor, width: 1),
                verticalInside: BorderSide(color: borderColor, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              columns: [
                DataColumn(
                  label: _headerCell('E-Mail', flexibleColumnWidth),
                  onSort: onSort,
                ),
                DataColumn(
                  label: _headerCell('Rolle', flexibleColumnWidth),
                  onSort: onSort,
                ),
                DataColumn(
                  label: _headerCell('Erstellt am', flexibleColumnWidth),
                  onSort: onSort,
                ),
                DataColumn(label: _headerCell('Aktionen', actionColumnWidth)),
              ],
              rows: [
                for (final user in users)
                  DataRow(
                    cells: [
                      DataCell(
                        _dataCell(
                          width: flexibleColumnWidth,
                          child: Text(
                            user.email,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        _dataCell(
                          width: flexibleColumnWidth,
                          child: Text(user.roleLabel),
                        ),
                      ),
                      DataCell(
                        _dataCell(
                          width: flexibleColumnWidth,
                          child: Text(_formatCreatedAt(user.createdAt)),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: actionColumnWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: user.isAdmin
                                    ? 'Admins koennen nicht bearbeitet werden'
                                    : 'Temporaeres Passwort erstellen',
                                onPressed: user.isAdmin
                                    ? null
                                    : () => onResetPassword(user),
                                icon: const Icon(Icons.mail_outline_rounded),
                              ),
                              IconButton(
                                tooltip: user.isAdmin
                                    ? 'Admins koennen nicht geloescht werden'
                                    : 'Benutzer loeschen',
                                onPressed: user.isAdmin
                                    ? null
                                    : () => onDelete(user),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _headerCell(String label, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(label),
      ),
    );
  }

  Widget _dataCell({required double width, required Widget child}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      ),
    );
  }

  String _formatCreatedAt(DateTime? createdAt) {
    if (createdAt == null) {
      return 'Nicht verfuegbar';
    }

    final day = createdAt.day.toString().padLeft(2, '0');
    final month = createdAt.month.toString().padLeft(2, '0');
    final year = createdAt.year.toString();
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');

    return '$day.$month.$year, $hour:$minute';
  }
}
