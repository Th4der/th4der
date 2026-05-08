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
  String get languageApplied => isRu ? 'Язык обновлён' : 'Language was updated';
  String get profileSettings => isRu ? 'Настройки профиля' : 'Profile settings';
  String get saveChanges => isRu ? 'Сохранить' : 'Save changes';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get newPassword => isRu ? 'Новый пароль' : 'New password';
  String get confirmPassword => isRu ? 'Повторите пароль' : 'Confirm password';
  String get passwordTooShort => isRu
      ? 'Пароль должен быть не меньше 6 символов.'
      : 'Password must be at least 6 characters.';
  String get passwordsDoNotMatch =>
      isRu ? 'Пароли не совпадают.' : 'Passwords do not match.';
  String get profileUpdated => isRu ? 'Профиль обновлен' : 'Profile updated';
  String get profileUpdateFailed =>
      isRu ? 'Не удалось обновить профиль' : 'Failed to update profile';

  String get typeMessage => isRu ? 'Введите сообщение' : 'Type a message';
  String get sending => isRu ? 'Отправка...' : 'Sending...';
  String get startCall => isRu ? 'Начать звонок' : 'Start call';
  String get callInvite => isRu ? 'Приглашение в звонок' : 'Call invite';
  String get joinCall => isRu ? 'Присоединиться' : 'Join call';
  String get callOpenFailed =>
      isRu ? 'Не удалось открыть звонок' : 'Could not open call';
  String get callSendFailed => isRu
      ? 'Не удалось отправить приглашение в звонок'
      : 'Failed to send call invite';

  String get incomingCallTitle => isRu ? 'Входящий звонок' : 'Incoming call';
  String incomingCallFrom(String callerName) =>
      isRu ? '$callerName звонит вам' : '$callerName is calling you';
  String get decline => isRu ? 'Отклонить' : 'Decline';
  String get accept => isRu ? 'Принять' : 'Accept';

  String get unknownUser => isRu ? 'Неизвестный пользователь' : 'Unknown user';
  String get unknownUsername => isRu ? 'неизвестно' : 'unknown';
  String get unknownContact => isRu ? 'Контакт' : 'Contact';

  String get sendPhotoFailed =>
      isRu ? 'Не удалось отправить фото' : 'Failed to send photo';
  String get photoUnavailable =>
      isRu ? '[Фото недоступно]' : '[Photo unavailable]';
  String get deleteMessageTitle =>
      isRu ? 'Удалить сообщение?' : 'Delete message?';
  String get deleteMessageBody =>
      isRu ? 'Это действие нельзя отменить.' : 'This action cannot be undone.';
  String get delete => isRu ? 'Удалить' : 'Delete';
  String get deleteMessageFailed =>
      isRu ? 'Не удалось удалить сообщение' : 'Failed to delete message';
  String get failedToJoinActiveCall => isRu
      ? 'Не удалось присоединиться к активному звонку'
      : 'Failed to join active call';
  String get callNotActiveYet =>
      isRu ? 'Звонок еще не активен' : 'Call is not active yet';
  String get failedToStartCall =>
      isRu ? 'Не удалось начать звонок' : 'Failed to start call';

  String get callInitializing => isRu ? 'Инициализация...' : 'Initializing...';

  String callStatusText(String status) {
    switch (status) {
      case 'Connecting...':
        return isRu ? 'Подключение...' : 'Connecting...';
      case 'Connected':
        return isRu ? 'Подключено' : 'Connected';
      case 'Signal reconnecting...':
        return isRu ? 'Переподключение сигнала...' : 'Signal reconnecting...';
      case 'Signal error':
        return isRu ? 'Ошибка сигнала' : 'Signal error';
      case 'Waiting for caller...':
        return isRu ? 'Ожидание звонящего...' : 'Waiting for caller...';
      case 'Failed to initialize call':
        return isRu
            ? 'Не удалось инициализировать звонок'
            : 'Failed to initialize call';
      case 'Connection failed':
        return isRu ? 'Не удалось подключиться' : 'Connection failed';
      case 'Disconnected':
        return isRu ? 'Отключено' : 'Disconnected';
      case 'ICE failed':
        return isRu ? 'Ошибка ICE' : 'ICE failed';
      case 'Ringing...':
        return isRu ? 'Вызов...' : 'Ringing...';
      case 'Negotiation retry...':
        return isRu ? 'Повтор согласования...' : 'Negotiation retry...';
      default:
        return status;
    }
  }
}
