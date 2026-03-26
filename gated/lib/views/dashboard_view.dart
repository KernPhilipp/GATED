import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.dashboard_customize_rounded,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Diese Ansicht ist in Vorbereitung.',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sobald die Vorarbeiten abgeschlossen sind, kann das '
                    'eigentliche Dashboard hier eingebunden werden. Bis dahin '
                    'stehen Kennzeichen, Profil und Einstellungen voll zur '
                    'Verfuegung.',
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: const [
                      Chip(
                        avatar: Icon(Icons.view_list_rounded),
                        label: Text('Kennzeichen'),
                      ),
                      Chip(
                        avatar: Icon(Icons.person_rounded),
                        label: Text('Profil'),
                      ),
                      Chip(
                        avatar: Icon(Icons.settings_rounded),
                        label: Text('Einstellungen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Web-App Installation',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'GATED ist als installierbare Web-App vorbereitet. '
                      'Browser bieten die Installation auf localhost oder '
                      'ueber HTTPS an.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
