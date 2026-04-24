import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gated/features/auth/browser_autofill_text_field.dart';
import 'package:gated/features/auth/browser_autofill_text_field_keys.dart';

void main() {
  testWidgets('uses browser mode first and preserves value after handoff', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _AutofillFieldHarness())),
    );

    expect(find.byKey(browserAutofillBrowserFieldKey), findsOneWidget);
    expect(find.byKey(browserAutofillFlutterFieldKey), findsNothing);

    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.tap(find.byKey(_toggleModeKey));
    await tester.pump();

    expect(find.byKey(browserAutofillBrowserFieldKey), findsNothing);
    expect(find.byKey(browserAutofillFlutterFieldKey), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
  });

  testWidgets('validator and submit keep working after handoff', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _AutofillFieldHarness())),
    );

    await tester.tap(find.byKey(_validateKey));
    await tester.pump();
    expect(find.text('Bitte Wert eingeben.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'filled');
    await tester.tap(find.byKey(_toggleModeKey));
    await tester.pump();

    await tester.showKeyboard(find.byType(TextFormField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('submitted: filled'), findsOneWidget);

    await tester.tap(find.byKey(_validateKey));
    await tester.pump();
    expect(find.text('Bitte Wert eingeben.'), findsNothing);
  });

  testWidgets('password visibility toggle still works after handoff', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: _AutofillFieldHarness(isPasswordField: true)),
      ),
    );

    await tester.tap(find.byKey(_toggleModeKey));
    await tester.pump();

    expect(_editableText(tester).obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_off_rounded));
    await tester.pump();

    expect(_editableText(tester).obscureText, isFalse);
  });

  testWidgets('handoff keeps the caret collapsed after focus restore', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: _AutofillFieldHarness(initialText: 'autofilled-password'),
        ),
      ),
    );

    await tester.tap(find.byKey(_toggleModeKey));
    await tester.pump();

    await tester.tap(find.byType(TextFormField));
    await tester.pump();

    final selection = _textFormFieldController(tester).selection;
    expect(selection.isCollapsed, isTrue);
    expect(selection.baseOffset, 'autofilled-password'.length);
    expect(selection.extentOffset, 'autofilled-password'.length);
  });
}

EditableText _editableText(WidgetTester tester) {
  return tester.widget<EditableText>(find.byType(EditableText));
}

TextEditingController _textFormFieldController(WidgetTester tester) {
  return tester.widget<TextFormField>(find.byType(TextFormField)).controller!;
}

const _toggleModeKey = ValueKey<String>('toggle-mode');
const _validateKey = ValueKey<String>('validate-form');

class _AutofillFieldHarness extends StatefulWidget {
  const _AutofillFieldHarness({
    this.isPasswordField = false,
    this.initialText = '',
  });

  final bool isPasswordField;
  final String initialText;

  @override
  State<_AutofillFieldHarness> createState() => _AutofillFieldHarnessState();
}

class _AutofillFieldHarnessState extends State<_AutofillFieldHarness> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool _preferFlutterField = false;
  bool _obscureText = true;
  String _submittedValue = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialText.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: widget.initialText,
        selection: TextSelection.collapsed(offset: widget.initialText.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final suffixIcon = widget.isPasswordField
        ? IconButton(
            onPressed: () {
              setState(() {
                _obscureText = !_obscureText;
              });
            },
            icon: Icon(
              _obscureText
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
            ),
          )
        : null;

    return Material(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrowserAutofillTextField(
              controller: _controller,
              focusNode: _focusNode,
              preferFlutterField: _preferFlutterField,
              autocomplete: widget.isPasswordField
                  ? 'current-password'
                  : 'email',
              inputType: widget.isPasswordField ? 'password' : 'email',
              keyboardType: widget.isPasswordField
                  ? TextInputType.visiblePassword
                  : TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              obscureText: widget.isPasswordField ? _obscureText : false,
              enableSuggestions: !widget.isPasswordField,
              autocorrect: false,
              autofillHints: <String>[
                if (widget.isPasswordField)
                  AutofillHints.password
                else
                  AutofillHints.email,
              ],
              decoration: InputDecoration(
                labelText: widget.isPasswordField ? 'Passwort' : 'E-Mail',
                suffixIcon: suffixIcon,
              ),
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Bitte Wert eingeben.';
                }
                return null;
              },
              onFieldSubmitted: (value) {
                setState(() {
                  _submittedValue = value;
                });
              },
            ),
            TextButton(
              key: _toggleModeKey,
              onPressed: () {
                setState(() {
                  _preferFlutterField = !_preferFlutterField;
                });
              },
              child: const Text('toggle'),
            ),
            TextButton(
              key: _validateKey,
              onPressed: () {
                _formKey.currentState?.validate();
              },
              child: const Text('validate'),
            ),
            Text('submitted: $_submittedValue'),
          ],
        ),
      ),
    );
  }
}
