import 'package:flutter/material.dart';
import 'editable_kennzeichen_row.dart';
import 'kennzeichen_data_table.dart';
import 'kennzeichen_table_actions.dart';

class KennzeichenTableSection extends StatelessWidget {
  const KennzeichenTableSection({
    super.key,
    required this.rows,
    required this.hasAnyRows,
    required this.searchController,
    required this.searchQuery,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.isLoading,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSort,
    required this.onAddRow,
    required this.onEditRow,
    required this.onDeleteRow,
  });

  final List<EditableKennzeichenRow> rows;
  final bool hasAnyRows;
  final TextEditingController searchController;
  final String searchQuery;
  final int? sortColumnIndex;
  final bool sortAscending;
  final bool isLoading;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final void Function(int columnIndex, bool ascending) onSort;
  final VoidCallback onAddRow;
  final ValueChanged<EditableKennzeichenRow> onEditRow;
  final ValueChanged<EditableKennzeichenRow> onDeleteRow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KennzeichenTableActions(
          searchController: searchController,
          searchQuery: searchQuery,
          onSearchChanged: onSearchChanged,
          onClearSearch: onClearSearch,
          onAddRow: onAddRow,
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
      return const Center(child: CircularProgressIndicator());
    }

    if (!hasAnyRows && searchQuery.isEmpty) {
      return Column(
        children: [
          const Text('Noch keine Kennzeichen vorhanden.'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAddRow,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ersten Eintrag anlegen'),
          ),
        ],
      );
    }

    if (rows.isEmpty) {
      return Center(child: Text('Keine Treffer für "$searchQuery".'));
    }

    return KennzeichenDataTable(
      rows: rows,
      sortColumnIndex: sortColumnIndex,
      sortAscending: sortAscending,
      onSort: onSort,
      onEditRow: onEditRow,
      onDeleteRow: onDeleteRow,
    );
  }
}
