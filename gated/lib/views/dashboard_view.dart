import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/session_expiration.dart';
import '../services/auth_service.dart';
import '../services/garage_door_service.dart';
import '../utils/snackbar_utils.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({
    super.key,
    this.isActive = true,
    AuthService? authService,
    GarageDoorController? garageDoorController,
  }) : _authService = authService,
       _garageDoorController = garageDoorController;

  final bool isActive;
  final AuthService? _authService;
  final GarageDoorController? _garageDoorController;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  static const Duration _pollInterval = Duration(seconds: 1);

  late final AuthService _authService;
  late final GarageDoorController _garageDoorController;

  Timer? _pollTimer;
  GarageDoorStatus? _status;
  String? _loadError;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isTriggering = false;
  bool _isUpdatingState = false;
  bool _isRedirectingToLogin = false;

  @override
  void initState() {
    super.initState();
    _authService = widget._authService ?? const AuthService();
    _garageDoorController =
        widget._garageDoorController ??
        GarageDoorService(authService: _authService);

    if (widget.isActive) {
      _activatePolling(initialLoad: true);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) {
      return;
    }

    if (widget.isActive) {
      _activatePolling(initialLoad: _status == null);
      return;
    }

    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dashboard', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 20),
          Text(
            'Das Modelltor wird ueber den Shelly-Proxy gesteuert. '
            'Der angezeigte Zustand ist ohne Sensor modelliert und kann '
            'bei Bedarf manuell korrigiert werden.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          if (_isLoading && _status == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            )
          else if (_loadError != null && _status == null)
            _buildLoadErrorCard(theme)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 950;
                final statusCard = _buildStatusCard(theme);
                final helperColumn = Column(
                  children: [
                    _buildShellyCard(theme),
                    const SizedBox(height: 20),
                    _buildInfoCard(theme),
                  ],
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: statusCard),
                      const SizedBox(width: 24),
                      Expanded(flex: 2, child: helperColumn),
                    ],
                  );
                }

                return Column(
                  children: [
                    statusCard,
                    const SizedBox(height: 20),
                    helperColumn,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLoadErrorCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Text(
                  'Torstatus konnte nicht geladen werden',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_loadError!, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _refreshStatus,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    final status = _status;
    if (status == null) {
      return const SizedBox.shrink();
    }

    final visual = _visualForStatus(theme.colorScheme, status);
    final isBusy = _isTriggering || _isUpdatingState;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: visual.backgroundColor,
                  foregroundColor: visual.foregroundColor,
                  child: Icon(visual.icon),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Torstatus', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        visual.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: visual.foregroundColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        visual.description,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStatusMeta(theme, status),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: isBusy ? null : _triggerPulse,
              icon: _isTriggering
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.power_settings_new_rounded),
              label: Text(
                status.state == GarageDoorState.open
                    ? 'Impuls zum Schliessen senden'
                    : 'Impuls senden',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Ein weiterer Impuls ist waehrend der modellierten Bewegung gesperrt, '
              'damit die App ohne Sensor nicht in einen widerspruechlichen Zustand laeuft.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Text(
              'Status manuell korrigieren',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildManualStateButton(
                  label: 'Als offen markieren',
                  state: GarageDoorState.open,
                  isBusy: isBusy,
                ),
                _buildManualStateButton(
                  label: 'Als geschlossen markieren',
                  state: GarageDoorState.closed,
                  isBusy: isBusy,
                ),
                _buildManualStateButton(
                  label: 'Als unbekannt markieren',
                  state: GarageDoorState.unknown,
                  isBusy: isBusy,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMeta(ThemeData theme, GarageDoorStatus status) {
    final rows = <Widget>[
      _DashboardInfoRow(
        icon: Icons.timer_outlined,
        label: status.countdownLabel ?? 'Kein aktiver Countdown',
        value: status.remainingMs == null
            ? 'Keiner'
            : _formatDuration(status.remainingMs!),
      ),
      _DashboardInfoRow(
        icon: Icons.route_rounded,
        label: 'Naechster modellierter Zustand',
        value: _titleForState(status.nextState) ?? 'Keiner',
      ),
      _DashboardInfoRow(
        icon: Icons.track_changes_rounded,
        label: 'Statusbasis',
        value: _titleForConfidence(status.stateConfidence),
      ),
      _DashboardInfoRow(
        icon: Icons.history_rounded,
        label: 'Letzte Aktion',
        value: _formatLastAction(status.lastAction),
      ),
    ];

    final actionTimestamp = status.lastAction.timestamp;
    if (actionTimestamp != null) {
      rows.add(
        _DashboardInfoRow(
          icon: Icons.schedule_rounded,
          label: 'Letzte Aenderung',
          value: _formatDateTime(actionTimestamp.toLocal()),
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          rows[index],
          if (index < rows.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildShellyCard(ThemeData theme) {
    final shelly = _status?.shelly;
    final relayText = switch (shelly?.relayOutput) {
      true => 'Relais aktiv',
      false => 'Relais inaktiv',
      null => 'Relaiszustand unbekannt',
    };
    final reachabilityText = switch (shelly?.isReachable) {
      true => 'Shelly erreichbar',
      false => 'Shelly derzeit nicht erreichbar',
      null => 'Shelly-Status noch nicht geprueft',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shelly-Hinweise', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            _DashboardInfoRow(
              icon: Icons.router_rounded,
              label: 'Erreichbarkeit',
              value: reachabilityText,
            ),
            const SizedBox(height: 12),
            _DashboardInfoRow(
              icon: Icons.toggle_on_rounded,
              label: 'Letzter Relaiswert',
              value: relayText,
            ),
            const SizedBox(height: 12),
            _DashboardInfoRow(
              icon: Icons.update_rounded,
              label: 'Zuletzt geprueft',
              value: shelly?.lastCheckedAt == null
                  ? 'Noch nicht verfuegbar'
                  : _formatDateTime(shelly!.lastCheckedAt!.toLocal()),
            ),
            if (shelly?.errorMessage case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hinweis zum Modell', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              'Ohne dedizierten Sensor kennt das System keine echte Torposition. '
              'Die Anzeige basiert daher auf festen Zeiten und kann bewusst '
              'manuell korrigiert werden.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualStateButton({
    required String label,
    required GarageDoorState state,
    required bool isBusy,
  }) {
    final isSelected = _status?.state == state;

    return OutlinedButton(
      onPressed: isBusy ? null : () => _setManualState(state),
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : null,
      ),
      child: Text(label),
    );
  }

  Future<void> _refreshStatus({
    bool silent = false,
    bool showLoadErrorSnackBar = false,
  }) async {
    if (_isRefreshing || _isRedirectingToLogin) {
      return;
    }

    setState(() {
      _isRefreshing = true;
      if (_status == null) {
        _isLoading = true;
      }
    });

    try {
      final status = await _garageDoorController.fetchStatus();
      if (!mounted) {
        return;
      }

      setState(() {
        _status = status;
        _loadError = null;
        _isLoading = false;
      });
    } on SessionExpiredException catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = error.message;
        });
      }
      await _handleSessionExpired(error);
    } on GarageDoorException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        if (_status == null) {
          _loadError = error.message;
        }
      });

      if (!silent || showLoadErrorSnackBar) {
        _showErrorSnackBar(error.message);
      }
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      const message = 'Zeitueberschreitung beim Laden des Torstatus.';
      setState(() {
        _isLoading = false;
        if (_status == null) {
          _loadError = message;
        }
      });

      if (!silent || showLoadErrorSnackBar) {
        _showErrorSnackBar(message);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      const message = 'Torstatus konnte nicht geladen werden.';
      setState(() {
        _isLoading = false;
        if (_status == null) {
          _loadError = message;
        }
      });

      if (!silent || showLoadErrorSnackBar) {
        _showErrorSnackBar(message);
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _triggerPulse() async {
    setState(() => _isTriggering = true);

    try {
      final status = await _garageDoorController.triggerPulse();
      if (!mounted) {
        return;
      }

      setState(() {
        _status = status;
        _loadError = null;
      });

      showAppSnackBar(context, message: 'Impuls wurde gesendet.');
    } on SessionExpiredException catch (error) {
      await _handleSessionExpired(error);
    } on GarageDoorException catch (error) {
      _showErrorSnackBar(error.message);
    } on TimeoutException {
      _showErrorSnackBar('Zeitueberschreitung beim Senden des Impulses.');
    } catch (_) {
      _showErrorSnackBar('Impuls konnte nicht gesendet werden.');
    } finally {
      if (mounted) {
        setState(() => _isTriggering = false);
      }
    }
  }

  Future<void> _setManualState(GarageDoorState state) async {
    setState(() => _isUpdatingState = true);

    try {
      final status = await _garageDoorController.setManualState(state);
      if (!mounted) {
        return;
      }

      setState(() {
        _status = status;
        _loadError = null;
      });

      showAppSnackBar(
        context,
        message: 'Torstatus auf ${_titleForState(state)} gesetzt.',
      );
    } on SessionExpiredException catch (error) {
      await _handleSessionExpired(error);
    } on GarageDoorException catch (error) {
      _showErrorSnackBar(error.message);
    } on TimeoutException {
      _showErrorSnackBar(
        'Zeitueberschreitung beim manuellen Aktualisieren des Torstatus.',
      );
    } catch (_) {
      _showErrorSnackBar('Torstatus konnte nicht aktualisiert werden.');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingState = false);
      }
    }
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

  _DashboardStateVisual _visualForStatus(
    ColorScheme colorScheme,
    GarageDoorStatus status,
  ) {
    final isHeuristic =
        status.stateConfidence == GarageDoorStateConfidence.heuristic;
    final state = status.state;

    return switch (state) {
      GarageDoorState.determining => _DashboardStateVisual(
        title: 'Status wird ermittelt',
        description:
            'Das Backend wartet kurz ab und setzt ohne Bewegung '
            'anschliessend auf geschlossen.',
        icon: Icons.hourglass_top_rounded,
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.primary,
      ),
      GarageDoorState.opening => _DashboardStateVisual(
        title: 'Tor oeffnet',
        description: isHeuristic
            ? 'Die Oeffnungsbewegung wurde heuristisch ueber einen externen '
                  'Shelly-Impuls erkannt.'
            : 'Das Modell rechnet aktuell mit einer Oeffnungsbewegung.',
        icon: Icons.upload_rounded,
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      GarageDoorState.open => _DashboardStateVisual(
        title: 'Tor offen',
        description: isHeuristic
            ? 'Das Modell geht nach einem heuristisch erkannten externen '
                  'Shelly-Impuls von einem offenen Tor aus.'
            : 'Das Modell geht von einem offenen Tor aus, bis das automatische '
                  'Schliessen beginnt.',
        icon: Icons.door_front_door_outlined,
        backgroundColor: colorScheme.tertiaryContainer,
        foregroundColor: colorScheme.onTertiaryContainer,
      ),
      GarageDoorState.closing => _DashboardStateVisual(
        title: 'Tor schliesst',
        description: isHeuristic
            ? 'Die Schliessbewegung wurde heuristisch ueber einen externen '
                  'Shelly-Impuls erkannt.'
            : 'Das Modell rechnet aktuell mit einer Schliessbewegung.',
        icon: Icons.download_rounded,
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
      ),
      GarageDoorState.closed => _DashboardStateVisual(
        title: 'Tor geschlossen',
        description:
            'Das Tor sollte sich im Standardzustand geschlossen '
            'befinden.',
        icon: Icons.garage_rounded,
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.secondary,
      ),
      GarageDoorState.unknown => _DashboardStateVisual(
        title: 'Status unbekannt',
        description: isHeuristic
            ? 'Ein externer Shelly-Impuls wurde heuristisch waehrend einer '
                  'laufenden Bewegung erkannt. Die reale Position ist deshalb '
                  'derzeit unklar.'
            : 'Die reale Position ist derzeit nicht sicher. Eine manuelle '
                  'Korrektur ist moeglich.',
        icon: Icons.help_outline_rounded,
        backgroundColor: colorScheme.errorContainer,
        foregroundColor: colorScheme.onErrorContainer,
      ),
    };
  }

  String _titleForConfidence(GarageDoorStateConfidence confidence) {
    return switch (confidence) {
      GarageDoorStateConfidence.modeled => 'Modelliert',
      GarageDoorStateConfidence.heuristic => 'Heuristisch erkannt',
    };
  }

  String _formatLastAction(GarageDoorLastAction action) {
    if (action.source == 'heuristic-external') {
      return 'Heuristisch extern erkannt: ${action.description}';
    }

    return action.description;
  }

  String? _titleForState(GarageDoorState? state) {
    return switch (state) {
      GarageDoorState.determining => 'Status wird ermittelt',
      GarageDoorState.opening => 'Tor oeffnet',
      GarageDoorState.open => 'Tor offen',
      GarageDoorState.closing => 'Tor schliesst',
      GarageDoorState.closed => 'Tor geschlossen',
      GarageDoorState.unknown => 'Status unbekannt',
      null => null,
    };
  }

  String _formatDuration(int milliseconds) {
    final totalSeconds = (milliseconds / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    if (minutes == 0) {
      return '$seconds s';
    }

    return '$minutes min ${seconds.toString().padLeft(2, '0')} s';
  }

  String _formatDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');

    return '$day.$month.$year, $hour:$minute:$second';
  }

  void _activatePolling({required bool initialLoad}) {
    _pollTimer?.cancel();
    if (initialLoad) {
      unawaited(_refreshStatus());
    } else {
      unawaited(_refreshStatus(silent: true));
    }

    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_refreshStatus(silent: true));
    });
  }
}

class _DashboardInfoRow extends StatelessWidget {
  const _DashboardInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardStateVisual {
  const _DashboardStateVisual({
    required this.title,
    required this.description,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
}
