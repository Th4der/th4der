import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_language.dart';
import 'chat_api.dart';

const String _defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.1.3:8000',
);

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
  }

  void _onAuthenticated(AuthSession session) {
    setState(() {
      _api = HttpChatApi(
        baseUrl: _defaultApiBaseUrl,
        currentUserId: session.user.id,
        authToken: session.token,
      );
      _currentUser = session.user;
    });
  }

  void _logout() {
    FocusManager.instance.primaryFocus?.unfocus();
    final api = _api;
    if (api != null) {
      unawaited(api.logout().catchError((Object _) {}));
    }
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
      home: _api == null
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
                        if (_registerMode) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _displayName,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            style: const TextStyle(color: AppBlue.text),
                            decoration: InputDecoration(
                              labelText: s.displayName,
                              prefixIcon: const Icon(Icons.badge_outlined),
                            ),
                          ),
                        ],
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
  bool _loading = true;
  bool _profileLoading = false;
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
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _load(quiet: true),
    );
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

  void _showProfileHint(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
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
      final users = await widget.api.fetchUsers();
      final me = users.where((item) => item.id == widget.api.currentUserId);
      if (!mounted) return;
      setState(() {
        if (me.isNotEmpty) {
          _currentUser = me.first;
        }
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
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
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
                child: _tabIndex == 0
                    ? _buildChatsTab(list, s)
                    : _buildProfileTab(s),
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
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppBlue.dangerSoft),
                    textAlign: TextAlign.center,
                  ),
                )
              : RefreshIndicator(
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
                                      MaterialPageRoute(
                                        builder: (_) => ConversationScreen(
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
                                                    BorderRadius.circular(999),
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
      ],
    );
  }

  Widget _buildProfileTab(AppStrings s) {
    final me = _currentUser;
    final displayName = me?.displayName ?? 'Unknown user';
    final username = me?.username ?? 'unknown';
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
          loading: _profileLoading,
          animationsEnabled: _animationsEnabled,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ProfileActionButton(
                icon: Icons.edit_outlined,
                label: s.edit,
                onTap: () => _showProfileHint(s.profileEditorSoon),
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
  List<ChatMessage> _messages = [];
  Timer? _pollTimer;
  bool _loading = true;
  bool _sending = false;
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
      setState(() {
        _messages = merged;
        _loading = false;
      });
      _scrollToBottom();
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
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    final local = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: widget.conversation.id,
      sender: 'me',
      text: text,
      createdAt: DateTime.now(),
      pending: true,
    );
    setState(() {
      _sending = true;
      _messages = [..._messages, local];
    });
    _scrollToBottom();
    try {
      final result = await widget.api.sendMessage(
        conversationId: widget.conversation.id,
        text: text,
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
      widget.onConversationChanged(result.conversation);
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _messages = _messages.where((m) => m.id != local.id).toList();
      });
      _input.text = text;
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
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppBlue.dangerSoft),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
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
                              constraints: const BoxConstraints(maxWidth: 310),
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
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
                                      : AppBlue.outline.withValues(alpha: 0.85),
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    m.text,
                                    style: TextStyle(
                                      color: m.isMine
                                          ? Colors.white
                                          : AppBlue.text,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    m.pending
                                        ? s.sending
                                        : formatTime(m.createdAt),
                                    style: TextStyle(
                                      color: m.isMine
                                          ? Colors.white70
                                          : AppBlue.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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

String formatTime(DateTime timestamp) {
  final h = timestamp.hour.toString().padLeft(2, '0');
  final m = timestamp.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
