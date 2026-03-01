import 'editable_kennzeichen_row.dart';

List<EditableKennzeichenRow> buildVisibleKennzeichenRows({
  required List<EditableKennzeichenRow> rows,
  required String searchQuery,
  required int? sortColumnIndex,
  required bool sortAscending,
}) {
  final normalizedQuery = searchQuery.trim().toLowerCase();

  final visibleRows = normalizedQuery.isEmpty
      ? List<EditableKennzeichenRow>.from(rows)
      : rows.where((row) {
          final teacher = row.teacherName.trim().toLowerCase();
          final licensePlate = row.licensePlate.trim().toLowerCase();
          return teacher.contains(normalizedQuery) ||
              licensePlate.contains(normalizedQuery);
        }).toList();

  if (sortColumnIndex == null) {
    return visibleRows;
  }

  visibleRows.sort((a, b) {
    final result = switch (sortColumnIndex) {
      0 => a.teacherName.trim().toLowerCase().compareTo(
        b.teacherName.trim().toLowerCase(),
      ),
      1 => a.licensePlate.trim().toLowerCase().compareTo(
        b.licensePlate.trim().toLowerCase(),
      ),
      _ => a.localRowId.compareTo(b.localRowId),
    };

    return sortAscending ? result : -result;
  });

  return visibleRows;
}
