class EditableKennzeichenRow {
  EditableKennzeichenRow({
    required this.localRowId,
    required this.id,
    required this.teacherName,
    required this.licensePlate,
  });

  final int localRowId;
  final int id;
  String teacherName;
  String licensePlate;
  bool isBusy = false;
}
