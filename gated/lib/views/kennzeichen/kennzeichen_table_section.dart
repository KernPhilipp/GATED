import 'package:flutter/material.dart';
import 'editable_kennzeichen_row.dart';

class KennzeichenTableSection extends StatelessWidget {
  const KennzeichenTableSection({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.isRefreshing,
    required this.onAddRow,
    required this.onRefresh,
    required this.onSaveRow,
    required this.onDeleteRow,
  });

  final List<EditableKennzeichenRow> rows;
  final bool isLoading;
  final bool isRefreshing;
  final VoidCallback onAddRow;
  final VoidCallback onRefresh;
  final ValueChanged<EditableKennzeichenRow> onSaveRow;
  final ValueChanged<EditableKennzeichenRow> onDeleteRow;

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
              onPressed: onAddRow,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Eintrag hinzufügen'),
            ),
            OutlinedButton.icon(
              onPressed: isRefreshing ? null : onRefresh,
              icon: isRefreshing
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: const Text('Aktualisieren'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return Column(children: [Center(child: CircularProgressIndicator())]);
    }

    if (rows.isEmpty) {
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final borderColor = theme.dividerColor;

          return DataTable(
            columnSpacing: 20,
            headingRowHeight: 50,
            dataRowMaxHeight: 80,
            border: TableBorder(
              top: BorderSide(color: borderColor, width: 3),
              right: BorderSide(color: borderColor, width: 3),
              bottom: BorderSide(color: borderColor, width: 3),
              left: BorderSide(color: borderColor, width: 3),
              horizontalInside: BorderSide(color: borderColor, width: 1),
              verticalInside: BorderSide(color: borderColor, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            columns: const [
              DataColumn(label: Text('Lehrer')),
              DataColumn(label: Text('Kennzeichen')),
              DataColumn(label: Text('Aktionen')),
            ],
            rows: [
              for (final row in rows)
                DataRow.byIndex(
                  index: row.localRowId,
                  cells: [
                    DataCell(
                      TextField(
                        controller: row.teacherController,
                        enabled: !row.isBusy,
                        decoration: InputDecoration(
                          hintText: 'z.B. Max Mustermann',
                          hintStyle: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    DataCell(
                      TextField(
                        controller: row.licensePlateController,
                        enabled: !row.isBusy,
                        decoration: InputDecoration(
                          hintText: 'z.B. HA123AB',
                          hintStyle: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => onSaveRow(row),
                      ),
                    ),
                    DataCell(
                      Row(
                        children: [
                          IconButton(
                            tooltip: row.id == null
                                ? 'Speichern'
                                : 'Änderungen speichern',
                            onPressed: row.isBusy ? null : () => onSaveRow(row),
                            icon: row.isBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                          ),
                          IconButton(
                            tooltip: 'Löschen',
                            onPressed: row.isBusy
                                ? null
                                : () => onDeleteRow(row),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
