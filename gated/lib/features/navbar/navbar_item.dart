import 'package:flutter/material.dart';
import 'navbar_constants.dart';

class NavbarItem extends StatelessWidget {
  final String label;
  final int index;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final IconData icon;
  final bool isCompactNav;

  const NavbarItem({
    super.key,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.onTap,
    required this.icon,
    required this.isCompactNav,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelBaseStyle = theme.textTheme.titleMedium ?? const TextStyle();
    final selected = index == selectedIndex;
    const animationDuration = Duration(milliseconds: 100);

    return InkWell(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textFactor =
                ((constraints.maxWidth - compactSizeNav) /
                        (normalSizeNav - compactSizeNav))
                    .clamp(0.0, 1.0);
            final textHidden = textFactor <= 0;
            return AnimatedAlign(
              alignment: isCompactNav && textHidden
                  ? Alignment.center
                  : Alignment.centerLeft,
              duration: Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: animationDuration,
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selected ? colorScheme.primary : null,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: TweenAnimationBuilder<Color?>(
                      duration: animationDuration,
                      curve: Curves.easeInOut,
                      tween: ColorTween(
                        end: selected
                            ? colorScheme.onPrimary
                            : colorScheme.primary,
                      ),
                      builder: (context, color, child) {
                        return Icon(icon, color: color);
                      },
                    ),
                  ),
                  if (constraints.maxWidth > compactSizeNav)
                    Flexible(
                      fit: FlexFit.loose,
                      child: AnimatedOpacity(
                        opacity: textFactor,
                        duration: animationDuration,
                        curve: Curves.easeInOut,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: AnimatedDefaultTextStyle(
                            duration: animationDuration,
                            curve: Curves.easeInOut,
                            style: labelBaseStyle.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              color: selected
                                  ? colorScheme.secondary
                                  : colorScheme.primary,
                            ),
                            child: Text(label, maxLines: 1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
