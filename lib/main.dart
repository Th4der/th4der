import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_language.dart';
import 'chat_api.dart';

const String _defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.1.8:8000',
);
const String _webrtcStunUrls = String.fromEnvironment(
  'WEBRTC_STUN_URLS',
  defaultValue: 'stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302',
);
const String _webrtcTurnUrl = String.fromEnvironment(
  'WEBRTC_TURN_URL',
  defaultValue: '',
);
const String _webrtcTurnUsername = String.fromEnvironment(
  'WEBRTC_TURN_USERNAME',
  defaultValue: '',
);
const String _webrtcTurnCredential = String.fromEnvironment(
  'WEBRTC_TURN_CREDENTIAL',
  defaultValue: '',
);
const bool _webrtcForceRelay = bool.fromEnvironment(
  'WEBRTC_FORCE_RELAY',
  defaultValue: false,
);
const bool _webrtcUseAiortc = bool.fromEnvironment(
  'WEBRTC_USE_AIORTC',
  defaultValue: true,
);
const String _prefsAuthTokenKey = 'th4der_auth_token';
const String _prefsUserIdKey = 'th4der_user_id';

Uri _callWebSocketUri(ChatApi api) {
  final base = Uri.parse(_defaultApiBaseUrl);
  final scheme = base.scheme == 'https' ? 'wss' : 'ws';
  final query = <String, String>{'user_id': '${api.currentUserId}'};
  if (api is HttpChatApi) {
    final token = api.authToken;
    if (token != null && token.isNotEmpty) {
      query['token'] = token;
    }
  }
  return base.replace(
    scheme: scheme,
    path: '/ws/calls',
    queryParameters: query,
  );
}

Route<T> _buildSmoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, _, _) => page,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 230),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0.0, 0.03),
        end: Offset.zero,
      ).animate(curved);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

void main() {
  runApp(const Th4derApp());
}

class AppBlue {
  static const bgTop = Color(0xFF041C3D);
  static const bgMid = Color(0xFF073069);
  static const bgBottom = Color(0xFF0A3E80);
  static const surface = Color(0xFF0F2C58);
  static const surfaceElevated = Color(0xFF143568);
  static const accent = Color(0xFF2D8CFF);
  static const accentSoft = Color(0xFF76BAFF);
  static const accentDeep = Color(0xFF1E5EBD);
  static const accentNavy = Color(0xFF113B7A);
  static const success = Color(0xFF66B6FF);
  static const onlineDot = Color(0xFF46D26A);
  static const onlineDotSoft = Color(0x6646D26A);
  static const dangerSoft = Color(0xFF8EBEFF);
  static const outline = Color(0x335FA9FF);
  static const outlineStrong = Color(0x6679BDFF);
  static const shadow = Color(0x330A2D63);
  static const text = Color(0xFFF1F7FF);
  static const textMuted = Color(0xFF9BB7DB);
}

class Th4derApp extends StatefulWidget {
  const Th4derApp({
    super.key,
    this.api,
    this.authApi,
    this.currentUser,
    this.initialLanguage,
  });

  final ChatApi? api;
  final AuthApi? authApi;
  final UserProfile? currentUser;
  final AppLanguage? initialLanguage;

  @override
  State<Th4derApp> createState() => _Th4derAppState();
}

class _Th4derAppState extends State<Th4derApp> {
  ChatApi? _api;
  late final AuthApi _authApi;
  UserProfile? _currentUser;
  late AppLanguage _language;
  bool _authRestoring = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api;
    _currentUser = widget.currentUser;
    _authApi = widget.authApi ?? AuthApi(baseUrl: _defaultApiBaseUrl);
    _language =
        widget.initialLanguage ??
        AppLanguage.fromCode(
          WidgetsBinding.instance.platformDispatcher.locale.languageCode,
        );
    if (_api == null) {
      _authRestoring = true;
      unawaited(_restorePersistedSession());
    }
  }

  void _onAuthenticated(AuthSession session) {
    final api = HttpChatApi(
      baseUrl: _defaultApiBaseUrl,
      currentUserId: session.user.id,
      authToken: session.token,
    );
    setState(() {
      _api = api;
      _currentUser = session.user;
    });
    unawaited(
      _savePersistedSession(token: session.token, userId: session.user.id),
    );
  }

  void _logout() {
    FocusManager.instance.primaryFocus?.unfocus();
    final api = _api;
    if (api != null) {
      unawaited(api.logout().catchError((Object _) {}));
    }
    unawaited(_clearPersistedSession());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _api = null;
        _currentUser = null;
      });
    });
  }

  void _onLanguageChanged(AppLanguage language) {
    if (_language == language) return;
    setState(() => _language = language);
  }

  Future<void> _savePersistedSession({
    required String token,
    required int userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAuthTokenKey, token);
    await prefs.setInt(_prefsUserIdKey, userId);
  }

  Future<void> _clearPersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsAuthTokenKey);
    await prefs.remove(_prefsUserIdKey);
  }

  Future<void> _restorePersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsAuthTokenKey)?.trim() ?? '';
      final userId = prefs.getInt(_prefsUserIdKey);
      if (token.isEmpty || userId == null) {
        if (!mounted) return;
        setState(() => _authRestoring = false);
        return;
      }

      final api = HttpChatApi(
        baseUrl: _defaultApiBaseUrl,
        currentUserId: userId,
        authToken: token,
      );
      final user = await api.fetchCurrentUser();

      if (!mounted) return;
      setState(() {
        _api = api;
        _currentUser = user;
        _authRestoring = false;
      });
      if (user.id != userId) {
        unawaited(_savePersistedSession(token: token, userId: user.id));
      }
    } catch (_) {
      await _clearPersistedSession();
      if (!mounted) return;
      setState(() => _authRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppBlue.accent,
        brightness: Brightness.dark,
      ),
    );
    return MaterialApp(
      key: ValueKey<bool>(_api != null),
      debugShowCheckedModeBanner: false,
      title: 'Th4der',
      locale: Locale(_language.code),
      supportedLocales: const [Locale('en'), Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: base.copyWith(
        scaffoldBackgroundColor: AppBlue.bgTop,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppBlue.text,
        ),
        cardTheme: CardThemeData(
          color: AppBlue.surface.withValues(alpha: 0.86),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: AppBlue.outline.withValues(alpha: 0.8)),
          ),
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppBlue.accent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        chipTheme: base.chipTheme.copyWith(
          backgroundColor: AppBlue.surfaceElevated.withValues(alpha: 0.9),
          selectedColor: AppBlue.accent.withValues(alpha: 0.35),
          labelStyle: const TextStyle(color: AppBlue.textMuted),
          secondaryLabelStyle: const TextStyle(color: AppBlue.text),
          side: BorderSide(color: AppBlue.outline.withValues(alpha: 0.9)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          indicatorColor: AppBlue.accent.withValues(alpha: 0.3),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected)
                  ? AppBlue.text
                  : AppBlue.textMuted,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            );
          }),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppBlue.surfaceElevated,
          contentTextStyle: const TextStyle(color: AppBlue.text),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppBlue.outline.withValues(alpha: 0.9)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppBlue.surfaceElevated.withValues(alpha: 0.84),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          labelStyle: const TextStyle(color: AppBlue.textMuted),
          hintStyle: const TextStyle(color: AppBlue.textMuted),
          prefixIconColor: AppBlue.accentSoft,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: AppBlue.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: AppBlue.outline.withValues(alpha: 0.7),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: AppBlue.accentSoft.withValues(alpha: 0.95),
              width: 1.4,
            ),
          ),
        ),
      ),
      home: _authRestoring
          ? const _SessionRestoreScreen()
          : _api == null
          ? AuthScreen(
              key: const ValueKey('auth-screen'),
              authApi: _authApi,
              language: _language,
              onAuthenticated: _onAuthenticated,
            )
          : ChatHomeScreen(
              key: const ValueKey('chat-home'),
              api: _api!,
              language: _language,
              onLanguageChanged: _onLanguageChanged,
              initialUser: _currentUser,
              onLogout: _logout,
            ),
    );
  }
}

