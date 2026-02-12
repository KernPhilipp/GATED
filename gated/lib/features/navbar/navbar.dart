import 'package:flutter/material.dart';

import '../logo_assets.dart';
import 'navbar_constants.dart';
import 'navbar_item.dart';

class NavigationSidebar extends StatelessWidget {
  final List<({String label, IconData icon})> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const NavigationSidebar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final width = MediaQuery.of(context).size.width;
    final isCompactNav = width < bigSizeDisplay;
    final compactLogoAsset = getCompactLogoAsset(brightness);
    final fullLogoAsset = getFullLogoAsset(brightness);

    return AnimatedContainer(
      width: isCompactNav ? compactSizeNav : normalSizeNav,
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOut,
      color: colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 750),
              curve: Curves.easeInOut,
              height: isCompactNav ? compactLogoHeight : expandedLogoHeight,
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 750),
                switchOutCurve: const Interval(0.0, 1.0, curve: Curves.easeOut),
                switchInCurve: const Interval(0.5, 1.0, curve: Curves.easeIn),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  );
                },
                child: isCompactNav
                    ? Image.asset(
                        compactLogoAsset,
                        key: ValueKey('compactLogo-$compactLogoAsset'),
                        fit: BoxFit.contain,
                      )
                    : Image.asset(
                        fullLogoAsset,
                        key: ValueKey('fullLogo-$fullLogoAsset'),
                        fit: BoxFit.contain,
                      ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                return NavbarItem(
                  label: items[i].label,
                  icon: items[i].icon,
                  index: i,
                  selectedIndex: selectedIndex,
                  onTap: onTap,
                  isCompactNav: isCompactNav,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
