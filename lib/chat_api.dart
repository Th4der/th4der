import 'dart:convert';

import 'package:http/http.dart' as http;

class ChatApiException implements Exception {
  ChatApiException(this.message);

  final String message;

  @override
  String toString() => 'ChatApiException: $message';
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.online,
  });

  final int id;
  final String username;
  final String displayName;
  final bool online;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      online: json['online'] as bool? ?? false,
    );
  }
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final UserProfile user;
}

class AuthApi {
  AuthApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  String get _normalizedBaseUrl => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Uri _uri(String path) => Uri.parse('$_normalizedBaseUrl$path');

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final response = await _client.post(
      _uri('/api/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username.trim().toLowerCase(),
        'password': password,
      }),
    );
    _ensureSuccess(response);
    return _parseAuthSession(response.body);
  }

  Future<AuthSession> register({
    required String username,
    required String displayName,
    required String password,
  }) async {
    final response = await _client.post(
      _uri('/api/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username.trim().toLowerCase(),
        'display_name': displayName.trim(),
        'password': password,
      }),
    );
    _ensureSuccess(response);
    return _parseAuthSession(response.body);
  }

  AuthSession _parseAuthSession(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw ChatApiException('Unexpected auth payload.');
    }
    final token = decoded['token'] as String?;
    final userMap = decoded['user'] as Map<dynamic, dynamic>?;
    if (token == null || userMap == null) {
      throw ChatApiException('Malformed auth response.');
    }
    return AuthSession(
      token: token,
      user: UserProfile.fromJson(Map<String, dynamic>.from(userMap)),
    );
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw ChatApiException(
        'API error ${response.statusCode}: ${response.body}',
      );
    }
  }
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.name,
    required this.handle,
    required this.online,
    required this.pinned,
    required this.unreadCount,
    required this.lastMessage,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String handle;
  final bool online;
  final bool pinned;
  final int unreadCount;
  final String lastMessage;
  final DateTime updatedAt;

  ConversationSummary copyWith({
    bool? online,
    int? unreadCount,
    String? lastMessage,
    DateTime? updatedAt,
  }) {
    return ConversationSummary(
      id: id,
      name: name,
      handle: handle,
      online: online ?? this.online,
      pinned: pinned,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'].toString(),
      name: json['name'] as String,
      handle: json['handle'] as String,
      online: json['online'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessage: json['last_message'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.text,
    required this.createdAt,
    this.pending = false,
  });

  final String id;
  final String conversationId;
  final String sender;
  final String text;
  final DateTime createdAt;
  final bool pending;

  bool get isMine => sender == 'me';

  ChatMessage copyWith({bool? pending}) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      sender: sender,
      text: text,
      createdAt: createdAt,
      pending: pending ?? this.pending,
    );
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    int? currentUserId,
  }) {
    final sender = (json['sender'] as String?)?.trim();
    final senderId = (json['sender_id'] as num?)?.toInt();
    final resolvedSender =
        sender ??
        ((currentUserId != null && senderId == currentUserId)
            ? 'me'
            : 'contact');
    return ChatMessage(
      id: json['id'].toString(),
      conversationId: json['conversation_id'].toString(),
      sender: resolvedSender,
      text: json['text'] as String,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class SendMessageResult {
  const SendMessageResult({required this.conversation, required this.messages});

  final ConversationSummary conversation;
  final List<ChatMessage> messages;
}

abstract interface class ChatApi {
  int get currentUserId;

  Future<List<ConversationSummary>> fetchConversations();

  Future<List<ChatMessage>> fetchMessages(String conversationId);

  Future<SendMessageResult> sendMessage({
    required String conversationId,
    required String text,
    String sender,
  });

  Future<ConversationSummary> markRead(String conversationId);

  Future<List<UserProfile>> fetchUsers();

  Future<ConversationSummary> createDirectConversation({
    required int partnerUserId,
  });

  Future<void> logout();
}

class HttpChatApi implements ChatApi {
  HttpChatApi({
    required this.baseUrl,
    required this.currentUserId,
    this.authToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  @override
  final int currentUserId;
  final String? authToken;
  final http.Client _client;

  String get _normalizedBaseUrl => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    return Uri.parse(
      '$_normalizedBaseUrl$path',
    ).replace(queryParameters: queryParameters);
  }

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    if (authToken != null && authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  @override
  Future<List<ConversationSummary>> fetchConversations() async {
    final response = await _client.get(
      _uri('/api/conversations', {'user_id': '$currentUserId'}),
      headers: _headers(),
    );
    _ensureSuccess(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw ChatApiException('Unexpected conversations payload.');
    }
    return decoded
        .map(
          (item) => ConversationSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    final response = await _client.get(
      _uri('/api/conversations/$conversationId/messages', {
        'user_id': '$currentUserId',
      }),
      headers: _headers(),
    );
    _ensureSuccess(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['messages'] is! List) {
      throw ChatApiException('Unexpected messages payload.');
    }

    final messages = decoded['messages'] as List<dynamic>;
    return messages
        .map(
          (item) => ChatMessage.fromJson(
            Map<String, dynamic>.from(item as Map),
            currentUserId: currentUserId,
          ),
        )
        .toList();
  }

  @override
  Future<SendMessageResult> sendMessage({
    required String conversationId,
    required String text,
    String sender = 'me',
  }) async {
    final response = await _client.post(
      _uri('/api/conversations/$conversationId/messages'),
      headers: _headers(json: true),
      body: jsonEncode({
        'sender': sender,
        'sender_id': currentUserId,
        'text': text,
      }),
    );
    _ensureSuccess(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ChatApiException('Unexpected send payload.');
    }

    final conversation = ConversationSummary.fromJson(
      Map<String, dynamic>.from(decoded['conversation'] as Map),
    );
    final messages = (decoded['messages'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (item) => ChatMessage.fromJson(
            Map<String, dynamic>.from(item as Map),
            currentUserId: currentUserId,
          ),
        )
        .toList();

    return SendMessageResult(conversation: conversation, messages: messages);
  }

  @override
  Future<ConversationSummary> markRead(String conversationId) async {
    final response = await _client.post(
      _uri('/api/conversations/$conversationId/read', {
        'user_id': '$currentUserId',
      }),
      headers: _headers(),
    );
    _ensureSuccess(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['conversation'] is! Map) {
      throw ChatApiException('Unexpected mark-read payload.');
    }
    return ConversationSummary.fromJson(
      Map<String, dynamic>.from(decoded['conversation'] as Map),
    );
  }

  @override
  Future<List<UserProfile>> fetchUsers() async {
    final response = await _client.get(_uri('/api/users'), headers: _headers());
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw ChatApiException('Unexpected users payload.');
    }
    return decoded
        .map(
          (item) =>
              UserProfile.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  @override
  Future<ConversationSummary> createDirectConversation({
    required int partnerUserId,
  }) async {
    final response = await _client.post(
      _uri('/api/conversations/direct'),
      headers: _headers(json: true),
      body: jsonEncode({
        'partner_user_id': partnerUserId,
        'user_a_id': currentUserId,
        'user_b_id': partnerUserId,
      }),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['conversation'] is! Map) {
      throw ChatApiException('Unexpected create conversation payload.');
    }
    return ConversationSummary.fromJson(
      Map<String, dynamic>.from(decoded['conversation'] as Map),
    );
  }

  @override
  Future<void> logout() async {
    if (authToken == null || authToken!.isEmpty) {
      return;
    }
    final response = await _client.post(
      _uri('/api/auth/logout'),
      headers: _headers(),
    );
    _ensureSuccess(response);
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw ChatApiException(
        'API error ${response.statusCode}: ${response.body}',
      );
    }
  }
}

class DemoChatApi implements ChatApi {
  DemoChatApi({this.currentUserId = 1}) {
    final now = DateTime.now();
    _users = [
      const UserProfile(
        id: 1,
        username: 'leo',
        displayName: 'Leo',
        online: true,
      ),
      const UserProfile(
        id: 2,
        username: 'diana',
        displayName: 'Diana',
        online: true,
      ),
      const UserProfile(
        id: 3,
        username: 'olga',
        displayName: 'Olga',
        online: false,
      ),
    ];
    _conversations = [
      ConversationSummary(
        id: 'c-1',
        name: 'Diana',
        handle: '@diana',
        online: true,
        pinned: true,
        unreadCount: 2,
        lastMessage: 'I will share the latest design in 10 minutes.',
        updatedAt: now.subtract(const Duration(minutes: 3)),
      ),
      ConversationSummary(
        id: 'c-2',
        name: 'Olga',
        handle: '@olga',
        online: false,
        pinned: false,
        unreadCount: 0,
        lastMessage: 'Can we review this later?',
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
    ];
    _messages = {
      'c-1': [
        ChatMessage(
          id: 'm-1',
          conversationId: 'c-1',
          sender: 'contact',
          text: 'I will share the latest design in 10 minutes.',
          createdAt: now.subtract(const Duration(minutes: 3)),
        ),
      ],
      'c-2': [
        ChatMessage(
          id: 'm-2',
          conversationId: 'c-2',
          sender: 'contact',
          text: 'Can we review this later?',
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
      ],
    };
  }

  @override
  final int currentUserId;
  late final List<UserProfile> _users;
  late List<ConversationSummary> _conversations;
  late Map<String, List<ChatMessage>> _messages;
  int _counter = 100;

  @override
  Future<List<ConversationSummary>> fetchConversations() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _sorted(_conversations);
  }

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return [...(_messages[conversationId] ?? const <ChatMessage>[])];
  }

  @override
  Future<SendMessageResult> sendMessage({
    required String conversationId,
    required String text,
    String sender = 'me',
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 160));
    final now = DateTime.now();
    final message = ChatMessage(
      id: 'm-${_counter++}',
      conversationId: conversationId,
      sender: sender,
      text: text,
      createdAt: now,
    );
    final list = _messages.putIfAbsent(conversationId, () => <ChatMessage>[]);
    list.add(message);

    final index = _conversations.indexWhere(
      (item) => item.id == conversationId,
    );
    final previous = _conversations[index];
    final updated = previous.copyWith(
      unreadCount: 0,
      lastMessage: message.text,
      updatedAt: now,
    );
    _conversations[index] = updated;

    return SendMessageResult(conversation: updated, messages: [message]);
  }

  @override
  Future<ConversationSummary> markRead(String conversationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final index = _conversations.indexWhere(
      (item) => item.id == conversationId,
    );
    final updated = _conversations[index].copyWith(unreadCount: 0);
    _conversations[index] = updated;
    return updated;
  }

  @override
  Future<List<UserProfile>> fetchUsers() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return _users;
  }

  @override
  Future<ConversationSummary> createDirectConversation({
    required int partnerUserId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final user = _users.firstWhere((item) => item.id == partnerUserId);
    final existing = _conversations
        .where((item) => item.handle == '@${user.username}')
        .toList();
    if (existing.isNotEmpty) {
      return existing.first;
    }
    final conversation = ConversationSummary(
      id: 'c-${_counter++}',
      name: user.displayName,
      handle: '@${user.username}',
      online: user.online,
      pinned: false,
      unreadCount: 0,
      lastMessage: '',
      updatedAt: DateTime.now(),
    );
    _conversations = [conversation, ..._conversations];
    _messages[conversation.id] = <ChatMessage>[];
    return conversation;
  }

  @override
  Future<void> logout() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }

  List<ConversationSummary> _sorted(List<ConversationSummary> input) {
    final copy = [...input];
    copy.sort((left, right) {
      if (left.pinned != right.pinned) {
        return left.pinned ? -1 : 1;
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return copy;
  }
}
