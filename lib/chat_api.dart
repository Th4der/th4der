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
    this.imageBase64,
    this.fileBase64,
    this.fileName,
    this.fileMimeType,
    this.fileSize,
    this.readByPeer = false,
    this.pending = false,
  });

  final String id;
  final String conversationId;
  final String sender;
  final String text;
  final DateTime createdAt;
  final String? imageBase64;
  final String? fileBase64;
  final String? fileName;
  final String? fileMimeType;
  final int? fileSize;
  final bool readByPeer;
  final bool pending;

  bool get isMine => sender == 'me';
  bool get hasImage => (imageBase64?.isNotEmpty ?? false);
  bool get hasFile =>
      (fileBase64?.isNotEmpty ?? false) && (fileName?.isNotEmpty ?? false);

  ChatMessage copyWith({bool? pending, bool? readByPeer}) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      sender: sender,
      text: text,
      createdAt: createdAt,
      imageBase64: imageBase64,
      fileBase64: fileBase64,
      fileName: fileName,
      fileMimeType: fileMimeType,
      fileSize: fileSize,
      readByPeer: readByPeer ?? this.readByPeer,
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
      text: json['text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      imageBase64: (json['image_base64'] as String?)?.trim(),
      fileBase64: (json['file_base64'] as String?)?.trim(),
      fileName: (json['file_name'] as String?)?.trim(),
      fileMimeType: (json['file_mime_type'] as String?)?.trim(),
      fileSize: (json['file_size'] as num?)?.toInt(),
      readByPeer: json['read_by_peer'] as bool? ?? false,
    );
  }
}

class SendMessageResult {
  const SendMessageResult({required this.conversation, required this.messages});

  final ConversationSummary conversation;
  final List<ChatMessage> messages;
}

class CallSession {
  const CallSession({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.calleeId,
    required this.state,
    required this.startedAt,
    required this.updatedAt,
    this.answeredAt,
    this.endedAt,
    this.peer,
  });

  final String id;
  final String conversationId;
  final int callerId;
  final int calleeId;
  final String state;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final UserProfile? peer;

  bool get isEnded => state == 'ended' || state == 'rejected';
  bool get isRinging => state == 'ringing';
  bool get isActive => state == 'active';

