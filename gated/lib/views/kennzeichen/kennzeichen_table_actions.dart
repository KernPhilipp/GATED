import 'package:flutter/material.dart';

class KennzeichenTableActions extends StatelessWidget {
  const KennzeichenTableActions({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.isRefreshing,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onAddRow,
    required this.onRefresh,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final bool isRefreshing;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onAddRow;
  final VoidCallback onRefresh;

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
              onPressed: searchQuery.isNotEmpty ? null : onAddRow,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Eintrag hinzufügen'),
              style: searchQuery.isNotEmpty
                  ? FilledButton.styleFrom(
                      foregroundColor: Theme.of(context).disabledColor,
                      backgroundColor: Theme.of(context).disabledColor,
                    )
                  : null,
            ),
            OutlinedButton.icon(
              onPressed: isRefreshing ? null : onRefresh,
              icon: isRefreshing
                  ? Padding(
                      padding: const EdgeInsets.only(right: 2, left: 2),
                      child: const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: const Text('Aktualisieren'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            labelText: 'Suche',
            hintText: 'Nach Lehrer oder Kennzeichen filtern',
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