class _SessionRestoreScreen extends StatelessWidget {
  const _SessionRestoreScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: BlueBackground(child: Center(child: CircularProgressIndicator())),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.authApi,
    required this.language,
    required this.onAuthenticated,
  });

  final AuthApi authApi;
  final AppLanguage language;
  final ValueChanged<AuthSession> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  bool _registerMode = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = AppStrings(widget.language);
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = s.usernamePasswordRequired);
      return;
    }
    if (_registerMode && _displayName.text.trim().isEmpty) {
      setState(() => _error = s.displayNameRequired);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = _registerMode
          ? await widget.authApi.register(
              username: _username.text.trim(),
              displayName: _displayName.text.trim(),
              password: _password.text,
            )
          : await widget.authApi.login(
              username: _username.text.trim(),
              password: _password.text,
            );
      if (!mounted) return;
      widget.onAuthenticated(session);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(widget.language);
    return Scaffold(
      body: BlueBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppBlue.surfaceElevated.withValues(alpha: 0.95),
                        AppBlue.surface.withValues(alpha: 0.92),
                      ],
                    ),
                    border: Border.all(
                      color: AppBlue.outline.withValues(alpha: 0.95),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: AppBlue.shadow,
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [AppBlue.accentSoft, AppBlue.accent],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppBlue.accent.withValues(alpha: 0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.flash_on_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Th4der',
                          style: TextStyle(
                            color: AppBlue.text,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _registerMode ? s.createAccount : s.secureSignIn,
                          style: const TextStyle(color: AppBlue.textMuted),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _username,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          style: const TextStyle(color: AppBlue.text),
                          decoration: InputDecoration(
                            labelText: s.username,
                            prefixIcon: const Icon(
                              Icons.alternate_email_rounded,
                            ),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: _registerMode
                              ? Padding(
                                  key: const ValueKey('register-display-name'),
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: TextField(
                                    controller: _displayName,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.name],
                                    style: const TextStyle(color: AppBlue.text),
                                    decoration: InputDecoration(
                                      labelText: s.displayName,
                                      prefixIcon: const Icon(
                                        Icons.badge_outlined,
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('login-no-display-name'),
                                ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          onSubmitted: (_) => _submit(),
                          autofillHints: const [AutofillHints.password],
                          style: const TextStyle(color: AppBlue.text),
                          decoration: InputDecoration(
                            labelText: s.password,
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            style: const TextStyle(color: AppBlue.dangerSoft),
                          ),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_registerMode ? s.register : s.login),
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _registerMode = !_registerMode;
                                  _error = null;
                                }),
                          child: Text(
                            _registerMode
                                ? s.haveAccountLogin
                                : s.needAccountRegister,
                            style: const TextStyle(color: AppBlue.accentSoft),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({
    super.key,
    required this.api,
    required this.language,
    required this.onLanguageChanged,
    required this.onLogout,
    this.initialUser,
  });

  final ChatApi api;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onLogout;
  final UserProfile? initialUser;

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  final _search = TextEditingController();
  final List<ConversationSummary> _conversations = [];
  Timer? _pollTimer;
  bool _incomingCallDialogOpen = false;
  final Set<String> _handledIncomingCallIds = <String>{};
  bool _loading = true;
  bool _profileLoading = false;
  bool _profileSaving = false;
  bool _unreadOnly = false;
  bool _animationsEnabled = true;
  bool _showOnlineBadge = true;
  int _tabIndex = 0;
  String? _error;
  UserProfile? _currentUser;

  int get _totalUnread =>
      _conversations.fold<int>(0, (sum, item) => sum + item.unreadCount);

  @override
  void initState() {
    super.initState();
    _currentUser = widget.initialUser;
    _load();
    _loadCurrentUser(quiet: true);
    unawaited(_checkIncomingCalls());
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_load(quiet: true));
      unawaited(_checkIncomingCalls());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_load(), _loadCurrentUser()]);
  }

  Future<void> _checkIncomingCalls() async {
    if (_incomingCallDialogOpen) return;
    try {
      final s = AppStrings(widget.language);
      final calls = await widget.api.fetchIncomingCalls();
      if (!mounted || calls.isEmpty) return;
      final incoming = calls.firstWhere(
        (item) => !_handledIncomingCallIds.contains(item.session.id),
        orElse: () => calls.first,
      );
      if (_handledIncomingCallIds.contains(incoming.session.id)) {
        return;
      }
      _incomingCallDialogOpen = true;
      final callerName = incoming.session.peer?.displayName ?? s.unknownUser;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppBlue.surfaceElevated,
          title: Text(
            s.incomingCallTitle,
            style: const TextStyle(color: AppBlue.text),
          ),
          content: Text(
            s.incomingCallFrom(callerName),
            style: const TextStyle(color: AppBlue.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.decline),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.accept),
            ),
          ],
        ),
      );
      _incomingCallDialogOpen = false;
      _handledIncomingCallIds.add(incoming.session.id);

      if (!mounted) return;
      if (accepted == true) {
        final acceptedSession = await widget.api.acceptCall(
          incoming.session.id,
        );
        if (!mounted) return;
        await Navigator.push(
          context,
          _buildSmoothRoute(
            _WebRtcCallScreen(
              api: widget.api,
              language: widget.language,
              session: acceptedSession,
              isCaller: false,
              peerName:
                  acceptedSession.peer?.displayName ??
                  incoming.session.peer?.displayName ??
                  s.unknownContact,
            ),
          ),
        );
      } else {
        await widget.api.rejectCall(incoming.session.id);
      }
      unawaited(_load(quiet: true));
    } catch (_) {
      _incomingCallDialogOpen = false;
    }
  }

  void _showProfileHint(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _profileErrorText(Object error, AppStrings s) {
    final raw = error.toString();
    const prefix = 'ChatApiException: ';
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length);
    }
    return s.profileUpdateFailed;
  }

  Future<void> _openProfileSettings(AppStrings s) async {
    var me = _currentUser;
    if (me == null) {
      await _loadCurrentUser(quiet: true);
      me = _currentUser;
      if (me == null) {
        _showProfileHint(s.profileUpdateFailed);
        return;
      }
    }
    final usernameCtrl = TextEditingController(text: me.username);
    final displayNameCtrl = TextEditingController(text: me.displayName);
    final passwordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();

    String? localError;
    var localSaving = false;

    try {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppBlue.surfaceElevated,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> submit() async {
                final username = usernameCtrl.text.trim().toLowerCase();
                final displayName = displayNameCtrl.text.trim();
                final password = passwordCtrl.text;
                final confirmPassword = confirmPasswordCtrl.text;

                if (username.isEmpty) {
                  setModalState(() => localError = s.usernamePasswordRequired);
                  return;
                }
                if (displayName.isEmpty) {
                  setModalState(() => localError = s.displayNameRequired);
                  return;
                }
                if (password.isNotEmpty && password.length < 6) {
                  setModalState(() => localError = s.passwordTooShort);
                  return;
                }
                if (password.isNotEmpty && password != confirmPassword) {
                  setModalState(() => localError = s.passwordsDoNotMatch);
                  return;
                }

                setModalState(() {
                  localError = null;
                  localSaving = true;
                });
                if (mounted) {
                  setState(() => _profileSaving = true);
                }
                try {
                  final updated = await widget.api.updateProfile(
                    username: username == me!.username ? null : username,
                    displayName: displayName == me.displayName
                        ? null
                        : displayName,
                    password: password.isEmpty ? null : password,
                  );
                  if (!mounted) return;
                  setState(() {
                    _currentUser = updated;
                    _profileSaving = false;
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                  _showProfileHint(s.profileUpdated);
                } catch (error) {
                  if (!mounted) return;
                  setState(() => _profileSaving = false);
                  setModalState(() {
                    localSaving = false;
                    localError = _profileErrorText(error, s);
                  });
                }
              }

              final bottomInset = MediaQuery.of(context).viewInsets.bottom;
              return Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, bottomInset + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.profileSettings,
                      style: const TextStyle(
                        color: AppBlue.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: displayNameCtrl,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: AppBlue.text),
                      decoration: InputDecoration(labelText: s.displayName),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: usernameCtrl,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: AppBlue.text),
                      decoration: InputDecoration(labelText: s.username),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: AppBlue.text),
                      decoration: InputDecoration(labelText: s.newPassword),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmPasswordCtrl,
                      obscureText: true,
                      onSubmitted: (_) => submit(),
                      style: const TextStyle(color: AppBlue.text),
                      decoration: InputDecoration(labelText: s.confirmPassword),
                    ),
                    if (localError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        localError!,
                        style: const TextStyle(color: AppBlue.dangerSoft),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: localSaving
                                ? null
                                : () => Navigator.pop(context),
                            child: Text(s.cancel),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: localSaving ? null : submit,
                            child: localSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(s.saveChanges),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      usernameCtrl.dispose();
      displayNameCtrl.dispose();
      passwordCtrl.dispose();
      confirmPasswordCtrl.dispose();
      if (mounted && _profileSaving) {
        setState(() => _profileSaving = false);
      }
    }
  }

  Future<void> _selectLanguage(AppStrings s) async {
    final selected = await showModalBottomSheet<AppLanguage>(
      context: context,
      backgroundColor: AppBlue.surfaceElevated,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                s.selectLanguage,
                style: const TextStyle(
                  color: AppBlue.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              leading: const _LangBadge(label: 'RU'),
              title: Text(
                AppLanguage.ru.nativeName,
                style: const TextStyle(color: AppBlue.text),
              ),
              trailing: widget.language == AppLanguage.ru
                  ? const Icon(Icons.check_rounded, color: AppBlue.accentSoft)
                  : null,
              onTap: () => Navigator.pop(context, AppLanguage.ru),
            ),
            ListTile(
              leading: const _LangBadge(label: 'EN'),
              title: Text(
                AppLanguage.en.nativeName,
                style: const TextStyle(color: AppBlue.text),
              ),
              trailing: widget.language == AppLanguage.en
                  ? const Icon(Icons.check_rounded, color: AppBlue.accentSoft)
                  : null,
              onTap: () => Navigator.pop(context, AppLanguage.en),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || selected == widget.language) {
      return;
    }
    widget.onLanguageChanged(selected);
    if (!mounted) return;
    _showProfileHint(AppStrings(selected).languageApplied);
  }

  Future<void> _loadCurrentUser({bool quiet = false}) async {
    if (!quiet) {
      setState(() => _profileLoading = true);
    }
    try {
      final me = await widget.api.fetchCurrentUser();
      if (!mounted) return;
      setState(() {
        _currentUser = me;
        _profileLoading = false;
      });
    } catch (_) {
      if (!mounted || quiet) return;
      setState(() => _profileLoading = false);
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final items = await widget.api.fetchConversations();
      if (!mounted) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(items);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _newChat() async {
    final s = AppStrings(widget.language);
    final users = await widget.api.fetchUsers();
    final available = users
        .where((u) => u.id != widget.api.currentUserId)
        .toList();
    if (!mounted || available.isEmpty) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppBlue.surface,
      showDragHandle: true,
      builder: (context) => ListView(
        children: [
          ListTile(
            title: Text(
              s.createChat,
              style: const TextStyle(color: AppBlue.text),
            ),
          ),
          ...available.map(
            (u) => ListTile(
              leading: AvatarBubble(name: u.displayName, online: u.online),
              title: Text(
                u.displayName,
                style: const TextStyle(color: AppBlue.text),
              ),
              subtitle: Text(
                '@${u.username}',
                style: const TextStyle(color: AppBlue.textMuted),
              ),
              onTap: () => Navigator.pop(context, u.id),
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    final conv = await widget.api.createDirectConversation(
      partnerUserId: selected,
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      _buildSmoothRoute(
        ConversationScreen(
          api: widget.api,
          language: widget.language,
          conversation: conv,
          onConversationChanged: (_) => _load(),
        ),
      ),
    );
    _load(quiet: true);
  }

  List<ConversationSummary> _filteredConversations() {
    final query = _search.text.trim().toLowerCase();
    return _conversations.where((c) {
      final matchesSearch =
          c.name.toLowerCase().contains(query) ||
          c.lastMessage.toLowerCase().contains(query);
      final matchesUnread = !_unreadOnly || c.unreadCount > 0;
      return matchesSearch && matchesUnread;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(widget.language);
    final list = _filteredConversations();
    return Scaffold(
      body: BlueBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: _tabIndex == 0
                    ? _ChatsTopBar(
                        strings: s,
                        totalChats: _conversations.length,
                        unreadCount: _totalUnread,
                        onRefresh: _refreshAll,
                        onLogout: widget.onLogout,
                      )
                    : _ProfileTopBar(
                        strings: s,
                        onRefresh: _refreshAll,
                        onLogout: widget.onLogout,
                      ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Duration(
                    milliseconds: _animationsEnabled ? 320 : 1,
                  ),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0.0, 0.03),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: _tabIndex == 0
                      ? _buildChatsTab(list, s)
                      : _buildProfileTab(s),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              backgroundColor: AppBlue.accent,
              foregroundColor: Colors.white,
              onPressed: _newChat,
              icon: const Icon(Icons.edit_rounded),
              label: Text(s.newChat),
            )
          : null,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: AppBlue.surface.withValues(alpha: 0.7),
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  selectedIndex: _tabIndex,
                  indicatorColor: AppBlue.accent.withValues(alpha: 0.35),
                  onDestinationSelected: (index) {
                    setState(() => _tabIndex = index);
                  },
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      selectedIcon: const Icon(Icons.chat_bubble_rounded),
                      label: s.chats,
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.person_outline_rounded),
                      selectedIcon: const Icon(Icons.person_rounded),
                      label: s.profile,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatsTab(List<ConversationSummary> list, AppStrings s) {
    return Column(
      key: const ValueKey('chats-tab'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppBlue.text),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: s.searchChat,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ChoiceChip(
                selected: !_unreadOnly,
                label: Text(s.all),
                onSelected: (_) => setState(() => _unreadOnly = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                selected: _unreadOnly,
                label: Text(s.unread),
                onSelected: (_) => setState(() => _unreadOnly = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: _animationsEnabled ? 260 : 1),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _loading
                ? const Center(
                    key: ValueKey('chat-loading'),
                    child: CircularProgressIndicator(),
                  )
                : _error != null
                ? Center(
                    key: const ValueKey('chat-error'),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppBlue.dangerSoft),
                      textAlign: TextAlign.center,
                    ),
                  )
                : RefreshIndicator(
                    key: const ValueKey('chat-list'),
                    onRefresh: _load,
                    color: AppBlue.accentSoft,
                    backgroundColor: AppBlue.surfaceElevated,
                    child: list.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 40, 16, 96),
                            children: [_EmptyChatsState(strings: s)],
                          )
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final c = list[i];
                              return TweenAnimationBuilder<double>(
                                tween: Tween(
                                  begin: _animationsEnabled ? 0 : 1,
                                  end: 1,
                                ),
                                duration: Duration(
                                  milliseconds: _animationsEnabled
                                      ? 180 + i * 35
                                      : 1,
                                ),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, child) => Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, 12 * (1 - value)),
                                    child: child,
                                  ),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppBlue.surfaceElevated.withValues(
                                          alpha: 0.88,
                                        ),
                                        AppBlue.surface.withValues(alpha: 0.84),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: AppBlue.outline.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: AppBlue.shadow,
                                        blurRadius: 16,
                                        offset: Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () => Navigator.push(
                                        context,
                                        _buildSmoothRoute(
                                          ConversationScreen(
                                            api: widget.api,
                                            language: widget.language,
                                            conversation: c,
                                            onConversationChanged: (_) =>
                                                _load(quiet: true),
                                          ),
                                        ),
                                      ),
                                      child: ListTile(
                                        leading: AvatarBubble(
                                          name: c.name,
                                          online: c.online,
                                        ),
                                        title: Text(
                                          c.name,
                                          style: const TextStyle(
                                            color: AppBlue.text,
                                          ),
                                        ),
                                        subtitle: Text(
                                          c.lastMessage.isEmpty
                                              ? (c.online
                                                    ? '${s.onlineNow} • ${s.noMessagesYet}'
                                                    : s.noMessagesYet)
                                              : (c.online
                                                    ? '${s.onlineNow} • ${c.lastMessage}'
                                                    : c.lastMessage),
                                          style: const TextStyle(
                                            color: AppBlue.textMuted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              formatTime(c.updatedAt),
                                              style: const TextStyle(
                                                color: AppBlue.textMuted,
                                                fontSize: 11,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            if (c.unreadCount > 0)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppBlue.accent,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  '${c.unreadCount}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              )
                                            else if (c.online)
                                              const _OnlinePingMini()
                                            else
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                                color: AppBlue.accentSoft,
                                                size: 18,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTab(AppStrings s) {
    final me = _currentUser;
    final displayName = me?.displayName ?? s.unknownUser;
    final username = me?.username ?? s.unknownUsername;
    final online = me?.online ?? false;
    final statusText = online ? s.onlineNow : s.offline;

    return ListView(
      key: const ValueKey('profile-tab'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _ProfileHeroCard(
          displayName: displayName,
          username: username,
          statusText: statusText,
          online: online && _showOnlineBadge,
          userIdLabel: s.userIdLabel(widget.api.currentUserId),
          loading: _profileLoading || _profileSaving,
          animationsEnabled: _animationsEnabled,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ProfileActionButton(
                icon: Icons.edit_outlined,
                label: s.edit,
                onTap: _profileSaving ? () {} : () => _openProfileSettings(s),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProfileActionButton(
                icon: Icons.qr_code_2_rounded,
                label: s.qr,
                onTap: () => _showProfileHint(s.qrShareSoon),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProfileActionButton(
                icon: Icons.shield_outlined,
                label: s.privacy,
                onTap: () => _showProfileHint(s.privacySoon),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.forum_rounded,
                label: s.chats,
                value: '${_conversations.length}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.mark_chat_unread_rounded,
                label: s.unread,
                value: '$_totalUnread',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          color: AppBlue.surface.withValues(alpha: 0.8),
          child: ListTile(
            leading: const Icon(
              Icons.language_rounded,
              color: AppBlue.accentSoft,
            ),
            title: Text(
              s.languageLabel,
              style: const TextStyle(color: AppBlue.text),
            ),
            subtitle: Text(
              widget.language.nativeName,
              style: const TextStyle(color: AppBlue.textMuted),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppBlue.textMuted,
            ),
            onTap: () => _selectLanguage(s),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: AppBlue.surface.withValues(alpha: 0.8),
          child: Column(
            children: [
              SwitchListTile(
                value: _animationsEnabled,
                activeThumbColor: AppBlue.accentSoft,
                activeTrackColor: AppBlue.accentSoft.withValues(alpha: 0.35),
                title: Text(
                  s.smoothAnimations,
                  style: TextStyle(color: AppBlue.text),
                ),
                subtitle: Text(
                  s.smoothAnimationsSubtitle,
                  style: TextStyle(color: AppBlue.textMuted),
                ),
                onChanged: (value) {
                  setState(() => _animationsEnabled = value);
                },
              ),
              const Divider(height: 1, color: Color(0x334E84C7)),
              SwitchListTile(
                value: _showOnlineBadge,
                activeThumbColor: AppBlue.accentSoft,
                activeTrackColor: AppBlue.accentSoft.withValues(alpha: 0.35),
                title: Text(
                  s.onlineBadge,
                  style: TextStyle(color: AppBlue.text),
                ),
                subtitle: Text(
                  s.onlineBadgeSubtitle,
                  style: TextStyle(color: AppBlue.textMuted),
                ),
                onChanged: (value) {
                  setState(() => _showOnlineBadge = value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: AppBlue.surface.withValues(alpha: 0.78),
          child: ListTile(
            leading: const Icon(
              Icons.auto_awesome_rounded,
              color: AppBlue.accentSoft,
            ),
            title: Text(
              s.profileRefreshed,
              style: const TextStyle(
                color: AppBlue.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              s.profileRefreshedSubtitle,
              style: const TextStyle(color: AppBlue.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.displayName,
    required this.username,
    required this.statusText,
    required this.online,
    required this.userIdLabel,
    required this.loading,
    required this.animationsEnabled,
  });

  final String displayName;
  final String username;
  final String statusText;
  final bool online;
  final String userIdLabel;
  final bool loading;
  final bool animationsEnabled;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animationsEnabled ? 0.95 : 1, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0, 1), child: child),
      ),
      child: Card(
        color: Colors.transparent,
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppBlue.surfaceElevated.withValues(alpha: 0.94),
                AppBlue.accentDeep.withValues(alpha: 0.68),
              ],
            ),
            border: Border.all(color: AppBlue.outline.withValues(alpha: 0.95)),
            boxShadow: const [
              BoxShadow(
                color: AppBlue.shadow,
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (animationsEnabled)
                      Positioned.fill(
                        child: Transform.scale(
                          scale: 1.22,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppBlue.accentSoft.withValues(alpha: 0.18),
                            ),
                          ),
                        ),
                      ),
                    AvatarBubble(name: displayName, online: online, radius: 30),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: AppBlue.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 21,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: const TextStyle(color: AppBlue.textMuted),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: online
                                  ? AppBlue.success.withValues(alpha: 0.18)
                                  : AppBlue.accentSoft.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: online
                                    ? AppBlue.success.withValues(alpha: 0.45)
                                    : AppBlue.accentSoft.withValues(
                                        alpha: 0.24,
                                      ),
                              ),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                color: online
                                    ? AppBlue.success
                                    : AppBlue.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            userIdLabel,
                            style: const TextStyle(
                              color: AppBlue.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppBlue.surfaceElevated.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppBlue.outline.withValues(alpha: 0.85)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppBlue.accentSoft, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppBlue.text,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatsTopBar extends StatelessWidget {
  const _ChatsTopBar({
    required this.strings,
    required this.totalChats,
    required this.unreadCount,
    required this.onRefresh,
    required this.onLogout,
  });

  final AppStrings strings;
  final int totalChats;
  final int unreadCount;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppBlue.surfaceElevated.withValues(alpha: 0.9),
            AppBlue.surface.withValues(alpha: 0.82),
          ],
        ),
        border: Border.all(
          color: AppBlue.outlineStrong.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Th4der',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppBlue.text,
                  ),
                ),
                Text(
                  strings.chatsSummary(totalChats, unreadCount),
                  style: const TextStyle(color: AppBlue.textMuted),
                ),
              ],
            ),
          ),
          _HeaderActionButton(
            icon: Icons.refresh_rounded,
            onPressed: onRefresh,
          ),
          const SizedBox(width: 8),
          _HeaderActionButton(icon: Icons.logout_rounded, onPressed: onLogout),
        ],
      ),
    );
  }
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({
    required this.strings,
    required this.onRefresh,
    required this.onLogout,
  });

  final AppStrings strings;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppBlue.surfaceElevated.withValues(alpha: 0.9),
            AppBlue.surface.withValues(alpha: 0.82),
          ],
        ),
        border: Border.all(
          color: AppBlue.outlineStrong.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.profile,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppBlue.text,
                  ),
                ),
                Text(
                  strings.yourTh4derAccount,
                  style: const TextStyle(color: AppBlue.textMuted),
                ),
              ],
            ),
          ),
          _HeaderActionButton(
            icon: Icons.refresh_rounded,
            onPressed: onRefresh,
          ),
          const SizedBox(width: 8),
          _HeaderActionButton(icon: Icons.logout_rounded, onPressed: onLogout),
        ],
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: AppBlue.surfaceElevated.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppBlue.outline.withValues(alpha: 0.85)),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: AppBlue.text),
          splashRadius: 20,
        ),
      ),
    );
  }
}

