import 'package:flutter/material.dart';

class KennzeichenTableActions extends StatelessWidget {
  const KennzeichenTableActions({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onAddRow,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onAddRow;

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