  factory CallSession.fromJson(Map<String, dynamic> json) {
    final peerMap = json['peer'] as Map<dynamic, dynamic>?;
    return CallSession(
      id: json['id'].toString(),
      conversationId: json['conversation_id'].toString(),
      callerId: (json['caller_id'] as num).toInt(),
      calleeId: (json['callee_id'] as num).toInt(),
      state: json['state'] as String? ?? 'ringing',
      startedAt:
          DateTime.tryParse(json['started_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      answeredAt: DateTime.tryParse(json['answered_at'] as String? ?? ''),
      endedAt: DateTime.tryParse(json['ended_at'] as String? ?? ''),
      peer: peerMap == null
          ? null
          : UserProfile.fromJson(Map<String, dynamic>.from(peerMap)),
    );
  }
}

class IncomingCall {
  const IncomingCall({required this.session});

  final CallSession session;

  factory IncomingCall.fromJson(Map<String, dynamic> json) {
    return IncomingCall(session: CallSession.fromJson(json));
  }
}

class CallSignalEvent {
  const CallSignalEvent({
    required this.id,
    required this.callId,
    required this.senderId,
    required this.recipientId,
    required this.kind,
    required this.createdAt,
    required this.payload,
  });

  final int id;
  final String callId;
  final int senderId;
  final int recipientId;
  final String kind;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  factory CallSignalEvent.fromJson(Map<String, dynamic> json) {
    return CallSignalEvent(
      id: (json['id'] as num).toInt(),
      callId: json['call_id'].toString(),
      senderId: (json['sender_id'] as num).toInt(),
      recipientId: (json['recipient_id'] as num).toInt(),
      kind: (json['kind'] as String? ?? '').toLowerCase(),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      payload: Map<String, dynamic>.from(
        (json['payload'] as Map?) ?? const <String, dynamic>{},
      ),
    );
  }
}

class CallSignalsBatch {
  const CallSignalsBatch({
    required this.session,
    required this.signals,
    required this.lastSignalId,
  });

  final CallSession session;
  final List<CallSignalEvent> signals;
  final int lastSignalId;
}

class RtcBridgeAnswer {
  const RtcBridgeAnswer({required this.sdp, required this.type});

  final String sdp;
  final String type;
}

abstract interface class ChatApi {
  int get currentUserId;

  Future<List<ConversationSummary>> fetchConversations();

  Future<List<ChatMessage>> fetchMessages(String conversationId);

  Future<SendMessageResult> sendMessage({
    required String conversationId,
    required String text,
    String? imageBase64,
    String? fileBase64,
    String? fileName,
    String? fileMimeType,
    int? fileSize,
    String sender,
  });

  Future<ConversationSummary> markRead(String conversationId);

  Future<ConversationSummary> deleteMessage({
    required String conversationId,
    required String messageId,
  });

  Future<UserProfile> fetchCurrentUser();

  Future<UserProfile> updateProfile({
    String? username,
    String? displayName,
    String? password,
  });

  Future<List<UserProfile>> fetchUsers();

  Future<ConversationSummary> createDirectConversation({
    required int partnerUserId,
  });

  Future<CallSession> startCall({required String conversationId});

  Future<List<IncomingCall>> fetchIncomingCalls();

  Future<CallSession> acceptCall(String callId);

  Future<CallSession> rejectCall(String callId);

  Future<CallSession> endCall(String callId);

  Future<void> sendCallSignal({
    required String callId,
    required String kind,
    Map<String, dynamic>? payload,
  });

  Future<CallSignalsBatch> fetchCallSignals({
    required String callId,
    int sinceSignalId,
  });

  Future<RtcBridgeAnswer> connectCallRtc({
    required String callId,
    required String sdp,
    String type,
  });

  Future<void> sendCallRtcCandidate({
    required String callId,
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  });

  Future<void> disconnectCallRtc(String callId);

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
    String? imageBase64,
    String? fileBase64,
    String? fileName,
    String? fileMimeType,
    int? fileSize,
    String sender = 'me',
  }) async {
    final response = await _client.post(
      _uri('/api/conversations/$conversationId/messages'),
      headers: _headers(json: true),
      body: jsonEncode({
        'sender': sender,
        'sender_id': currentUserId,
        'text': text,
        'image_base64': imageBase64,
        'file_base64': fileBase64,
        'file_name': fileName,
        'file_mime_type': fileMimeType,
        'file_size': fileSize,
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
  Future<ConversationSummary> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final response = await _client.delete(
      _uri('/api/conversations/$conversationId/messages/$messageId', {
        'user_id': '$currentUserId',
      }),
      headers: _headers(),
    );
    _ensureSuccess(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['conversation'] is! Map) {
      throw ChatApiException('Unexpected delete-message payload.');
    }
    return ConversationSummary.fromJson(
      Map<String, dynamic>.from(decoded['conversation'] as Map),
    );
  }

  @override
  Future<UserProfile> fetchCurrentUser() async {
    final response = await _client.get(
      _uri('/api/auth/me'),
      headers: _headers(),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['user'] is! Map) {
      throw ChatApiException('Unexpected current-user payload.');
    }
    return UserProfile.fromJson(
      Map<String, dynamic>.from(decoded['user'] as Map),
    );
  }

  @override
  Future<UserProfile> updateProfile({
    String? username,
    String? displayName,
    String? password,
  }) async {
    final body = <String, dynamic>{};
    if (username != null) {
      body['username'] = username.trim().toLowerCase();
    }
    if (displayName != null) {
      body['display_name'] = displayName.trim();
    }
    if (password != null) {
      body['password'] = password;
    }
    final response = await _client.post(
      _uri('/api/auth/profile'),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['user'] is! Map) {
      throw ChatApiException('Unexpected profile-update payload.');
    }
    return UserProfile.fromJson(
      Map<String, dynamic>.from(decoded['user'] as Map),
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
  Future<CallSession> startCall({required String conversationId}) async {
    final response = await _client.post(
      _uri('/api/calls/start'),
      headers: _headers(json: true),
      body: jsonEncode({'conversation_id': conversationId}),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['call'] is! Map) {
      throw ChatApiException('Unexpected start call payload.');
    }
    return CallSession.fromJson(
      Map<String, dynamic>.from(decoded['call'] as Map),
    );
  }

  @override
  Future<List<IncomingCall>> fetchIncomingCalls() async {
    final response = await _client.get(
      _uri('/api/calls/incoming'),
      headers: _headers(),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['calls'] is! List) {
      throw ChatApiException('Unexpected incoming calls payload.');
    }
    return (decoded['calls'] as List<dynamic>)
        .map((item) => IncomingCall.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<CallSession> acceptCall(String callId) async {
    final response = await _client.post(
      _uri('/api/calls/$callId/accept'),
      headers: _headers(),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['call'] is! Map) {
      throw ChatApiException('Unexpected accept call payload.');
    }
    return CallSession.fromJson(Map<String, dynamic>.from(decoded['call']));
  }

  @override
  Future<CallSession> rejectCall(String callId) async {
    final response = await _client.post(
      _uri('/api/calls/$callId/reject'),
      headers: _headers(),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['call'] is! Map) {
      throw ChatApiException('Unexpected reject call payload.');
    }
    return CallSession.fromJson(Map<String, dynamic>.from(decoded['call']));
  }

  @override
  Future<CallSession> endCall(String callId) async {
    final response = await _client.post(
      _uri('/api/calls/$callId/end'),
      headers: _headers(),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['call'] is! Map) {
      throw ChatApiException('Unexpected end call payload.');
    }
    return CallSession.fromJson(Map<String, dynamic>.from(decoded['call']));
  }

  @override
  Future<void> sendCallSignal({
    required String callId,
    required String kind,
    Map<String, dynamic>? payload,
  }) async {
    final response = await _client.post(
      _uri('/api/calls/$callId/signal'),
      headers: _headers(json: true),
      body: jsonEncode({
        'kind': kind,
        ...?((payload == null) ? null : {'payload': payload}),
      }),
    );
    _ensureSuccess(response);
  }

  @override
  Future<CallSignalsBatch> fetchCallSignals({
    required String callId,
    int sinceSignalId = 0,
  }) async {
    final response = await _client.get(
      _uri('/api/calls/$callId/signals', {'since_id': '$sinceSignalId'}),
      headers: _headers(),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['call'] is! Map ||
        decoded['signals'] is! List) {
      throw ChatApiException('Unexpected fetch call signals payload.');
    }
    final signals = (decoded['signals'] as List<dynamic>)
        .map(
          (item) => CallSignalEvent.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
    return CallSignalsBatch(
      session: CallSession.fromJson(Map<String, dynamic>.from(decoded['call'])),
      signals: signals,
      lastSignalId:
          (decoded['last_signal_id'] as num?)?.toInt() ?? sinceSignalId,
    );
  }

  @override
  Future<RtcBridgeAnswer> connectCallRtc({
    required String callId,
    required String sdp,
    String type = 'offer',
  }) async {
    final response = await _client.post(
      _uri('/api/calls/$callId/rtc/connect'),
      headers: _headers(json: true),
      body: jsonEncode({'sdp': sdp, 'type': type}),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['answer'] is! Map) {
      throw ChatApiException('Unexpected rtc connect payload.');
    }
    final answer = Map<String, dynamic>.from(decoded['answer'] as Map);
    final answerSdp = answer['sdp'] as String?;
    final answerType = answer['type'] as String?;
    if (answerSdp == null || answerType == null) {
      throw ChatApiException('Malformed rtc answer.');
    }
    return RtcBridgeAnswer(sdp: answerSdp, type: answerType);
  }

  @override
  Future<void> sendCallRtcCandidate({
    required String callId,
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) async {
    final response = await _client.post(
      _uri('/api/calls/$callId/rtc/candidate'),
      headers: _headers(json: true),
      body: jsonEncode({
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      }),
    );
    _ensureSuccess(response);
  }

  @override
  Future<void> disconnectCallRtc(String callId) async {
    final response = await _client.post(
      _uri('/api/calls/$callId/rtc/disconnect'),
      headers: _headers(),
    );
    _ensureSuccess(response);
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
    String? imageBase64,
    String? fileBase64,
    String? fileName,
    String? fileMimeType,
    int? fileSize,
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
      imageBase64: imageBase64,
      fileBase64: fileBase64,
      fileName: fileName,
      fileMimeType: fileMimeType,
      fileSize: fileSize,
      readByPeer: false,
    );
    final list = _messages.putIfAbsent(conversationId, () => <ChatMessage>[]);
    list.add(message);

    final index = _conversations.indexWhere(
      (item) => item.id == conversationId,
    );
    final previous = _conversations[index];
    final updated = previous.copyWith(
      unreadCount: 0,
      lastMessage: message.text.trim().isNotEmpty
          ? message.text
          : message.hasImage
          ? '[Photo]'
          : message.hasFile
          ? '[File] ${message.fileName}'
          : '',
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
  Future<ConversationSummary> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final list = _messages[conversationId] ?? <ChatMessage>[];
    list.removeWhere((item) => item.id == messageId);

    final index = _conversations.indexWhere(
      (item) => item.id == conversationId,
    );
    if (index == -1) {
      throw ChatApiException('Conversation not found.');
    }
    final updated = _conversations[index].copyWith(
      lastMessage: list.isEmpty
          ? ''
          : (list.last.text.trim().isNotEmpty
                ? list.last.text
                : list.last.hasImage
                ? '[Photo]'
                : list.last.hasFile
                ? '[File] ${list.last.fileName}'
                : ''),
      updatedAt: DateTime.now(),
    );
    _conversations[index] = updated;
    return updated;
  }

  @override
  Future<UserProfile> fetchCurrentUser() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return _users.firstWhere((item) => item.id == currentUserId);
  }

  @override
  Future<UserProfile> updateProfile({
    String? username,
    String? displayName,
    String? password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final index = _users.indexWhere((item) => item.id == currentUserId);
    if (index == -1) {
      throw ChatApiException('Current user not found.');
    }
    final current = _users[index];
    final next = UserProfile(
      id: current.id,
      username: (username == null || username.trim().isEmpty)
          ? current.username
          : username.trim().toLowerCase(),
      displayName: (displayName == null || displayName.trim().isEmpty)
          ? current.displayName
          : displayName.trim(),
      online: current.online,
    );
    _users[index] = next;
    return next;
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
  Future<CallSession> startCall({required String conversationId}) async {
    throw ChatApiException('Calls are not supported in demo mode.');
  }

  @override
  Future<List<IncomingCall>> fetchIncomingCalls() async {
    return const <IncomingCall>[];
  }

  @override
  Future<CallSession> acceptCall(String callId) async {
    throw ChatApiException('Calls are not supported in demo mode.');
  }

  @override
  Future<CallSession> rejectCall(String callId) async {
    throw ChatApiException('Calls are not supported in demo mode.');
  }

  @override
  Future<CallSession> endCall(String callId) async {
    throw ChatApiException('Calls are not supported in demo mode.');
  }

  @override
  Future<void> sendCallSignal({
    required String callId,
    required String kind,
    Map<String, dynamic>? payload,
  }) async {
    throw ChatApiException('Calls are not supported in demo mode.');
  }

  @override
  Future<CallSignalsBatch> fetchCallSignals({
    required String callId,
    int sinceSignalId = 0,
  }) async {
    throw ChatApiException('Calls are not supported in demo mode.');
  }

  @override
  Future<RtcBridgeAnswer> connectCallRtc({
    required String callId,
    required String sdp,
    String type = 'offer',
  }) async {
    throw ChatApiException('Calls are not supported in demo mode.');
  }

  @override
  Future<void> sendCallRtcCandidate({
    required String callId,
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) async {
    throw ChatApiException('Calls are not supported in demo mode.');
  }

  @override
  Future<void> disconnectCallRtc(String callId) async {
    throw ChatApiException('Calls are not supported in demo mode.');
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
