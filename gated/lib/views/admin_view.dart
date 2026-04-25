import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/session_expiration.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/email_draft_service.dart';
import '../services/realtime_event_subscription.dart';
import '../utils/snackbar_utils.dart';

class AdminView extends StatefulWidget {
  const AdminView({
    super.key,
    required this.adminService,
    required this.emailDraftService,
    AuthService? authService,
    this.isActive = true,
  }) : _authService = authService;

  final AdminService adminService;
  final EmailDraftService emailDraftService;
  final AuthService? _authService;
  final bool isActive;

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  final TextEditingController _searchController = TextEditingController();
  final List<AdminUser> _users = [];
  late final AuthService _authService;
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
    _authService = widget._authService ?? const AuthService();
    _realtimeEvents = RealtimeEventSubscription(
      authService: _authService,
      path: '/admin/events',
      canConnect: () => mounted && widget.isActive && !_isRedirectingToLogin,
      onEvent: _handleRealtimeEvent,
    );
    if (widget.isActive) {
      _activateRealtimeUpdates(initialLoad: true);
    }
  }

  @override
  void didUpdateWidget(covariant AdminView oldWidget) {
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
                  'Zugelassene Benutzer und registrierte Accounts verwalten.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _AdminTableSection(
                  users: visibleUsers,
                  hasAnyUsers: _users.isNotEmpty,
                  searchController: _searchController,
                  searchQuery: searchQuery,
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  isLoading: _isLoading,
                  onSearchChanged: (_) => setState(() {}),
                  onClearSearch: _clearSearch,
                  onSort: _handleSort,
                  onAddUser: _openCreateDialog,
                  onEditUser: _openEditDialog,
                  onDeleteUser: _confirmDeleteUser,
                  onResetPassword: _resetPasswordForUser,
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

  List<AdminUser> _buildVisibleUsers(String searchQuery) {
    final normalizedQuery = searchQuery.toLowerCase();
    final filteredUsers = _users.where((user) {
      if (normalizedQuery.isEmpty) {
        return true;
      }

      return user.email.toLowerCase().contains(normalizedQuery) ||
          user.roleLabel.toLowerCase().contains(normalizedQuery) ||
          _registeredLabel(user).toLowerCase().contains(normalizedQuery);
    }).toList();

    int compare(AdminUser a, AdminUser b) {
      switch (_sortColumnIndex) {
        case 1:
          return a.roleLabel.compareTo(b.roleLabel);
        case 2:
          return a.isRegistered == b.isRegistered
              ? 0
              : a.isRegistered
              ? 1
              : -1;
        case 3:
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

  Future<void> _loadUsers({bool refreshOnly = false}) async {
    if (!mounted || _isRedirectingToLogin) {
      return;
    }

    setState(() {
      if (refreshOnly) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final users = await widget.adminService.fetchUsers();
      if (!mounted) {
        return;
      }

      setState(() {
        _hasLoadedOnce = true;
        _users
          ..clear()
          ..addAll(users);
      });
    } on SessionExpiredException catch (error) {
      await _handleSessionExpired(error);
    } on AdminException catch (error) {
      _showError(error.message);
    } on TimeoutException {
      _showError('Zeitueberschreitung beim Laden der Benutzer.');
    } catch (_) {
      _showError('Benutzerdaten konnten nicht geladen werden.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _openCreateDialog() async {
    final result = await showAdminEmailDialog(
      context,
      title: 'Benutzer zulassen',
      confirmLabel: 'Anlegen',
    );
    if (!mounted || result == null) {
      return;
    }

    setState(() => _isMutating = true);
    try {
      await widget.adminService.addAllowedEmail(result.email);
      await _loadUsers(refreshOnly: true);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, message: 'Benutzer zugelassen.');
    } on AdminException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Benutzer konnte nicht zugelassen werden.');
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  Future<void> _openEditDialog(AdminUser user) async {
    if (!user.canEdit) {
      return;
    }

    final result = await showAdminEmailDialog(
      context,
      title: 'Benutzer bearbeiten',
      confirmLabel: 'Speichern',
      initialEmail: user.email,
    );
    if (!mounted || result == null || result.email == user.email) {
      return;
    }

    setState(() => _isMutating = true);
    try {
      await widget.adminService.updateAllowedEmail(
        currentEmail: user.email,
        newEmail: result.email,
      );
      await _loadUsers(refreshOnly: true);
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, message: 'Benutzer gespeichert.');
    } on AdminException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Benutzer konnte nicht gespeichert werden.');
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  Future<void> _confirmDeleteUser(AdminUser user) async {
    if (!user.canDelete) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Benutzer loeschen'),
          content: Text(
            'Soll ${user.email} wirklich geloescht und aus den zugelassenen '
            'E-Mails entfernt werden?',
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
      if (user.id != null) {
        await widget.adminService.deleteUser(user.id!);
      } else {
        await widget.adminService.deleteAllowedEmail(user.email);
      }
      await _loadUsers(refreshOnly: true);
      if (!mounted) {
        return;
      }
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
    if (!user.canResetPassword) {
      return;
    }

    setState(() => _isMutating = true);
    try {
      final result = await widget.adminService.resetPassword(user.id!);
      final draftOpened = await widget.emailDraftService.openDraft(
        EmailDraft(
          to: result.email,
          subject: 'GATED-Zugangsdaten',
          body:
              'Sehr geehrter GATED-User,\n\n'
              'Ihr GATED-Zugang wurde von mir aktualisiert.\n\n'
              'E-Mail-Adresse: ${result.email}\n'
              'Temporaeres Passwort: ${result.temporaryPassword}\n\n'
              'Bitte melden Sie sich mit diesen Zugangsdaten an und aendern '
              'Sie Ihr Passwort anschliessend '
              'direkt in GATED.\n\n'
              'Mit freundlichen Gruessen\n'
              'Philipp Kern\n'
              'Administrator'
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

  void _activateRealtimeUpdates({required bool initialLoad}) {
    if (initialLoad) {
      unawaited(_loadUsers());
    } else {
      unawaited(_loadUsers(refreshOnly: true));
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

    unawaited(_loadUsers(refreshOnly: true));
  }

  void _disconnectRealtimeUpdates() {
    _realtimeEvents.stop();
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

class _AdminTableSection extends StatelessWidget {
  const _AdminTableSection({
    required this.users,
    required this.hasAnyUsers,
    required this.searchController,
    required this.searchQuery,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.isLoading,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSort,
    required this.onAddUser,
    required this.onEditUser,
    required this.onDeleteUser,
    required this.onResetPassword,
  });

  final List<AdminUser> users;
  final bool hasAnyUsers;
  final TextEditingController searchController;
  final String searchQuery;
  final int? sortColumnIndex;
  final bool sortAscending;
  final bool isLoading;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final void Function(int columnIndex, bool ascending) onSort;
  final VoidCallback onAddUser;
  final ValueChanged<AdminUser> onEditUser;
  final ValueChanged<AdminUser> onDeleteUser;
  final ValueChanged<AdminUser> onResetPassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdminTableActions(
          searchController: searchController,
          searchQuery: searchQuery,
          onSearchChanged: onSearchChanged,
          onClearSearch: onClearSearch,
          onAddUser: onAddUser,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _buildContent(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (!hasAnyUsers && searchQuery.isEmpty) {
      return Column(
        children: [
          const Text('Noch keine Benutzer zugelassen.'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAddUser,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ersten Benutzer zulassen'),
          ),
        ],
      );
    }

    if (users.isEmpty) {
      return Center(child: Text('Keine Treffer fuer "$searchQuery".'));
    }

    return _AdminUsersTable(
      users: users,
      sortColumnIndex: sortColumnIndex,
      sortAscending: sortAscending,
      onSort: onSort,
      onEdit: onEditUser,
      onDelete: onDeleteUser,
      onResetPassword: onResetPassword,
    );
  }
}

class _AdminTableActions extends StatelessWidget {
  const _AdminTableActions({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onAddUser,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onAddUser;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 20,
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: searchQuery.isNotEmpty ? null : onAddUser,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Benutzer hinzufuegen'),
              style: searchQuery.isNotEmpty
                  ? FilledButton.styleFrom(
                      foregroundColor: Theme.of(context).disabledColor,
                      backgroundColor: Theme.of(context).disabledColor,
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            labelText: 'Suche',
            hintText: 'Nach E-Mail, Rolle oder Status filtern',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Suche leeren',
                    onPressed: onClearSearch,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ],
    );
  }
}

class _AdminUsersTable extends StatelessWidget {
  const _AdminUsersTable({
    required this.users,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
    required this.onEdit,
    required this.onDelete,
    required this.onResetPassword,
  });

  final List<AdminUser> users;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending) onSort;
  final ValueChanged<AdminUser> onEdit;
  final ValueChanged<AdminUser> onDelete;
  final ValueChanged<AdminUser> onResetPassword;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minTableWidth = 700.0;
        const minTableActionWidth = 150.0;
        const columnCount = 5;
        const sortArrowIconSize = 16.0;
        const sortArrowPadding = 2.0;
        const sortIndicatorWidth = sortArrowIconSize + (sortArrowPadding * 2);
        const sortRightPadding = 10.0;

        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minTableWidth;
        final tableWidth = availableWidth < minTableWidth
            ? minTableWidth
            : availableWidth;
        final columnWidth = tableWidth / columnCount;
        final tableActionWidth = columnWidth < minTableActionWidth
            ? minTableActionWidth
            : columnWidth;

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
                  headingRowAlignment: MainAxisAlignment.start,
                  label: _headerCell(
                    'Email',
                    columnWidth,
                    isSortable: true,
                    sortIndicatorWidth: sortIndicatorWidth,
                    sortRightPadding: sortRightPadding,
                  ),
                  onSort: onSort,
                ),
                DataColumn(
                  headingRowAlignment: MainAxisAlignment.start,
                  label: _headerCell(
                    'Rolle',
                    columnWidth,
                    isSortable: true,
                    sortIndicatorWidth: sortIndicatorWidth,
                    sortRightPadding: sortRightPadding,
                  ),
                  onSort: onSort,
                ),
                DataColumn(
                  headingRowAlignment: MainAxisAlignment.start,
                  label: _headerCell(
                    'Bereits registriert',
                    columnWidth,
                    isSortable: true,
                    sortIndicatorWidth: sortIndicatorWidth,
                    sortRightPadding: sortRightPadding,
                  ),
                  onSort: onSort,
                ),
                DataColumn(
                  headingRowAlignment: MainAxisAlignment.start,
                  label: _headerCell(
                    'Erstellt am',
                    columnWidth,
                    isSortable: true,
                    sortIndicatorWidth: sortIndicatorWidth,
                    sortRightPadding: sortRightPadding,
                  ),
                  onSort: onSort,
                ),
                DataColumn(label: _headerCell('Aktionen', tableActionWidth)),
              ],
              rows: [
                for (var index = 0; index < users.length; index++)
                  DataRow.byIndex(
                    index: index,
                    cells: [
                      DataCell(
                        _dataCell(
                          width: columnWidth,
                          child: Text(
                            users[index].email,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        _dataCell(
                          width: columnWidth,
                          child: Text(users[index].roleLabel),
                        ),
                      ),
                      DataCell(
                        _dataCell(
                          width: columnWidth,
                          child: Text(_registeredLabel(users[index])),
                        ),
                      ),
                      DataCell(
                        _dataCell(
                          width: columnWidth,
                          child: Text(_formatCreatedAt(users[index].createdAt)),
                        ),
                      ),
                      DataCell(
                        _buttonCell(
                          width: tableActionWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: users[index].canEdit
                                    ? 'Bearbeiten'
                                    : 'Admins koennen nicht bearbeitet werden',
                                onPressed: users[index].canEdit
                                    ? () => onEdit(users[index])
                                    : null,
                                icon: const Icon(Icons.edit_rounded),
                              ),
                              IconButton(
                                tooltip: users[index].canResetPassword
                                    ? 'Temporaeres Passwort erstellen'
                                    : 'Nur registrierte Benutzer',
                                onPressed: users[index].canResetPassword
                                    ? () => onResetPassword(users[index])
                                    : null,
                                icon: const Icon(Icons.mail_outline_rounded),
                              ),
                              IconButton(
                                tooltip: users[index].canDelete
                                    ? 'Benutzer loeschen'
                                    : 'Admins koennen nicht geloescht werden',
                                onPressed: users[index].canDelete
                                    ? () => onDelete(users[index])
                                    : null,
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

  Widget _headerCell(
    String text,
    double width, {
    bool isSortable = false,
    double sortIndicatorWidth = 0,
    double sortRightPadding = 0,
  }) {
    final adjustedWidth = isSortable
        ? (width - sortIndicatorWidth - sortRightPadding).clamp(0.0, width)
        : width;

    return SizedBox(
      width: adjustedWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(text),
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

  Widget _buttonCell({required double width, required Widget child}) {
    return SizedBox(width: width, child: child);
  }
}

class AdminEmailDialogResult {
  const AdminEmailDialogResult({required this.email});

  final String email;
}

Future<AdminEmailDialogResult?> showAdminEmailDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? initialEmail,
}) {
  return showDialog<AdminEmailDialogResult>(
    context: context,
    builder: (context) => _AdminEmailDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialEmail: initialEmail,
    ),
  );
}

class _AdminEmailDialog extends StatefulWidget {
  const _AdminEmailDialog({
    required this.title,
    required this.confirmLabel,
    this.initialEmail,
  });

  final String title;
  final String confirmLabel;
  final String? initialEmail;

  @override
  State<_AdminEmailDialog> createState() => _AdminEmailDialogState();
}

class _AdminEmailDialogState extends State<_AdminEmailDialog> {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _emailController,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-Mail'),
          validator: _validateEmail,
          onFieldSubmitted: (_) => _submit(),
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

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) {
      return 'Bitte E-Mail eingeben.';
    }
    if (!_emailPattern.hasMatch(email)) {
      return 'Bitte eine gueltige E-Mail eingeben.';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() == false) {
      return;
    }

    Navigator.of(
      context,
    ).pop(AdminEmailDialogResult(email: _emailController.text.trim()));
  }
}

String _registeredLabel(AdminUser user) {
  return user.isRegistered ? 'Ja' : 'Nein';
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
