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
  bool _isRedirectingToLogin = false;
  bool _isBackendUnavailable = false;

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
            'Das Tor wird ueber den Shelly-Proxy gesteuert. '
            'Der Naeherungssensor bestaetigt die stabilen Offen- und '
            'Geschlossen-Zustaende.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          if (_isBackendUnavailable && _status != null) ...[
            _buildConnectionBanner(theme),
            const SizedBox(height: 20),
          ],
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
            _buildStatusCard(theme),
        ],
      ),
    );
  }

  Widget _buildConnectionBanner(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Backend derzeit nicht erreichbar',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Der letzte erfolgreiche Torstatus bleibt sichtbar. '
                    'Im Hintergrund wird weiter versucht, die Verbindung '
                    'wiederherzustellen.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Torstatus konnte nicht geladen werden',
                    style: theme.textTheme.titleLarge,
                  ),
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
    final canTrigger = !_isTriggering && _isShellySensorReady(status);

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
              onPressed: canTrigger ? _triggerPulse : null,
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
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMeta(ThemeData theme, GarageDoorStatus status) {
    final shelly = status.shelly;
    final isReady = _isShellySensorReady(status);
    final warningColor = theme.colorScheme.error;

    final rows = <Widget>[
      _DashboardInfoRow(
        icon: Icons.sensors_rounded,
        label: 'Sensorstatus',
        value: _sensorStatusText(status),
        color: isReady ? null : warningColor,
      ),
      _DashboardInfoRow(
        icon: Icons.router_rounded,
        label: 'Shelly',
        value: _shellyStatusText(shelly),
        color: isReady ? null : warningColor,
      ),
      _DashboardInfoRow(
        icon: Icons.update_rounded,
        label: 'Sensor zuletzt geprueft',
        value: shelly?.lastCheckedAt == null
            ? 'Noch nicht verfuegbar'
            : _formatDateTime(shelly!.lastCheckedAt!.toLocal()),
      ),
    ];

    final lastChangedAt = status.lastChangedAt;
    if (lastChangedAt != null) {
      rows.add(
        _DashboardInfoRow(
          icon: Icons.schedule_rounded,
          label: 'Letzte Aenderung',
          value: _formatDateTime(lastChangedAt.toLocal()),
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

      final recoveredFromOutage = _isBackendUnavailable;
      setState(() {
        _status = status;
        _loadError = null;
        _isLoading = false;
        _isBackendUnavailable = false;
      });

      if (recoveredFromOutage) {
        showAppSnackBar(
          context,
          message: 'Verbindung zum Backend wiederhergestellt.',
          withCloseAction: true,
        );
      }
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
        } else {
          _isBackendUnavailable = true;
        }
      });

      if (_status != null) {
        _showBackendUnavailableOnce(error.message);
      } else if (!silent || showLoadErrorSnackBar) {
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
        } else {
          _isBackendUnavailable = true;
        }
      });

      if (_status != null) {
        _showBackendUnavailableOnce(message);
      } else if (!silent || showLoadErrorSnackBar) {
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
        } else {
          _isBackendUnavailable = true;
        }
      });

      if (_status != null) {
        _showBackendUnavailableOnce(message);
      } else if (!silent || showLoadErrorSnackBar) {
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

  void _showBackendUnavailableOnce(String message) {
    if (!mounted || _isBackendUnavailable == false) {
      return;
    }

    final wasAlreadyUnavailable = _loadError == message;
    _loadError = message;
    if (wasAlreadyUnavailable) {
      return;
    }

    showAppSnackBar(
      context,
      message:
          '$message Letzter bekannter Stand bleibt sichtbar, waehrend im Hintergrund neu verbunden wird.',
      isError: true,
      withCloseAction: true,
    );
  }

  _DashboardStateVisual _visualForStatus(
    ColorScheme colorScheme,
    GarageDoorStatus status,
  ) {
    final state = status.state;

    return switch (state) {
      GarageDoorState.determining => _DashboardStateVisual(
        title: 'Status wird ermittelt',
        description: 'Das Backend wartet auf den naechsten Sensorstatus.',
        icon: Icons.hourglass_top_rounded,
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.primary,
      ),
      GarageDoorState.opening => _DashboardStateVisual(
        title: 'Tor oeffnet',
        description:
            'Der Sensor bestaetigt den offenen Zustand nach kurzer Wartezeit.',
        icon: Icons.upload_rounded,
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      GarageDoorState.open => _DashboardStateVisual(
        title: 'Tor offen',
        description: 'Der Naeherungssensor meldet das Tor als offen.',
        icon: Icons.door_front_door_outlined,
        backgroundColor: colorScheme.tertiaryContainer,
        foregroundColor: colorScheme.onTertiaryContainer,
      ),
      GarageDoorState.closing => _DashboardStateVisual(
        title: 'Tor schliesst',
        description:
            'Der Sensor bestaetigt den geschlossenen Zustand nach kurzer Wartezeit.',
        icon: Icons.download_rounded,
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
      ),
      GarageDoorState.closed => _DashboardStateVisual(
        title: 'Tor geschlossen',
        description: 'Der Naeherungssensor meldet das Tor als geschlossen.',
        icon: Icons.garage_rounded,
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.secondary,
      ),
      GarageDoorState.unknown => _DashboardStateVisual(
        title: 'Status unbekannt',
        description:
            'Die reale Position ist derzeit nicht sicher, bis der Sensor wieder eindeutig meldet.',
        icon: Icons.help_outline_rounded,
        backgroundColor: colorScheme.errorContainer,
        foregroundColor: colorScheme.onErrorContainer,
      ),
    };
  }

  bool _isShellySensorReady(GarageDoorStatus status) {
    final shelly = status.shelly;
    return shelly?.isReachable == true && shelly?.inputState != null;
  }

  String _sensorStatusText(GarageDoorStatus status) {
    final shelly = status.shelly;
    if (shelly == null || shelly.isReachable == null) {
      return 'Noch nicht geprueft';
    }
    if (shelly.isReachable != true) {
      return 'Nicht erreichbar';
    }
    if (shelly.inputState == null) {
      return 'Sensorwert fehlt';
    }
    final remainingMs = status.remainingMs;
    if (remainingMs != null && remainingMs > 0) {
      return 'Bestaetigung laeuft (${_formatDuration(remainingMs)})';
    }
    return 'Erreichbar';
  }

  String _shellyStatusText(GarageDoorShellyStatus? shelly) {
    if (shelly == null || shelly.isReachable == null) {
      return 'Noch nicht geprueft';
    }
    if (shelly.isReachable == true && shelly.inputState != null) {
      return 'Erreichbar';
    }
    if (shelly.isReachable == true) {
      return 'Erreichbar, Sensorwert fehlt';
    }
    final error = shelly.errorMessage;
    return error == null || error.isEmpty ? 'Nicht erreichbar' : error;
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
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color ?? theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(color: color),
              ),
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
