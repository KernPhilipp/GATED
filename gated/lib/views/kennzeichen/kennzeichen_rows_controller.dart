import '../../services/kennzeichen_service.dart';
import 'editable_kennzeichen_row.dart';

class KennzeichenRowsController {
  KennzeichenRowsController({KennzeichenService? service})
    : _service = service ?? KennzeichenService();

  final KennzeichenService _service;
  int _nextLocalRowId = 0;

  Future<List<EditableKennzeichenRow>> loadRows() async {
    final entries = await _service.fetchEntries();
    return entries.map(_toEditableRow).toList();
  }

  Future<EditableKennzeichenRow> createRow({
    required String teacherName,
    required String licensePlate,
  }) async {
    final saved = await _service.createEntry(
      teacherName: teacherName,
      licensePlate: licensePlate,
    );

    return _toEditableRow(saved);
  }

  Future<KennzeichenEntry> updateRow({
    required EditableKennzeichenRow row,
    required String teacherName,
    required String licensePlate,
  }) {
    return _service.updateEntry(
      id: row.id,
      teacherName: teacherName,
      licensePlate: licensePlate,
    );
  }

  Future<void> deleteRow(EditableKennzeichenRow row) {
    return _service.deleteEntry(row.id);
  }

  void applyUpdatedEntry(EditableKennzeichenRow row, KennzeichenEntry entry) {
    row.teacherName = entry.teacherName;
    row.licensePlate = entry.licensePlate;
  }

  EditableKennzeichenRow _toEditableRow(KennzeichenEntry entry) {
    return EditableKennzeichenRow(
      localRowId: _nextLocalRowId++,
      id: entry.id,
      teacherName: entry.teacherName,
      licensePlate: entry.licensePlate,
    );
  }
}