class _LangBadge extends StatelessWidget {
  const _LangBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppBlue.accentSoft, AppBlue.accent],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppBlue.surfaceElevated.withValues(alpha: 0.92),
              AppBlue.accentDeep.withValues(alpha: 0.62),
            ],
          ),
          border: Border.all(color: AppBlue.outline.withValues(alpha: 0.9)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppBlue.accentSoft),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  color: AppBlue.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              Text(label, style: const TextStyle(color: AppBlue.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChatsState extends StatelessWidget {
  const _EmptyChatsState({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.chat_bubble_outline_rounded,
            size: 46,
            color: AppBlue.textMuted,
          ),
          const SizedBox(height: 10),
          Text(
            strings.noChatsYet,
            style: const TextStyle(
              color: AppBlue.text,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            strings.tapNewChatToStart,
            style: const TextStyle(color: AppBlue.textMuted),
          ),
        ],
      ),
    );
  }
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.api,
    required this.language,
    required this.conversation,
    required this.onConversationChanged,
  });

  final ChatApi api;
  final AppLanguage language;
  final ConversationSummary conversation;
  final ValueChanged<ConversationSummary> onConversationChanged;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  static final RegExp _linkRegExp = RegExp(
    r'(https?:\/\/[^\s]+)',
    caseSensitive: false,
  );
  static const int _maxAttachmentBytes = 15 * 1024 * 1024;
  final Map<String, ({String source, Uint8List? bytes})> _decodedMessageImages =
      <String, ({String source, Uint8List? bytes})>{};
  List<ChatMessage> _messages = [];
  Timer? _pollTimer;
  bool _loading = true;
  bool _sending = false;
  bool _sendingCall = false;
  bool _deletingMessage = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(widget.api.markRead(widget.conversation.id));
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _load(quiet: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _decodedMessageImages.clear();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final remote = await widget.api.fetchMessages(widget.conversation.id);
      if (!mounted) return;
      final pending = _messages.where((m) => m.pending).toList();
      final merged = [
        ...remote,
        ...pending.where((p) => remote.every((r) => r.id != p.id)),
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final changed = !_areMessagesEquivalent(_messages, merged);
      if (changed || _loading || _error != null) {
        _syncImageCacheWithMessages(merged);
        setState(() {
          if (changed) {
            _messages = merged;
          }
          _loading = false;
          _error = null;
        });
        if (changed) {
          _scrollToBottom();
        }
      }
      unawaited(widget.api.markRead(widget.conversation.id));
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    await _sendMessage(text: text, restoreTextOnError: text);
  }

  Future<void> _pickAndSendFile() async {
    if (_sending) return;
    final s = AppStrings(widget.language);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      Uint8List? bytes = picked.bytes;
      if ((bytes == null || bytes.isEmpty) &&
          picked.path != null &&
          picked.path!.isNotEmpty) {
        final localPathFile = File(picked.path!);
        if (await localPathFile.exists()) {
          bytes = await localPathFile.readAsBytes();
        }
      }
      if (bytes == null || bytes.isEmpty) return;
      if (bytes.length > _maxAttachmentBytes) {
        _showHint('File is too large (max 15 MB)');
        return;
      }
      final fileName = (picked.name).trim().isEmpty
          ? 'file.bin'
          : picked.name.trim();
      final mimeType = _guessMimeType(fileName);
      final asBase64 = base64Encode(bytes);
      if (mimeType.startsWith('image/')) {
        await _sendMessage(
          text: '',
          imageBase64: asBase64,
          errorHint: s.sendPhotoFailed,
        );
      } else {
        await _sendMessage(
          text: '',
          fileBase64: asBase64,
          fileName: fileName,
          fileMimeType: mimeType,
          fileSize: bytes.length,
          errorHint: 'Failed to send file',
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showHint('Failed to send file');
    }
  }

  Future<void> _sendMessage({
    required String text,
    String? imageBase64,
    String? fileBase64,
    String? fileName,
    String? fileMimeType,
    int? fileSize,
    String? restoreTextOnError,
    String errorHint = 'Failed to send message',
  }) async {
    final hasImage = imageBase64 != null && imageBase64.isNotEmpty;
    final hasFile = fileBase64 != null && fileBase64.isNotEmpty;
    if (text.trim().isEmpty && !hasImage && !hasFile) {
      return;
    }
    final local = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: widget.conversation.id,
      sender: 'me',
      text: text,
      imageBase64: imageBase64,
      fileBase64: fileBase64,
      fileName: fileName,
      fileMimeType: fileMimeType,
      fileSize: fileSize,
      createdAt: DateTime.now(),
      pending: true,
    );
    setState(() {
      _sending = true;
      _messages = [..._messages, local];
    });
    _syncImageCacheWithMessages(_messages);
    _scrollToBottom();
    try {
      final result = await widget.api.sendMessage(
        conversationId: widget.conversation.id,
        text: text,
        imageBase64: imageBase64,
        fileBase64: fileBase64,
        fileName: fileName,
        fileMimeType: fileMimeType,
        fileSize: fileSize,
      );
      if (!mounted) return;
      final base = _messages.where((m) => m.id != local.id).toList();
      final ids = base.map((e) => e.id).toSet();
      base.addAll(result.messages.where((m) => !ids.contains(m.id)));
      base.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      setState(() {
        _messages = base;
        _sending = false;
      });
      _syncImageCacheWithMessages(base);
      widget.onConversationChanged(result.conversation);
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      final restored = _messages.where((m) => m.id != local.id).toList();
      setState(() {
        _sending = false;
        _messages = restored;
      });
      _syncImageCacheWithMessages(restored);
      if (restoreTextOnError != null) {
        _input.text = restoreTextOnError;
      } else {
        _showHint(errorHint);
      }
    }
  }

  bool _areMessagesEquivalent(List<ChatMessage> a, List<ChatMessage> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.pending != right.pending ||
          left.readByPeer != right.readByPeer ||
          left.sender != right.sender ||
          left.text != right.text ||
          left.imageBase64 != right.imageBase64 ||
          left.fileBase64 != right.fileBase64 ||
          left.fileName != right.fileName ||
          left.fileMimeType != right.fileMimeType ||
          left.fileSize != right.fileSize ||
          left.createdAt != right.createdAt) {
        return false;
      }
    }
    return true;
  }

  void _syncImageCacheWithMessages(List<ChatMessage> messages) {
    final ids = messages.map((item) => item.id).toSet();
    _decodedMessageImages.removeWhere((id, _) => !ids.contains(id));
  }

  Uint8List? _cachedMessageImageBytes(ChatMessage message) {
    final imageBase64 = message.imageBase64;
    if (imageBase64 == null || imageBase64.isEmpty) return null;
    final cached = _decodedMessageImages[message.id];
    if (cached != null && cached.source == imageBase64) {
      return cached.bytes;
    }
    Uint8List? bytes;
    try {
      bytes = base64Decode(imageBase64);
    } catch (_) {
      bytes = null;
    }
    _decodedMessageImages[message.id] = (source: imageBase64, bytes: bytes);
    return bytes;
  }

  Future<void> _openImagePreview(ChatMessage message) async {
    final bytes = _cachedMessageImageBytes(message);
    if (bytes == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.rar')) return 'application/vnd.rar';
    if (lower.endsWith('.7z')) return 'application/x-7z-compressed';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'application/octet-stream';
  }

  Future<void> _openFileAttachment(ChatMessage message) async {
    final encoded = message.fileBase64;
    if (encoded == null || encoded.isEmpty) return;
    try {
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty) {
        _showHint('Cannot open empty file');
        return;
      }
      final rawName = (message.fileName ?? 'attachment.bin').trim();
      final safeName = rawName
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll(RegExp(r'\s+'), ' ');
      final outFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}th4der_${message.id}_$safeName',
      );
      await outFile.writeAsBytes(bytes, flush: true);
      final opened = await launchUrl(
        Uri.file(outFile.path),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        _showHint('Failed to open file');
      }
    } catch (_) {
      _showHint('Failed to open file');
    }
  }

  Future<void> _openUrl(String raw) async {
    final candidate = raw.trim();
    if (candidate.isEmpty) return;
    final parsed = Uri.tryParse(candidate);
    if (parsed == null || !parsed.hasScheme) return;
    try {
      final ok = await launchUrl(parsed, mode: LaunchMode.externalApplication);
      if (!ok) {
        _showHint('Failed to open link');
      }
    } catch (_) {
      _showHint('Failed to open link');
    }
  }

  Widget _buildMessageText(String text, bool isMine) {
    final baseColor = isMine ? Colors.white : AppBlue.text;
    final linkColor = isMine ? const Color(0xFFE6F2FF) : AppBlue.accentSoft;
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _linkRegExp.allMatches(text)) {
      if (match.start > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, match.start),
            style: TextStyle(color: baseColor),
          ),
        );
      }
      final linkText = match.group(0) ?? '';
      spans.add(
        TextSpan(
          text: linkText,
          style: TextStyle(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor.withValues(alpha: 0.85),
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              unawaited(_openUrl(linkText));
            },
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(start),
          style: TextStyle(color: baseColor),
        ),
      );
    }
    if (spans.isEmpty) {
      spans.add(
        TextSpan(
          text: text,
          style: TextStyle(color: baseColor),
        ),
      );
    }
    return RichText(text: TextSpan(children: spans));
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    final precision = value >= 10 || index == 0 ? 0 : 1;
    return '${value.toStringAsFixed(precision)} ${units[index]}';
  }

  Widget _buildMessageMeta(ChatMessage message, AppStrings s) {
    final textColor = message.isMine ? Colors.white70 : AppBlue.textMuted;
    final label = message.pending ? s.sending : formatTime(message.createdAt);
    if (!message.isMine || message.pending) {
      return Text(label, style: TextStyle(color: textColor, fontSize: 11));
    }
    final readIcon = message.readByPeer
        ? Icons.done_all_rounded
        : Icons.done_rounded;
    final readColor = message.readByPeer ? AppBlue.onlineDot : textColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: textColor, fontSize: 11)),
        const SizedBox(width: 4),
        Icon(readIcon, size: 14, color: readColor),
      ],
    );
  }

  Future<void> _confirmDeleteMessage(ChatMessage message) async {
    if (_deletingMessage || message.pending || !message.isMine) return;
    final s = AppStrings(widget.language);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppBlue.surfaceElevated,
        title: Text(
          s.deleteMessageTitle,
          style: const TextStyle(color: AppBlue.text),
        ),
        content: Text(
          s.deleteMessageBody,
          style: const TextStyle(color: AppBlue.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      await _deleteMessage(message);
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final before = List<ChatMessage>.from(_messages);
    final updatedList = before.where((item) => item.id != message.id).toList();
    setState(() {
      _deletingMessage = true;
      _messages = updatedList;
    });
    _syncImageCacheWithMessages(updatedList);
    try {
      final conversation = await widget.api.deleteMessage(
        conversationId: widget.conversation.id,
        messageId: message.id,
      );
      if (!mounted) return;
      widget.onConversationChanged(conversation);
      setState(() {
        _deletingMessage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deletingMessage = false;
        _messages = before;
      });
      _syncImageCacheWithMessages(before);
      _showHint(AppStrings(widget.language).deleteMessageFailed);
    }
  }

  void _showHint(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startCall() async {
    final s = AppStrings(widget.language);
    if (_sendingCall) return;
    setState(() {
      _sendingCall = true;
    });
    try {
      var session = await widget.api.startCall(
        conversationId: widget.conversation.id,
      );
      var isCaller = session.callerId == widget.api.currentUserId;
      if (!isCaller && session.isRinging) {
        try {
          session = await widget.api.acceptCall(session.id);
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _sendingCall = false;
          });
          _showHint(s.failedToJoinActiveCall);
          return;
        }
        isCaller = session.callerId == widget.api.currentUserId;
      }
      if (!isCaller && !session.isActive) {
        if (!mounted) return;
        setState(() {
          _sendingCall = false;
        });
        _showHint(s.callNotActiveYet);
        return;
      }
      if (!mounted) return;
      setState(() {
        _sendingCall = false;
      });
      await Navigator.push(
        context,
        _buildSmoothRoute(
          _WebRtcCallScreen(
            api: widget.api,
            language: widget.language,
            session: session,
            isCaller: isCaller,
            peerName: session.peer?.displayName ?? widget.conversation.name,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sendingCall = false;
      });
      _showHint(s.failedToStartCall);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(widget.language);
    return Scaffold(
      body: BlueBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppBlue.surfaceElevated.withValues(alpha: 0.8),
                    border: Border.all(
                      color: AppBlue.outline.withValues(alpha: 0.9),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppBlue.text,
                        ),
                      ),
                      AvatarBubble(
                        name: widget.conversation.name,
                        online: widget.conversation.online,
                        radius: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.conversation.name,
                              style: const TextStyle(
                                color: AppBlue.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              widget.conversation.online
                                  ? s.onlineNow
                                  : s.offline,
                              style: TextStyle(
                                color: widget.conversation.online
                                    ? AppBlue.onlineDot
                                    : AppBlue.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.conversation.online) const _OnlinePingMini(),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: s.startCall,
                        onPressed: _sendingCall ? null : _startCall,
                        icon: _sendingCall
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.1,
                                ),
                              )
                            : const Icon(
                                Icons.call_rounded,
                                color: AppBlue.accentSoft,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _loading
                      ? const Center(
                          key: ValueKey('conversation-loading'),
                          child: CircularProgressIndicator(),
                        )
                      : _error != null
                      ? Center(
                          key: const ValueKey('conversation-error'),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppBlue.dangerSoft),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          key: const ValueKey('conversation-list'),
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) {
                            final m = _messages[i];
                            return Align(
                              alignment: m.isMine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                constraints: const BoxConstraints(
                                  maxWidth: 310,
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  12,
                                  8,
                                ),
                                decoration: BoxDecoration(
                                  gradient: m.isMine
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFF2C91FF),
                                            Color(0xFF1460C9),
                                          ],
                                        )
                                      : null,
                                  color: m.isMine
                                      ? null
                                      : AppBlue.surface.withValues(alpha: 0.94),
                                  border: Border.all(
                                    color: m.isMine
                                        ? AppBlue.accentSoft.withValues(
                                            alpha: 0.3,
                                          )
                                        : AppBlue.outline.withValues(
                                            alpha: 0.85,
                                          ),
                                  ),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(
                                      m.isMine ? 16 : 6,
                                    ),
                                    bottomRight: Radius.circular(
                                      m.isMine ? 6 : 16,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppBlue.accentDeep.withValues(
                                        alpha: 0.25,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPress: m.isMine && !m.pending
                                      ? () => _confirmDeleteMessage(m)
                                      : null,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (m.hasImage)
                                        Builder(
                                          builder: (_) {
                                            final bytes =
                                                _cachedMessageImageBytes(m);
                                            if (bytes == null) {
                                              return Text(
                                                s.photoUnavailable,
                                                style: TextStyle(
                                                  color: m.isMine
                                                      ? Colors.white
                                                      : AppBlue.text,
                                                ),
                                              );
                                            }
                                            return GestureDetector(
                                              onTap: () => _openImagePreview(m),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.memory(
                                                  bytes,
                                                  width: 220,
                                                  height: 220,
                                                  fit: BoxFit.cover,
                                                  gaplessPlayback: true,
                                                  filterQuality:
                                                      FilterQuality.medium,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      if (m.hasImage &&
                                          m.text.trim().isNotEmpty)
                                        const SizedBox(height: 8),
                                      if (m.hasFile)
                                        GestureDetector(
                                          onTap: () => _openFileAttachment(m),
                                          child: Container(
                                            width: 220,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 9,
                                            ),
                                            decoration: BoxDecoration(
                                              color: m.isMine
                                                  ? Colors.white.withValues(
                                                      alpha: 0.18,
                                                    )
                                                  : AppBlue.surfaceElevated
                                                        .withValues(alpha: 0.9),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: m.isMine
                                                    ? Colors.white.withValues(
                                                        alpha: 0.36,
                                                      )
                                                    : AppBlue.outline
                                                          .withValues(
                                                            alpha: 0.9,
                                                          ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.attach_file_rounded,
                                                  color: m.isMine
                                                      ? Colors.white
                                                      : AppBlue.accentSoft,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        m.fileName ??
                                                            'attachment.bin',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: m.isMine
                                                              ? Colors.white
                                                              : AppBlue.text,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        _formatFileSize(
                                                          m.fileSize,
                                                        ),
                                                        style: TextStyle(
                                                          color: m.isMine
                                                              ? Colors.white70
                                                              : AppBlue
                                                                    .textMuted,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (m.hasFile && m.text.trim().isNotEmpty)
                                        const SizedBox(height: 8),
                                      if (m.text.trim().isNotEmpty)
                                        _buildMessageText(m.text, m.isMine),
                                      SizedBox(
                                        height:
                                            m.hasImage ||
                                                m.hasFile ||
                                                m.text.trim().isNotEmpty
                                            ? 6
                                            : 0,
                                      ),
                                      _buildMessageMeta(m, s),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: AppBlue.surfaceElevated.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppBlue.outline.withValues(alpha: 0.9),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: AppBlue.surface.withValues(
                              alpha: 0.65,
                            ),
                            foregroundColor: AppBlue.text,
                          ),
                          onPressed: _sending ? null : _pickAndSendFile,
                          icon: const Icon(Icons.add_rounded),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _input,
                            onSubmitted: (_) => _send(),
                            style: const TextStyle(color: AppBlue.text),
                            decoration: InputDecoration(
                              hintText: s.typeMessage,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: AppBlue.accent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _sending ? null : _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BlueBackground extends StatelessWidget {
  const BlueBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppBlue.bgTop, AppBlue.bgMid, AppBlue.bgBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.2, -0.7),
                    radius: 1.2,
                    colors: [
                      AppBlue.accentSoft.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            top: -120,
            right: -80,
            child: _GlowOrb(size: 260, color: Color(0x663DA7FF)),
          ),
          const Positioned(
            bottom: -120,
            left: -90,
            child: _GlowOrb(size: 240, color: Color(0x4D67D4FF)),
          ),
          const Positioned(
            top: 180,
            left: -60,
            child: _GlowOrb(size: 200, color: Color(0x33398FFF)),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 90, spreadRadius: 20),
          ],
        ),
      ),
    );
  }
}

class _OnlinePingMini extends StatelessWidget {
  const _OnlinePingMini();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: const [_TelegramOnlineDot(radius: 4.5)],
      ),
    );
  }
}

class _TelegramOnlineDot extends StatefulWidget {
  const _TelegramOnlineDot({required this.radius});

  final double radius;

  @override
  State<_TelegramOnlineDot> createState() => _TelegramOnlineDotState();
}

class _TelegramOnlineDotState extends State<_TelegramOnlineDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        final pulseScale = 1 + (0.9 * t);
        final pulseOpacity = 0.55 * (1 - t);
        final diameter = widget.radius * 2;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: pulseScale,
              child: Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppBlue.onlineDotSoft.withValues(alpha: pulseOpacity),
                ),
              ),
            ),
            Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppBlue.onlineDot,
                border: Border.all(color: AppBlue.bgTop, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: AppBlue.onlineDotSoft,
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class AvatarBubble extends StatelessWidget {
  const AvatarBubble({
    super.key,
    required this.name,
    required this.online,
    this.radius = 21,
  });

  final String name;
  final bool online;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF76BAFF), Color(0xFF2F7BEB)],
            ),
          ),
          child: Center(
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: _TelegramOnlineDot(radius: radius <= 20 ? 5 : 6),
          ),
      ],
    );
  }
}

