import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labelguard_mobile/l10n/strings.dart';
import 'package:labelguard_mobile/providers/language_provider.dart';
import 'package:labelguard_mobile/widgets/language_toggle.dart';
import 'package:provider/provider.dart';

/// A screen built with tr() in a helper, the way most screens are.
class _Screen extends StatelessWidget {
  const _Screen();

  Widget _title() => Text(tr('Scan Result'));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: _title(), actions: const [LanguageToggle()]),
        body: Text(tr('Scan #{id}', {'id': 46})),
      );
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppLanguage.tamil = false;
  });
  tearDown(() => AppLanguage.tamil = false);

  testWidgets('one tap switches an open screen to Tamil and back', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: const MaterialApp(home: _Screen()),
    ));
    expect(find.text('Scan Result'), findsOneWidget);
    expect(find.text('தமிழ்'), findsOneWidget);

    await tester.tap(find.text('தமிழ்'));
    await tester.pumpAndSettle();
    expect(find.text('ஸ்கேன் முடிவு'), findsOneWidget);
    expect(find.text('ஸ்கேன் #46'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Scan Result'), findsOneWidget);
  });

  testWidgets('the choice is saved for the next launch', (tester) async {
    await LanguageProvider().setTamil(true);
    expect(await const FlutterSecureStorage().read(key: 'app_language'), 'ta');
  });
}
