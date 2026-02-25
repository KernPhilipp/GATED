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

    return LayoutBuilder(
      builder: (context, constraints) {
        const minTableWidth = 500.0;
        const columnCount = 3;

        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minTableWidth;
        final tableWidth = availableWidth < minTableWidth
            ? minTableWidth
            : availableWidth;
        final columnWidth = tableWidth / columnCount;

        final theme = Theme.of(context);
        final borderColor = theme.dividerColor;
        final hintColor = theme.colorScheme.outline;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: tableWidth),
            child: DataTable(
              horizontalMargin: 0,
              columnSpacing: 0,
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
              columns: [
                DataColumn(label: _headerCell('Lehrer', columnWidth)),
                DataColumn(label: _headerCell('Kennzeichen', columnWidth)),
                DataColumn(label: _headerCell('Aktionen', columnWidth)),
              ],
              rows: [
                for (final row in rows)
                  DataRow.byIndex(
                    index: row.localRowId,
                    cells: [
                      DataCell(
                        _dataCell(
                          width: columnWidth,
                          child: TextField(
                            controller: row.teacherController,
                            enabled: !row.isBusy,
                            decoration: InputDecoration(
                              hintText: 'z.B. Max Mustermann',
                              hintStyle: TextStyle(color: hintColor),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ),
                      DataCell(
                        _dataCell(
                          width: columnWidth,
                          child: TextField(
                            controller: row.licensePlateController,
                            enabled: !row.isBusy,
                            decoration: InputDecoration(
                              hintText: 'z.B. HA123AB',
                              hintStyle: TextStyle(color: hintColor),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => onSaveRow(row),
                          ),
                        ),
                      ),
                      DataCell(
                        _dataCell(
                          width: columnWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: row.id == null
                                    ? 'Speichern'
                                    : 'Änderungen speichern',
                                onPressed: row.isBusy
                                    ? null
                                    : () => onSaveRow(row),
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

  Widget _headerCell(String text, double width) {
    return SizedBox(
      width: width,
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
}