class _WebRtcCallScreen extends StatefulWidget {
  const _WebRtcCallScreen({
    required this.api,
    required this.language,
    required this.session,
    required this.isCaller,
    required this.peerName,
  });

  final ChatApi api;
  final AppLanguage language;
  final CallSession session;
  final bool isCaller;
  final String peerName;

  @override
  State<_WebRtcCallScreen> createState() => _WebRtcCallScreenState();
}

class _QueuedCallSignal {
  _QueuedCallSignal({required this.kind, this.payload});

  final String kind;
  final Map<String, dynamic>? payload;
  int attempts = 0;
}

class _WebRtcCallScreenState extends State<_WebRtcCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  Timer? _signalsTimer;
  int _lastSignalId = 0;
  final Set<int> _seenSignalIds = <int>{};
  final List<RTCIceCandidate> _pendingRemoteIceCandidates = <RTCIceCandidate>[];
  bool _isPollingSignals = false;
  bool _iceRestartTried = false;
  MediaStream? _manualRemoteStream;
  Timer? _connectionWatchdogTimer;
  DateTime _connectingSince = DateTime.now();
  bool _initializing = true;
  bool _micMuted = false;
  bool _cameraEnabled = true;
  bool _ended = false;
  String _status = 'Connecting...';
  bool _remoteBound = false;
  bool _makingOffer = false;
  late final bool _polite;
  Timer? _signalRetryTimer;
  Timer? _wsReconnectTimer;
  Timer? _wsPingTimer;
  WebSocketChannel? _signalingSocket;
  StreamSubscription<dynamic>? _signalingSocketSubscription;
  bool _wsReady = false;
  int _nextSignalTxId = 1;
  final Map<String, Completer<void>> _pendingSignalAcks =
      <String, Completer<void>>{};
  final List<_QueuedCallSignal> _outgoingSignals = <_QueuedCallSignal>[];
  bool _isSendingQueuedSignals = false;
  bool _aiortcConnecting = false;
  bool _aiortcConnected = false;
  bool _aiortcNegotiated = false;
  final List<RTCIceCandidate> _pendingAiortcLocalCandidates =
      <RTCIceCandidate>[];
  final Set<String> _sentAiortcCandidateKeys = <String>{};
  Completer<void>? _iceGatheringCompleter;
  late CallSession _session;

  @override
  void initState() {
    super.initState();
    _polite = !widget.isCaller;
    _session = widget.session;
    unawaited(_initializeCall());
  }

  @override
  void dispose() {
    _signalsTimer?.cancel();
    _connectionWatchdogTimer?.cancel();
    _signalRetryTimer?.cancel();
    _wsReconnectTimer?.cancel();
    _wsPingTimer?.cancel();
    unawaited(_closeSignalWebSocket());
    if (!_ended) {
      _ended = true;
      unawaited(_bestEffortEndCall());
    }
    unawaited(_disposeCallResources());
    super.dispose();
  }

  Future<void> _bestEffortEndCall() async {
    try {
      await widget.api.endCall(_session.id);
    } catch (_) {}
  }

  Future<void> _closeSignalWebSocket() async {
    _wsReady = false;
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = null;
    _wsPingTimer?.cancel();
    _wsPingTimer = null;
    final pending = List<Completer<void>>.from(_pendingSignalAcks.values);
    _pendingSignalAcks.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('WebSocket closed'));
      }
    }
    await _signalingSocketSubscription?.cancel();
    _signalingSocketSubscription = null;
    try {
      await _signalingSocket?.sink.close();
    } catch (_) {}
    _signalingSocket = null;
  }

  void _scheduleSignalWebSocketReconnect() {
    if (_ended) return;
    _wsReady = false;
    _wsPingTimer?.cancel();
    if (mounted && _status != 'Connected') {
      setState(() {
        _status = 'Signal reconnecting...';
      });
    }
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_connectSignalWebSocket());
    });
  }

  Future<void> _handleSignalWebSocketMessage(dynamic raw) async {
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    if (data == null) return;

    final event = (data['event'] as String? ?? '').toLowerCase();
    if (event == 'ready') {
      _wsReady = true;
      if (mounted &&
          (_status == 'Signal reconnecting...' || _status == 'Signal error')) {
        setState(() {
          _status = _remoteBound ? 'Connected' : 'Connecting...';
        });
      }
      return;
    }
    if (event == 'ack') {
      final txId = (data['tx_id'] as String? ?? '').trim();
      if (txId.isEmpty) return;
      final completer = _pendingSignalAcks.remove(txId);
      completer?.complete();
      return;
    }
    if (event == 'error') {
      final txId = (data['tx_id'] as String? ?? '').trim();
      final errorCode = (data['error'] as String? ?? 'signal_error').trim();
      if (txId.isNotEmpty) {
        final completer = _pendingSignalAcks.remove(txId);
        completer?.completeError(ChatApiException(errorCode));
      }
      if (mounted && _status != 'Connected') {
        setState(() {
          _status = 'Signal reconnecting...';
        });
      }
      return;
    }
    if (event != 'signal') return;

    final rawSignal = data['signal'];
    if (rawSignal is! Map) return;
    final signal = CallSignalEvent.fromJson(
      Map<String, dynamic>.from(rawSignal),
    );
    if (signal.callId != _session.id) return;
    if (_seenSignalIds.contains(signal.id)) return;
    _seenSignalIds.add(signal.id);
    if (signal.id > _lastSignalId) {
      _lastSignalId = signal.id;
    }
    await _handleSignal(signal);
  }

  void _startSignalWebSocketPing() {
    _wsPingTimer?.cancel();
    _wsPingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final socket = _signalingSocket;
      if (_ended || !_wsReady || socket == null) return;
      try {
        socket.sink.add(jsonEncode({'action': 'ping'}));
      } catch (_) {
        _scheduleSignalWebSocketReconnect();
      }
    });
  }

  Future<void> _sendSignalViaWebSocket({
    required String callId,
    required String kind,
    Map<String, dynamic>? payload,
  }) async {
    final socket = _signalingSocket;
    if (!_wsReady || socket == null) {
      throw StateError('WebSocket not connected');
    }
    final txId =
        '${DateTime.now().microsecondsSinceEpoch}-${_nextSignalTxId++}-$kind';
    final completer = Completer<void>();
    _pendingSignalAcks[txId] = completer;
    try {
      socket.sink.add(
        jsonEncode({
          'action': 'signal',
          'call_id': callId,
          'kind': kind,
          ...?(payload == null ? null : <String, dynamic>{'payload': payload}),
          'tx_id': txId,
        }),
      );
      await completer.future.timeout(const Duration(seconds: 5));
    } finally {
      _pendingSignalAcks.remove(txId);
    }
  }

  Future<void> _connectSignalWebSocket() async {
    if (_ended) return;
    await _closeSignalWebSocket();
    try {
      final uri = _callWebSocketUri(widget.api);
      final socket = WebSocketChannel.connect(uri);
      _signalingSocket = socket;
      _signalingSocketSubscription = socket.stream.listen(
        (message) {
          unawaited(_handleSignalWebSocketMessage(message));
        },
        onDone: () {
          _wsReady = false;
          _wsPingTimer?.cancel();
          _scheduleSignalWebSocketReconnect();
        },
        onError: (_) {
          _wsReady = false;
          _wsPingTimer?.cancel();
          _scheduleSignalWebSocketReconnect();
        },
        cancelOnError: true,
      );
      _startSignalWebSocketPing();
    } catch (_) {
      _wsReady = false;
      _scheduleSignalWebSocketReconnect();
    }
  }

  Future<void> _initializeCall() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      await _initPeerConnection();
      await _connectSignalWebSocket();
      if (!widget.isCaller && _session.isRinging) {
        try {
          _session = await widget.api.acceptCall(_session.id);
        } catch (_) {}
      }
      _signalsTimer = Timer.periodic(
        const Duration(milliseconds: 1400),
        (_) => unawaited(_pollSignals()),
      );
      _connectionWatchdogTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_runConnectionWatchdog()),
      );
      if (widget.isCaller) {
        if (_webrtcUseAiortc) {
          await _connectToAiortcBridge();
        } else {
          await _createAndSendOffer();
        }
      } else {
        _status = _session.isActive ? 'Connecting...' : 'Waiting for caller...';
        if (_webrtcUseAiortc && _session.isActive) {
          await _connectToAiortcBridge();
        }
      }
      if (!mounted) return;
      setState(() {
        _initializing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = 'Failed to initialize call';
      });
    }
  }

  Future<void> _initPeerConnection() async {
    final stunUrls = _webrtcStunUrls
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final iceServers = <Map<String, dynamic>>[
      for (final url in stunUrls) {'urls': url},
    ];
    if (_webrtcTurnUrl.isNotEmpty) {
      iceServers.add({
        'urls': _webrtcTurnUrl,
        'username': _webrtcTurnUsername,
        'credential': _webrtcTurnCredential,
      });
    }
    final configuration = <String, dynamic>{
      'iceServers': iceServers,
      if (_webrtcForceRelay && _webrtcTurnUrl.isNotEmpty)
        'iceTransportPolicy': 'relay',
    };
    final constraints = <String, dynamic>{
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };
    _peerConnection = await createPeerConnection(configuration, constraints);

    _peerConnection?.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      if (_webrtcUseAiortc) {
        if (_aiortcConnected && !_aiortcConnecting) {
          unawaited(_sendAiortcCandidate(candidate));
        } else {
          _queueAiortcLocalCandidate(candidate);
        }
        return;
      }
      unawaited(
        _enqueueSignal(
          callId: _session.id,
          kind: 'ice',
          payload: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ),
      );
    };

    _peerConnection?.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateGathering) {
        _iceGatheringCompleter ??= Completer<void>();
        return;
      }
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        final completer = _iceGatheringCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      }
    };

    _peerConnection?.onTrack = (event) {
      unawaited(_handleRemoteTrack(event));
    };

    _peerConnection?.onAddStream = (stream) {
      _bindRemoteStream(stream);
    };

    _peerConnection?.onConnectionState = (state) {
      if (!mounted) return;
      setState(() {
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _aiortcConnected = true;
            _status = 'Connected';
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _aiortcConnected = false;
            _status = 'Connection failed';
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            _aiortcConnected = false;
            _status = 'Disconnected';
            break;
          default:
            break;
        }
      });
    };

    _peerConnection?.onIceConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
        _markConnecting();
        setState(() => _status = 'Connecting...');
      } else if (state ==
              RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _iceRestartTried = false;
        setState(() => _status = 'Connected');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        setState(() => _status = 'ICE failed');
        if (!_webrtcUseAiortc) {
          unawaited(_tryIceRestart());
        }
      }
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': true,
      });
    } catch (_) {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    }
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}
    _localRenderer.srcObject = _localStream;
    for (final track in _localStream!.getTracks()) {
      await _peerConnection?.addTrack(track, _localStream!);
    }
  }

  Future<void> _createAndSendOffer() async {
    _markConnecting();
    _makingOffer = true;
    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1,
      });
      await _peerConnection!.setLocalDescription(offer);
      await _enqueueSignal(
        callId: _session.id,
        kind: 'offer',
        payload: {'sdp': offer.sdp, 'type': offer.type},
      );
    } finally {
      _makingOffer = false;
    }
    if (mounted) {
      setState(() {
        _status = _session.isActive ? 'Connecting...' : 'Ringing...';
      });
    }
  }

  Future<void> _createAndSendAnswer() async {
    _markConnecting();
    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });
    await _peerConnection!.setLocalDescription(answer);
    await _enqueueSignal(
      callId: _session.id,
      kind: 'answer',
      payload: {'sdp': answer.sdp, 'type': answer.type},
    );
    if (mounted) {
      setState(() {
        _status = 'Connecting...';
      });
    }
  }

  Future<void> _connectToAiortcBridge({bool force = false}) async {
    final peer = _peerConnection;
    if (peer == null || _ended) return;
    if (_aiortcConnecting) return;
    if (_aiortcNegotiated && !force) return;

    _aiortcConnecting = true;
    if (force) {
      _aiortcNegotiated = false;
      _aiortcConnected = false;
    }
    _pendingAiortcLocalCandidates.clear();
    _sentAiortcCandidateKeys.clear();
    _markConnecting();
    if (mounted) {
      setState(() {
        _status = 'Connecting...';
      });
    }
    try {
      final offer = await peer.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1,
        if (force) 'iceRestart': true,
      });
      await peer.setLocalDescription(offer);
      await _waitForIceGatheringComplete();
      final localDescription = await _safeGetLocalDescription(peer);
      final localSdp = localDescription?.sdp ?? offer.sdp;
      if (localSdp == null || localSdp.isEmpty) {
        throw ChatApiException('Local SDP is empty');
      }
      final answer = await widget.api.connectCallRtc(
        callId: _session.id,
        sdp: localSdp,
        type: localDescription?.type ?? offer.type ?? 'offer',
      );
      await peer.setRemoteDescription(
        RTCSessionDescription(answer.sdp, answer.type),
      );
      _aiortcNegotiated = true;
      _aiortcConnected = true;
      await _sendAiortcCandidatesFromSdp(localSdp);
      await _flushPendingAiortcCandidates();
      await _flushPendingIceCandidates();
      _iceRestartTried = false;
    } catch (_) {
      if (mounted && _status != 'Connected') {
        setState(() {
          _status = 'Signal error';
        });
      }
      rethrow;
    } finally {
      _aiortcConnecting = false;
    }
  }

  Future<void> _pollSignals() async {
    if (_ended || _isPollingSignals) return;
    _isPollingSignals = true;
    try {
      final batch = await widget.api.fetchCallSignals(
        callId: _session.id,
        sinceSignalId: _lastSignalId,
      );
      _session = batch.session;

      if (!widget.isCaller && _session.isRinging) {
        try {
          _session = await widget.api.acceptCall(_session.id);
          if (mounted && _session.isActive) {
            setState(() {
              _status = 'Connecting...';
            });
          }
          if (_webrtcUseAiortc && _session.isActive && !_aiortcNegotiated) {
            await _connectToAiortcBridge();
          }
        } catch (_) {}
      }

      if (_session.isEnded) {
        await _finishCall(pop: true);
        return;
      }

      if (_webrtcUseAiortc && _session.isActive && !_aiortcNegotiated) {
        try {
          await _connectToAiortcBridge();
        } catch (_) {}
      }

      for (final signal in batch.signals) {
        if (_seenSignalIds.contains(signal.id)) {
          if (signal.id > _lastSignalId) {
            _lastSignalId = signal.id;
          }
          continue;
        }
        var handled = true;
        try {
          await _handleSignal(signal);
          _seenSignalIds.add(signal.id);
        } catch (_) {
          handled = false;
          if (mounted && _status != 'Connected') {
            setState(() {
              _status = 'Negotiation retry...';
            });
          }
        }
        // Do not advance past failed SDP signals - retry them on next poll.
        if (!handled && (signal.kind == 'offer' || signal.kind == 'answer')) {
          break;
        }
        if (signal.id > _lastSignalId) {
          _lastSignalId = signal.id;
        }
      }
      if (batch.signals.isEmpty && batch.lastSignalId > _lastSignalId) {
        _lastSignalId = batch.lastSignalId;
      }
      await _drainOutgoingSignals(callId: _session.id);
    } catch (_) {
      _scheduleSignalRetry(callId: _session.id, attempts: 1);
    } finally {
      _isPollingSignals = false;
    }
  }

  void _bindRemoteStream(MediaStream stream) {
    if (_remoteBound && _remoteRenderer.srcObject?.id == stream.id) {
      return;
    }
    _remoteRenderer.srcObject = stream;
    _remoteBound = true;
    if (mounted) {
      setState(() {
        _status = 'Connected';
      });
    }
  }

  Future<void> _enqueueSignal({
    required String callId,
    required String kind,
    Map<String, dynamic>? payload,
  }) async {
    if (_ended) return;
    _outgoingSignals.add(
      _QueuedCallSignal(
        kind: kind,
        payload: payload == null ? null : Map<String, dynamic>.from(payload),
      ),
    );
    await _drainOutgoingSignals(callId: callId);
  }

  void _scheduleSignalRetry({required String callId, int attempts = 1}) {
    if (_ended) return;
    _signalRetryTimer?.cancel();
    final delay = Duration(milliseconds: 300 * attempts.clamp(1, 6));
    _signalRetryTimer = Timer(delay, () {
      unawaited(_drainOutgoingSignals(callId: callId));
    });
  }

  bool _isCallClosedSignalError(Object error) {
    final text = error.toString().toLowerCase();
    return (text.contains('api error 409') &&
            text.contains('call is no longer active')) ||
        text.contains('call_closed');
  }

  bool _isRetryableSignalError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('api error 500') ||
        text.contains('api error 502') ||
        text.contains('api error 503') ||
        text.contains('api error 504') ||
        text.contains('temporary_signaling_storage_busy') ||
        text.contains('websocket') ||
        text.contains('socketexception') ||
        text.contains('timeout');
  }

  Future<void> _drainOutgoingSignals({required String callId}) async {
    if (_ended || _isSendingQueuedSignals) return;
    _isSendingQueuedSignals = true;
    try {
      while (_outgoingSignals.isNotEmpty && !_ended) {
        final signal = _outgoingSignals.first;
        try {
          var sent = false;
          if (_wsReady && _signalingSocket != null) {
            try {
              await _sendSignalViaWebSocket(
                callId: callId,
                kind: signal.kind,
                payload: signal.payload,
              );
              sent = true;
            } catch (_) {
              _wsReady = false;
              _scheduleSignalWebSocketReconnect();
            }
          }
          if (!sent) {
            await widget.api.sendCallSignal(
              callId: callId,
              kind: signal.kind,
              payload: signal.payload,
            );
          }
          _outgoingSignals.removeAt(0);
          if (mounted &&
              (_status == 'Signal reconnecting...' ||
                  _status == 'Signal error')) {
            setState(() {
              _status = _remoteBound ? 'Connected' : 'Connecting...';
            });
          }
        } catch (error) {
          if (_isCallClosedSignalError(error)) {
            _outgoingSignals.removeAt(0);
            continue;
          }
          if (signal.kind == 'ice') {
            // Avoid blocking SDP signaling because of noisy ICE transport errors.
            _outgoingSignals.removeAt(0);
            continue;
          }
          signal.attempts += 1;
          if (!_isRetryableSignalError(error) || signal.attempts >= 5) {
            if (mounted) {
              setState(() {
                _status = 'Signal error';
              });
            }
            _scheduleSignalRetry(callId: callId, attempts: signal.attempts);
            break;
          }
          if (mounted && _status != 'Connected') {
            setState(() {
              _status = 'Signal reconnecting...';
            });
          }
          _scheduleSignalRetry(callId: callId, attempts: signal.attempts);
          break;
        }
      }
    } finally {
      _isSendingQueuedSignals = false;
    }
  }

  Future<void> _handleSignal(CallSignalEvent signal) async {
    switch (signal.kind) {
      case 'accept':
        if (mounted) {
          setState(() {
            _status = 'Connecting...';
          });
        }
        break;
      case 'reject':
      case 'end':
        await _finishCall(pop: true);
        break;
      case 'offer':
        if (_webrtcUseAiortc) break;
        final sdp = signal.payload['sdp'] as String?;
        final type = signal.payload['type'] as String? ?? 'offer';
        if (sdp == null || sdp.isEmpty) break;
        final peer = _peerConnection;
        if (peer == null) break;
        final local = await _safeGetLocalDescription(peer);
        final offerCollision = _makingOffer || local?.type == 'offer';
        if (!_polite && offerCollision) {
          break;
        }
        final current = await _safeGetRemoteDescription(peer);
        if (current == null || current.sdp != sdp) {
          if (offerCollision) {
            try {
              await peer.setLocalDescription(
                RTCSessionDescription('', 'rollback'),
              );
            } catch (_) {}
          }
          _markConnecting();
          await peer.setRemoteDescription(RTCSessionDescription(sdp, type));
          await _flushPendingIceCandidates();
          await _createAndSendAnswer();
          break;
        }

        // Remote offer is the same; re-send existing local answer if we have one.
        final existingLocal = await _safeGetLocalDescription(peer);
        if (existingLocal?.type == 'answer' &&
            (existingLocal?.sdp?.isNotEmpty ?? false)) {
          await _enqueueSignal(
            callId: _session.id,
            kind: 'answer',
            payload: {'sdp': existingLocal!.sdp, 'type': existingLocal.type},
          );
        }
        break;
      case 'answer':
        if (_webrtcUseAiortc) break;
        final sdp = signal.payload['sdp'] as String?;
        final type = signal.payload['type'] as String? ?? 'answer';
        if (sdp == null || sdp.isEmpty) break;
        final peer = _peerConnection;
        if (peer == null) break;
        final local = await _safeGetLocalDescription(peer);
        if (local?.type != 'offer') break;
        final current = await _safeGetRemoteDescription(peer);
        if (current == null || current.sdp != sdp) {
          _markConnecting();
          await peer.setRemoteDescription(RTCSessionDescription(sdp, type));
          await _flushPendingIceCandidates();
        }
        break;
      case 'ice':
        if (_webrtcUseAiortc) break;
        final candidate = signal.payload['candidate'] as String?;
        if (candidate == null || candidate.isEmpty) break;
        final sdpMid = signal.payload['sdpMid'] as String?;
        final sdpMLineIndex = (signal.payload['sdpMLineIndex'] as num?)
            ?.toInt();
        await _handleIncomingIceCandidate(
          RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
        );
        break;
    }
  }

  Future<void> _handleIncomingIceCandidate(RTCIceCandidate candidate) async {
    final peer = _peerConnection;
    if (peer == null) return;

    final remoteDescription = await _safeGetRemoteDescription(peer);
    if (remoteDescription == null) {
      _pendingRemoteIceCandidates.add(candidate);
      return;
    }

    try {
      await peer.addCandidate(candidate);
    } catch (_) {
      _pendingRemoteIceCandidates.add(candidate);
    }
  }

  Future<RTCSessionDescription?> _safeGetRemoteDescription(
    RTCPeerConnection peer,
  ) async {
    try {
      return await peer.getRemoteDescription();
    } catch (_) {
      return null;
    }
  }

  Future<RTCSessionDescription?> _safeGetLocalDescription(
    RTCPeerConnection peer,
  ) async {
    try {
      return await peer.getLocalDescription();
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleRemoteTrack(RTCTrackEvent event) async {
    if (event.streams.isNotEmpty) {
      _bindRemoteStream(event.streams.first);
      return;
    }

    if (event.track.kind != 'audio' && event.track.kind != 'video') return;
    final remote =
        _manualRemoteStream ??
        await createLocalMediaStream('remote-${_session.id}');
    _manualRemoteStream = remote;
    final alreadyPresent = remote.getTracks().any(
      (track) => track.id == event.track.id,
    );
    if (!alreadyPresent) {
      remote.addTrack(event.track);
    }
    _bindRemoteStream(remote);
  }

  Future<void> _tryIceRestart() async {
    if (_ended || _iceRestartTried || _makingOffer) return;
    final peer = _peerConnection;
    if (peer == null) return;

    _iceRestartTried = true;
    _markConnecting();
    if (mounted) {
      setState(() {
        _status = 'Reconnecting...';
      });
    }
    if (_webrtcUseAiortc) {
      try {
        await _connectToAiortcBridge(force: true);
      } catch (_) {}
      return;
    }
    _makingOffer = true;
    try {
      final offer = await peer.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1,
        'iceRestart': true,
      });
      await peer.setLocalDescription(offer);
      await _enqueueSignal(
        callId: _session.id,
        kind: 'offer',
        payload: {'sdp': offer.sdp, 'type': offer.type},
      );
    } catch (_) {
    } finally {
      _makingOffer = false;
    }
  }

  void _markConnecting() {
    _connectingSince = DateTime.now();
  }

  Future<void> _runConnectionWatchdog() async {
    if (_ended || _remoteBound) return;
    final elapsed = DateTime.now().difference(_connectingSince);
    if (elapsed > const Duration(seconds: 18) && !_iceRestartTried) {
      if (_webrtcUseAiortc) {
        if (mounted && _status != 'Connected') {
          setState(() {
            _status = 'Waiting for media...';
          });
        }
        return;
      }
      await _tryIceRestart();
      return;
    }
    if (elapsed > const Duration(seconds: 40) && mounted) {
      setState(() {
        _status = 'Connection timeout';
      });
    }
  }

  void _queueAiortcLocalCandidate(RTCIceCandidate candidate) {
    final value = candidate.candidate;
    if (value == null || value.isEmpty) return;
    final key = _aiortcCandidateKey(
      value,
      candidate.sdpMid,
      candidate.sdpMLineIndex,
    );
    if (_sentAiortcCandidateKeys.contains(key)) return;
    final duplicate = _pendingAiortcLocalCandidates.any(
      (item) =>
          _aiortcCandidateKey(
            item.candidate,
            item.sdpMid,
            item.sdpMLineIndex,
          ) ==
          key,
    );
    if (!duplicate) {
      _pendingAiortcLocalCandidates.add(candidate);
    }
  }

  Future<void> _sendAiortcCandidate(RTCIceCandidate candidate) async {
    final value = candidate.candidate;
    if (value == null || value.isEmpty) return;
    try {
      await widget.api.sendCallRtcCandidate(
        callId: _session.id,
        candidate: value,
        sdpMid: candidate.sdpMid,
        sdpMLineIndex: candidate.sdpMLineIndex,
      );
      _sentAiortcCandidateKeys.add(
        _aiortcCandidateKey(value, candidate.sdpMid, candidate.sdpMLineIndex),
      );
    } catch (_) {
      _queueAiortcLocalCandidate(candidate);
    }
  }

  Future<void> _flushPendingAiortcCandidates() async {
    if (_pendingAiortcLocalCandidates.isEmpty || !_aiortcConnected) {
      return;
    }

    final pending = List<RTCIceCandidate>.from(_pendingAiortcLocalCandidates);
    _pendingAiortcLocalCandidates.clear();
    for (final candidate in pending) {
      await _sendAiortcCandidate(candidate);
    }
  }

  String _aiortcCandidateKey(
    String? candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) {
    return '${candidate ?? ''}|${sdpMid ?? ''}|${sdpMLineIndex ?? -1}';
  }

  Future<void> _sendAiortcCandidatesFromSdp(String sdp) async {
    if (!_aiortcConnected || sdp.isEmpty) return;

    final lines = sdp.split(RegExp(r'\r\n|\n'));
    var currentMid = '';
    var currentMLineIndex = -1;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('m=')) {
        currentMLineIndex += 1;
        currentMid = '';
        continue;
      }
      if (line.startsWith('a=mid:')) {
        currentMid = line.substring(6).trim();
        continue;
      }
      if (!line.startsWith('a=candidate:')) {
        continue;
      }
      final candidate = line.substring(2); // drop "a="
      final candidateObj = RTCIceCandidate(
        candidate,
        currentMid.isEmpty ? null : currentMid,
        currentMLineIndex >= 0 ? currentMLineIndex : null,
      );
      await _sendAiortcCandidate(candidateObj);
    }
  }

  Future<void> _waitForIceGatheringComplete() async {
    final completer = _iceGatheringCompleter ??= Completer<void>();
    try {
      await completer.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Continue with whatever candidates we already have.
    } finally {
      _iceGatheringCompleter = null;
    }
  }

  Future<void> _flushPendingIceCandidates() async {
    final peer = _peerConnection;
    if (peer == null || _pendingRemoteIceCandidates.isEmpty) return;

    final toApply = List<RTCIceCandidate>.from(_pendingRemoteIceCandidates);
    _pendingRemoteIceCandidates.clear();
    for (final candidate in toApply) {
      try {
        await peer.addCandidate(candidate);
      } catch (_) {}
    }
  }

  Future<void> _toggleMic() async {
    _micMuted = !_micMuted;
    for (final track
        in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !_micMuted;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    _cameraEnabled = !_cameraEnabled;
    for (final track
        in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = _cameraEnabled;
    }
    if (mounted) setState(() {});
  }

  Future<void> _finishCall({required bool pop}) async {
    if (_ended) return;
    _ended = true;
    _signalsTimer?.cancel();
    _connectionWatchdogTimer?.cancel();
    _signalRetryTimer?.cancel();
    _outgoingSignals.clear();
    if (_webrtcUseAiortc) {
      try {
        await widget.api.disconnectCallRtc(_session.id);
      } catch (_) {}
    }
    _aiortcNegotiated = false;
    _aiortcConnected = false;
    await _disposeCallResources();
    if (!mounted) return;
    if (pop) {
      Navigator.pop(context);
    } else {
      setState(() {});
    }
  }

  Future<void> _hangUp() async {
    try {
      await widget.api.endCall(_session.id);
    } catch (_) {}
    await _finishCall(pop: true);
  }

  Future<void> _disposeCallResources() async {
    final local = _localStream;
    _localStream = null;
    if (local != null) {
      for (final track in local.getTracks()) {
        track.stop();
      }
      await local.dispose();
    }
    await _peerConnection?.close();
    _peerConnection = null;
    if (_manualRemoteStream != null) {
      await _manualRemoteStream?.dispose();
      _manualRemoteStream = null;
    }
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(widget.language);
    final remoteReady = _remoteRenderer.srcObject != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _hangUp();
      },
      child: Scaffold(
        body: BlueBackground(
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: remoteReady
                        ? RTCVideoView(
                            key: const ValueKey('remote-video'),
                            _remoteRenderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          )
                        : Center(
                            key: const ValueKey('remote-placeholder'),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_rounded,
                                  size: 82,
                                  color: AppBlue.textMuted,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.peerName,
                                  style: const TextStyle(
                                    color: AppBlue.text,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _initializing
                                      ? s.callInitializing
                                      : s.callStatusText(_status),
                                  style: const TextStyle(
                                    color: AppBlue.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: AppBlue.surfaceElevated.withValues(
                            alpha: 0.8,
                          ),
                        ),
                        onPressed: _hangUp,
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.peerName,
                              style: const TextStyle(
                                color: AppBlue.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              s.callStatusText(_status),
                              style: const TextStyle(color: AppBlue.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_localRenderer.srcObject != null)
                  Positioned(
                    top: 90,
                    right: 14,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 112,
                        height: 166,
                        child: RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 26,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CallActionButton(
                        icon: _micMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        onTap: _toggleMic,
                      ),
                      const SizedBox(width: 18),
                      _CallActionButton(
                        icon: _cameraEnabled
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        onTap: _toggleCamera,
                      ),
                      const SizedBox(width: 18),
                      _CallActionButton(
                        icon: Icons.call_end_rounded,
                        color: const Color(0xFFE85063),
                        onTap: _hangUp,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.onTap,
    this.color = AppBlue.surfaceElevated,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

String formatTime(DateTime timestamp) {
  final h = timestamp.hour.toString().padLeft(2, '0');
  final m = timestamp.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
