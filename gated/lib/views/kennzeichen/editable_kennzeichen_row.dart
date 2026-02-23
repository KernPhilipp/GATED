import 'package:flutter/material.dart';

class EditableKennzeichenRow {
  EditableKennzeichenRow({
    required this.localRowId,
    required String teacherName,
    required String licensePlate,
    this.id,
  }) : teacherController = TextEditingController(text: teacherName),
       licensePlateController = TextEditingController(text: licensePlate);

  final int localRowId;
  int? id;
  bool isBusy = false;
  final TextEditingController teacherController;
  final TextEditingController licensePlateController;

  void dispose() {
    teacherController.dispose();
    licensePlateController.dispose();
  }
}
