import 'ta.dart';

/// The app's language: English (default) or Tamil.
///
/// Every user-facing string is written in English and wrapped in [tr]; the
/// English text is the key into the Tamil table in `ta.dart`. A string with
/// no Tamil entry shows in English rather than blank, and
/// `test/l10n_test.dart` fails the build if any wrapped string is missing.
///
/// [tr] reads a static flag so it works in helper methods with no
/// BuildContext. Switching language rebuilds every widget (see
/// LanguageProvider), so nothing keeps the old text on screen.
class AppLanguage {
  AppLanguage._();

  static bool tamil = false;

  /// Code for the API's `lang` parameter and Flutter's Locale.
  static String get code => tamil ? 'ta' : 'en';
}

/// Translate [en] into the current language, filling `{name}` placeholders
/// from [args]: `tr('Scan #{id}', {'id': 46})`.
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = AppLanguage.tamil ? (ta[en] ?? en) : en;
  args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}

/// Rule names arrive from the server in English; show them in Tamil by
/// rule number (1–13), keeping the English name as the fallback.
String trRuleName(int ruleNumber, String english) =>
    AppLanguage.tamil ? (taRuleNames[ruleNumber] ?? english) : english;

/// PASS / FAIL / REVIEW / EXEMPT as shown to people.
String trCheckStatus(String status) => switch (status.toUpperCase()) {
      'PASS' => tr('PASS'),
      'FAIL' => tr('FAIL'),
      'REVIEW' => tr('REVIEW'),
      'EXEMPT' => tr('EXEMPT'),
      _ => status.toUpperCase(),
    };
