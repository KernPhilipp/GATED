import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gated/services/admin_service.dart';
import 'package:gated/services/auth_service.dart';
import 'package:gated/services/email_draft_service.dart';
import 'package:gated/views/admin_view.dart';
import 'package:gated/views/kennzeichen/editable_kennzeichen_row.dart';
import 'package:gated/views/kennzeichen/kennzeichen_data_table.dart';
import 'package:gated/widgets/horizontal_table_scroll_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('horizontal table wrapper scrolls with a mouse drag', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: HorizontalTableScrollView(
              child: SizedBox(width: 900, height: 80),
            ),
          ),
        ),
      ),
    );

    final scrollableState = tester.state<ScrollableState>(
      find.byType(Scrollable),
    );
    expect(scrollableState.position.pixels, 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(tester.getCenter(find.byType(SingleChildScrollView)));
    await tester.pump();
    await gesture.moveBy(const Offset(-250, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(scrollableState.position.pixels, greaterThan(0));
  });

  testWidgets('kennzeichen table renders a visible horizontal scrollbar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: KennzeichenDataTable(
              rows: [
                EditableKennzeichenRow(
                  localRowId: 0,
                  id: 1,
                  teacherName: 'Max Mustermann',
                  licensePlate: 'W-12345',
                ),
              ],
              sortColumnIndex: null,
              sortAscending: true,
              onSort: (_, _) {},
              onEditRow: (_) {},
              onDeleteRow: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(_findHorizontalTableScrollbar(), findsOneWidget);
  });

  testWidgets('admin table renders a visible horizontal scrollbar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminView(
            adminService: _FakeAdminService(
              users: const [
                AdminUser(
                  id: 1,
                  email: 'user@example.com',
                  role: AuthUserRole.user,
                  isRegistered: true,
                  createdAt: null,
                ),
              ],
            ),
            emailDraftService: _FakeEmailDraftService(),
            authService: _FakeAuthService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_findHorizontalTableScrollbar(), findsOneWidget);
  });
}

Finder _findHorizontalTableScrollbar() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Scrollbar &&
        widget.thumbVisibility == true &&
        widget.trackVisibility == true &&
        widget.interactive == true &&
        widget.scrollbarOrientation == ScrollbarOrientation.bottom,
  );
}

class _FakeAdminService extends AdminService {
  _FakeAdminService({required this.users})
    : super(authService: AuthService(baseUrl: 'http://localhost'));

  final List<AdminUser> users;

  @override
  Future<List<AdminUser>> fetchUsers() async => users;
}

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(baseUrl: 'http://localhost');

  @override
  Future<String?> readAccessToken() async => null;
}

class _FakeEmailDraftService extends EmailDraftService {}
