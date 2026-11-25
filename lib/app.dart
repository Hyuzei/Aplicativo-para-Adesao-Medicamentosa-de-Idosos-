import 'dart:async';

import 'package:flutter/material.dart';

import 'features/auth/data/firebase_auth_service.dart';
import 'features/auth/data/local_auth_service.dart';
import 'features/auth/data/local_account_repository.dart';
import 'features/auth/models/user_account.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/family/data/firebase_care_service.dart';
import 'features/home/presentation/medication_prototype_app.dart';
import 'services/notification_service.dart';

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.accountRepository,
    this.authenticationService,
    this.careService,
  });

  final AccountRepository? accountRepository;
  final AuthenticationService? authenticationService;
  final CareService? careService;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _largeText = false;
  bool _darkMode = false;
  bool _sessionLoading = true;
  UserAccount? _account;
  String? _sessionError;
  late final AccountRepository _accountRepository =
      widget.accountRepository ?? PreferencesAccountRepository();
  late final AuthenticationService _authenticationService =
      widget.authenticationService ??
      (widget.accountRepository != null
          ? LocalAuthService(_accountRepository)
          : FirebaseAuthService());
  late final CareService? _careService =
      widget.careService ??
      (widget.accountRepository != null ? null : FirebaseCareService());

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    try {
      final account = await _authenticationService.restoreSession();
      if (!mounted) return;
      setState(() => _account = account);
    } catch (error, stackTrace) {
      debugPrint('Falha ao restaurar sessão: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _sessionError = error is LocalAuthException
            ? error.message
            : 'Não foi possível restaurar sua sessão: $error';
      });
    } finally {
      if (mounted) setState(() => _sessionLoading = false);
    }
  }

  void _signIn(UserAccount account) {
    setState(() {
      _account = account;
      _sessionError = null;
    });
  }

  Future<void> _signOut() async {
    // Antes do signOut: remover o token FCM exige o usuário ainda autenticado.
    // Sem isso o próximo usuário deste aparelho receberia os avisos deste.
    if (_careService != null) {
      await NotificationService.instance.unregisterPushToken();
    }
    unawaited(NotificationService.instance.cancelAllReminders());
    await _authenticationService.signOut();
    if (!mounted) return;
    setState(() => _account = null);
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A99D),
          brightness: brightness,
        ).copyWith(
          surface: isDark ? const Color(0xFF0D151D) : const Color(0xFFF4F8FA),
          surfaceContainerLowest: isDark
              ? const Color(0xFF0A1118)
              : const Color(0xFFFFFFFF),
          surfaceContainerLow: isDark
              ? const Color(0xFF14212B)
              : const Color(0xFFFFFFFF),
          surfaceContainer: isDark
              ? const Color(0xFF1A2A35)
              : const Color(0xFFEAF1F4),
          outline: isDark ? const Color(0xFF344955) : const Color(0xFFD5E1E6),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 19,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 16,
          height: 1.35,
        ),
        labelLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 60),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 60),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(52, 52),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.7)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        height: 84,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 16,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outline.withValues(alpha: 0.65),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cuidar+',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final systemTextScaler = mediaQuery.textScaler;
        final textScaler = _largeText && systemTextScaler.scale(1) < 2
            ? TextScaler.linear(2)
            : systemTextScaler;
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: textScaler),
          child: child!,
        );
      },
      home: _sessionLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _account == null
          ? AuthScreen(
              repository: _accountRepository,
              authService: _authenticationService,
              initialError: _sessionError,
              onAuthenticated: _signIn,
            )
          : MedicationPrototypeApp(
              account: _account!,
              careService: _careService,
              largeText: _largeText,
              onLargeTextChanged: (value) => setState(() => _largeText = value),
              darkMode: _darkMode,
              onDarkModeChanged: (value) => setState(() => _darkMode = value),
              onSignOut: _signOut,
            ),
    );
  }
}
