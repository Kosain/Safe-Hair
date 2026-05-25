import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'core/app_theme.dart';
import 'core/providers/app_providers.dart';
import 'core/router.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      Firebase.app();
    }
    FirebaseService.markInitialized();
  } catch (e) {
    // Keep app booting, but expose init issue in logs so auth failures are diagnosable.
    final msg = e.toString();
    if (msg.contains('duplicate-app') || msg.contains('[core/duplicate-app]')) {
      FirebaseService.markInitialized();
      debugPrint('Firebase already initialized (duplicate-app), continuing.');
    } else {
      FirebaseService.lastInitError = 'Firebase initialization failed: $e';
      debugPrint('Firebase initialization error: $e');
    }
  }
  runApp(const SafeHairApp());
}

class SafeHairApp extends StatelessWidget {
  const SafeHairApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: buildCoreProviders(),
      child: const _AppRouterHost(),
    );
  }
}

class _AppRouterHost extends StatefulWidget {
  const _AppRouterHost();

  @override
  State<_AppRouterHost> createState() => _AppRouterHostState();
}

class _AppRouterHostState extends State<_AppRouterHost> {
  late final AuthProvider _auth;
  late final dynamic _router;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    // Keep one router instance; theme changes should not reset navigation.
    _router = createRouter(_auth);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final locale = context.watch<LocaleProvider>();
    return MaterialApp.router(
      title: 'Safe Hair',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: theme.themeMode,
      locale: locale.locale,
      supportedLocales: const [Locale('en'), Locale('ur')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (deviceLocale, supported) {
        final code = locale.languageCode;
        if (code == 'ur') return const Locale('ur');
        return const Locale('en');
      },
      builder: (context, child) {
        final isRtl = locale.languageCode == 'ur';
        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: _router,
    );
  }
}
