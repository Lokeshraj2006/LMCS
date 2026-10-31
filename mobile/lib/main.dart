import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/compliance_provider.dart';
import 'providers/inspection_log_provider.dart';
import 'providers/inspection_provider.dart';
import 'providers/language_provider.dart';
import 'providers/pending_complaints_provider.dart';
import 'providers/scan_provider.dart';
import 'screens/splash_screen.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the saved backend URL before any provider builds an ApiService,
  // so the very first request already uses the user's override.
  await SettingsService.load();
  runApp(const LMCSApp());
}

class LMCSApp extends StatelessWidget {
  const LMCSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ComplianceProvider()),
        ChangeNotifierProvider(create: (_) => InspectionProvider()),
        ChangeNotifierProvider(create: (_) => ScanProvider()),
        ChangeNotifierProvider(create: (_) => InspectionLogProvider()),
        ChangeNotifierProvider(create: (_) => PendingComplaintsProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, lang, _) => MaterialApp(
        title: 'LMCS',
        debugShowCheckedModeBanner: false,
        // Flutter's own widgets (back buttons, date pickers) follow the
        // app's language too.
        locale: lang.locale,
        supportedLocales: const [Locale('en'), Locale('ta')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
          ),
          cardTheme: const CardThemeData(
            elevation: 1,
            margin: EdgeInsets.zero,
          ),
        ),
        home: const SplashScreen(),
        ),
      ),
    );
  }
}
