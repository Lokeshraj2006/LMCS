import 'package:flutter/widgets.dart';

import '../l10n/strings.dart';
import '../services/settings_service.dart';

/// English or Tamil, switched with one tap and remembered across launches.
class LanguageProvider extends ChangeNotifier {
  bool get tamil => AppLanguage.tamil;

  Locale get locale => Locale(AppLanguage.code);

  Future<void> toggle() => setTamil(!AppLanguage.tamil);

  Future<void> setTamil(bool on) async {
    if (on == AppLanguage.tamil) return;
    AppLanguage.tamil = on;
    notifyListeners();
    // tr() reads a static flag, so widgets that didn't change otherwise
    // would keep their old text. Marking the whole tree dirty rebuilds
    // every screen in place: the open screen, its state and the back stack
    // all stay as they were.
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
    await SettingsService.setLanguage(AppLanguage.code);
  }
}
