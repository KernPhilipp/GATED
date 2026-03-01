import 'package:flutter/material.dart';
import 'editable_kennzeichen_row.dart';

class KennzeichenDataTable extends StatelessWidget {
  const KennzeichenDataTable({
    super.key,
    required this.rows,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
    required this.onEditRow,
    required this.onDeleteRow,
  });

  final List<EditableKennzeichenRow> rows;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending) onSort;
  final ValueChanged<EditableKennzeichenRow> onEditRow;
  final ValueChanged<EditableKennzeichenRow> onDeleteRow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minTableWidth = 350.0;
        const minTableActionWidth = 120.0;
        const columnCount = 3;
        const sortArrowIconSize = 16.0;
        const sortArrowPadding = 2.0;
        const sortIndicatorWidth = sortArrowIconSize + (sortArrowPadding * 2);
        const sortRightPadding = 10.0;

        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minTableWidth;
        final tableWidth = availableWidth < minTableWidth
            ? minTableWidth
            : availableWidth;
        final columnWidth = tableWidth / columnCount;
        final tableActionWidth = columnWidth < minTableActionWidth
            ? minTableActionWidth
            : columnWidth;

        final borderColor = Theme.of(context).dividerColor;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: tableWidth),
            child: DataTable(
              horizontalMargin: 0,
              columnSpacing: 0,
              headingRowHeight: 50,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 72,
              sortColumnIndex: sortColumnIndex,
              sortAscending: sortAscending,
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
                DataColumn(
                  headingRowAlignment: MainAxisAlignment.start,
                  label: _headerCell(
                    'Lehrer',
                    columnWidth,
                    isSortable: true,
                    sortIndicatorWidth: sortIndicatorWidth,
                    sortRightPadding: sortRightPadding,
                  ),
                  onSort: onSort,
                ),
                DataColumn(
                  headingRowAlignment: MainAxisAlignment.start,
                  label: _headerCell(
                    'Kennzeichen',
                    columnWidth,
                    isSortable: true,
                    sortIndicatorWidth: sortIndicatorWidth,
                    sortRightPadding: sortRightPadding,
                  ),
                  onSort: onSort,
                ),
                DataColumn(label: _headerCell('Aktionen', tableActionWidth)),
              ],
              rows: [
                for (final row in rows)
                  DataRow.byIndex(
                    index: row.localRowId,
                    cells: [
                      DataCell(
                        _dataCell(
                          width: columnWidth,
                          child: Text(
                            row.teacherName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        _dataCell(
                          width: columnWidth,
                          child: Text(
                            row.licensePlate,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        _buttonCell(
                          width: tableActionWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Bearbeiten',
                                onPressed: row.isBusy
                                    ? null
                                    : () => onEditRow(row),
                                icon: const Icon(Icons.edit_rounded),
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

  Widget _headerCell(
    String text,
    double width, {
    bool isSortable = false,
    double sortIndicatorWidth = 0,
    double sortRightPadding = 0,
  }) {
    final adjustedWidth = isSortable
        ? (width - sortIndicatorWidth - sortRightPadding).clamp(0.0, width)
        : width;

    return SizedBox(
      width: adjustedWidth,
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

  Widget _buttonCell({required double width, required Widget child}) {
    return SizedBox(width: width, child: child);
  }
}
