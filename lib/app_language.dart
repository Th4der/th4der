enum AppLanguage {
  ru,
  en;

  String get code => this == AppLanguage.ru ? 'ru' : 'en';

  String get nativeName => this == AppLanguage.ru ? 'Русский' : 'English';

  static AppLanguage fromCode(String code) {
    final normalized = code.toLowerCase();
    if (normalized.startsWith('ru')) {
      return AppLanguage.ru;
    }
    return AppLanguage.en;
  }
}

class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  bool get isRu => language == AppLanguage.ru;

  String get appTitle => 'Th4der';
  String get createAccount => isRu ? 'Создать аккаунт' : 'Create account';
  String get secureSignIn => isRu ? 'Безопасный вход' : 'Secure Sign In';
  String get username => isRu ? 'Имя пользователя' : 'Username';
  String get displayName => isRu ? 'Отображаемое имя' : 'Display name';
  String get password => isRu ? 'Пароль' : 'Password';
  String get register => isRu ? 'Регистрация' : 'Register';
  String get login => isRu ? 'Войти' : 'Login';
  String get haveAccountLogin =>
      isRu ? 'Уже есть аккаунт? Войти' : 'Have account? Login';
  String get needAccountRegister =>
      isRu ? 'Нет аккаунта? Регистрация' : 'Need account? Register';
  String get usernamePasswordRequired => isRu
      ? 'Логин и пароль обязательны.'
      : 'Username and password are required.';
  String get displayNameRequired =>
      isRu ? 'Введите отображаемое имя.' : 'Display name is required.';

  String get chats => isRu ? 'Чаты' : 'Chats';
  String get profile => isRu ? 'Профиль' : 'Profile';
  String get searchChat => isRu ? 'Поиск по чатам' : 'Search chat';
  String get all => isRu ? 'Все' : 'All';
  String get unread => isRu ? 'Непрочитанные' : 'Unread';
  String get noMessagesYet => isRu ? 'Пока нет сообщений' : 'No messages yet';
  String get newChat => isRu ? 'Новый чат' : 'New chat';
  String get createChat => isRu ? 'Создать чат' : 'Create chat';
  String get noChatsYet => isRu ? 'Пока нет чатов' : 'No chats yet';
  String get tapNewChatToStart =>
      isRu ? 'Нажмите "Новый чат", чтобы начать' : 'Tap New chat to start';
  String chatsSummary(int totalChats, int unreadCount) => isRu
      ? '$totalChats чатов | $unreadCount непрочитанных'
      : '$totalChats chats | $unreadCount unread';

  String get yourTh4derAccount =>
      isRu ? 'Ваш аккаунт Th4der' : 'Your Th4der account';
  String get onlineNow => isRu ? 'В сети' : 'Online now';
  String get offline => isRu ? 'Не в сети' : 'Offline';
  String userIdLabel(int id) => 'ID $id';
  String get edit => isRu ? 'Изменить' : 'Edit';
  String get qr => 'QR';
  String get privacy => isRu ? 'Приватность' : 'Privacy';
  String get profileEditorSoon =>
      isRu ? 'Редактор профиля скоро появится' : 'Profile editor coming soon';
  String get qrShareSoon =>
      isRu ? 'QR-шаринг скоро появится' : 'QR share coming soon';
  String get privacySoon => isRu
      ? 'Настройки приватности скоро появятся'
      : 'Privacy settings coming soon';
  String get smoothAnimations =>
      isRu ? 'Плавные анимации' : 'Smooth animations';
  String get smoothAnimationsSubtitle => isRu
      ? 'Включить мягкие анимации профиля и чатов'
      : 'Enable soft profile and chat animations';
  String get onlineBadge => isRu ? 'Онлайн-индикатор' : 'Online badge';
  String get onlineBadgeSubtitle => isRu
      ? 'Показывать статус рядом с аватаром'
      : 'Show status indicator near avatar';
  String get profileRefreshed =>
      isRu ? 'Профиль обновлен' : 'Profile refreshed';
  String get profileRefreshedSubtitle => isRu
      ? 'Добавлены градиенты, быстрые действия и аккуратные детали.'
      : 'Added gradients, action shortcuts and cleaner account details.';

  String get languageLabel => isRu ? 'Язык' : 'Language';
  String get selectLanguage => isRu ? 'Выберите язык' : 'Select language';
  String get languageApplied =>
      isRu ? 'Язык интерфейса изменен' : 'Language was updated';

  String get typeMessage => isRu ? 'Введите сообщение' : 'Type a message';
  String get sending => isRu ? 'Отправка...' : 'Sending...';
}
