from __future__ import annotations

import asyncio
import base64
import binascii
import inspect as pyinspect
import json
import os
import threading
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, cast

import jwt
from flask import Flask, jsonify, request
from flask_sock import Sock
from jwt import InvalidTokenError
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    create_engine,
    event,
    func,
    inspect,
    or_,
    text,
)
from sqlalchemy import orm as sa_orm
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import relationship, sessionmaker
from werkzeug.security import check_password_hash, generate_password_hash

declarative_base = getattr(sa_orm, "declarative_base", None)
if declarative_base is None:
    from sqlalchemy.ext.declarative import declarative_base

try:
    from aiortc import (
        RTCConfiguration,
        RTCIceServer,
        RTCPeerConnection,
        RTCSessionDescription,
    )
    from aiortc.contrib.media import MediaRelay
    from aiortc.sdp import candidate_from_sdp

    AIORTC_AVAILABLE = True
except Exception:
    class _AiortcMissingRuntimeError(RuntimeError):
        pass

    def _aiortc_missing(*args: Any, **kwargs: Any) -> Any:
        raise _AiortcMissingRuntimeError("aiortc is not installed")

    RTCConfiguration = _aiortc_missing  # type: ignore[assignment]
    RTCIceServer = _aiortc_missing  # type: ignore[assignment]
    RTCPeerConnection = _aiortc_missing  # type: ignore[assignment]
    RTCSessionDescription = _aiortc_missing  # type: ignore[assignment]
    MediaRelay = _aiortc_missing  # type: ignore[assignment]
    candidate_from_sdp = _aiortc_missing  # type: ignore[assignment]
    AIORTC_AVAILABLE = False

BASE_DIR = Path(__file__).resolve().parent
DATABASE_PATH = (BASE_DIR / "th4der.db").as_posix()
DATABASE_URL = (
    os.getenv("TH4DER_DATABASE_URL")
    or os.getenv("DATABASE_URL")
    or f"sqlite:///{DATABASE_PATH}"
).strip()
if DATABASE_URL.startswith("postgres://"):
    # SQLAlchemy expects `postgresql://`, while many providers return `postgres://`.
    DATABASE_URL = f"postgresql://{DATABASE_URL[len('postgres://'):]}"
IS_SQLITE_DB = DATABASE_URL.startswith("sqlite:")

JWT_SECRET = os.getenv("TH4DER_JWT_SECRET", "th4der-dev-secret")
JWT_ALGORITHM = "HS256"
JWT_EXPIRES_HOURS = int(os.getenv("TH4DER_JWT_EXPIRES_HOURS", "72"))
ONLINE_WINDOW_SECONDS = int(os.getenv("TH4DER_ONLINE_WINDOW_SECONDS", "20"))
CALL_RINGING_STALE_SECONDS = int(os.getenv("TH4DER_CALL_RINGING_STALE_SECONDS", "45"))
CALL_ACTIVE_STALE_SECONDS = int(os.getenv("TH4DER_CALL_ACTIVE_STALE_SECONDS", "120"))
CALL_DEBUG_LOGGING = os.getenv("TH4DER_CALL_DEBUG_LOGGING", "0") == "1"
MAX_MESSAGE_IMAGE_BYTES = int(os.getenv("TH4DER_MAX_MESSAGE_IMAGE_BYTES", str(15 * 1024 * 1024)))
MAX_MESSAGE_FILE_BYTES = int(os.getenv("TH4DER_MAX_MESSAGE_FILE_BYTES", str(90 * 1024 * 1024)))

if IS_SQLITE_DB:
    engine = create_engine(
        DATABASE_URL,
        connect_args={"check_same_thread": False, "timeout": 30},
    )
else:
    engine = create_engine(
        DATABASE_URL,
        pool_pre_ping=True,
        pool_recycle=300,
    )
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


if IS_SQLITE_DB:
    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, connection_record):  # type: ignore[no-untyped-def]
        cursor = dbapi_connection.cursor()
        try:
            cursor.execute("PRAGMA journal_mode=WAL;")
            cursor.execute("PRAGMA synchronous=NORMAL;")
            cursor.execute("PRAGMA busy_timeout=30000;")
        finally:
            cursor.close()

app = Flask(__name__)
sock = Sock(app)
Base = declarative_base()

_ws_clients: dict[int, set[Any]] = {}
_ws_clients_lock = threading.Lock()


@dataclass
class _RtcCallPeer:
    call_id: int
    user_id: int
    pc: Any
    audio_sender: Any | None = None
    video_sender: Any | None = None
    inbound_audio: Any | None = None
    inbound_video: Any | None = None
    last_offer_sdp: str | None = None


@dataclass
class _RtcCallRoom:
    call_id: int
    peers: dict[int, _RtcCallPeer] = field(default_factory=dict)


_rtc_rooms: dict[int, _RtcCallRoom] = {}
_rtc_rooms_lock = threading.RLock()
_rtc_relay = MediaRelay() if AIORTC_AVAILABLE else None
_rtc_loop: asyncio.AbstractEventLoop | None = None
_rtc_loop_thread: threading.Thread | None = None


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    username = Column(String(64), unique=True, index=True, nullable=False)
    display_name = Column(String(128), nullable=False)
    password_hash = Column(String(255), nullable=False, default="")
    online = Column(Boolean, default=False, nullable=False)
    last_seen_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )

    participants = relationship("ConversationParticipant", back_populates="user")
    sent_messages = relationship("Message", back_populates="sender")


class Conversation(Base):
    __tablename__ = "conversations"

    id = Column(Integer, primary_key=True)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )

    participants = relationship(
        "ConversationParticipant",
        back_populates="conversation",
        cascade="all, delete-orphan",
    )
    messages = relationship(
        "Message",
        back_populates="conversation",
        cascade="all, delete-orphan",
        order_by="Message.id",
    )


class ConversationParticipant(Base):
    __tablename__ = "conversation_participants"
    __table_args__ = (
        UniqueConstraint("conversation_id", "user_id", name="uq_conversation_user"),
    )

    id = Column(Integer, primary_key=True)
    conversation_id = Column(
        Integer,
        ForeignKey("conversations.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    pinned = Column(Boolean, default=False, nullable=False)
    last_read_message_id = Column(Integer, nullable=True)

    conversation = relationship("Conversation", back_populates="participants")
    user = relationship("User", back_populates="participants")


class Message(Base):
    __tablename__ = "messages"

    id = Column(Integer, primary_key=True)
    conversation_id = Column(
        Integer,
        ForeignKey("conversations.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    sender_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    text = Column(Text, nullable=False)
    image_base64 = Column(Text, nullable=True)
    file_base64 = Column(Text, nullable=True)
    file_name = Column(String(255), nullable=True)
    file_mime_type = Column(String(255), nullable=True)
    file_size = Column(Integer, nullable=True)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )

    conversation = relationship("Conversation", back_populates="messages")
    sender = relationship("User", back_populates="sent_messages")


class CallSession(Base):
    __tablename__ = "call_sessions"

    id = Column(Integer, primary_key=True)
    conversation_id = Column(
        Integer,
        ForeignKey("conversations.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    caller_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    callee_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    state = Column(String(32), nullable=False, default="ringing")
    started_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(UTC))
    answered_at = Column(DateTime(timezone=True), nullable=True)
    ended_at = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(UTC))


class CallSignal(Base):
    __tablename__ = "call_signals"

    id = Column(Integer, primary_key=True)
    call_id = Column(
        Integer,
        ForeignKey("call_sessions.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    sender_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    recipient_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    kind = Column(String(32), nullable=False)
    payload = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(UTC))


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _iso(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _parse_user_id(raw: Any, default: int = 1) -> int:
    try:
        value = int(raw)
    except (TypeError, ValueError):
        return default
    return value if value > 0 else default


def _set_conversation_updated_at(conversation: Conversation, value: datetime) -> None:
    setattr(conversation, "updated_at", value)


def _set_user_online(user: User, value: bool) -> None:
    setattr(user, "online", value)


def _set_user_last_seen(user: User, value: datetime) -> None:
    setattr(user, "last_seen_at", value)


def _set_call_state(call: CallSession, value: str) -> None:
    setattr(call, "state", value)


def _set_call_updated_at(call: CallSession, value: datetime) -> None:
    setattr(call, "updated_at", value)


def _set_call_answered_at(call: CallSession, value: datetime | None) -> None:
    setattr(call, "answered_at", value)


def _set_call_ended_at(call: CallSession, value: datetime | None) -> None:
    setattr(call, "ended_at", value)


def _is_user_online(user: User) -> bool:
    if not bool(user.online):
        return False
    last_seen = user.last_seen_at
    if not isinstance(last_seen, datetime):
        return False
    if last_seen.tzinfo is None:
        last_seen = last_seen.replace(tzinfo=UTC)
    delta_seconds = (_utc_now() - last_seen.astimezone(UTC)).total_seconds()
    return delta_seconds <= ONLINE_WINDOW_SECONDS


def _touch_user_presence(session, user: User) -> None:
    _set_user_online(user, True)
    _set_user_last_seen(user, _utc_now())
    session.commit()
    session.refresh(user)


def _public_user(user: User) -> dict[str, Any]:
    return {
        "id": user.id,
        "username": user.username,
        "display_name": user.display_name,
        "online": _is_user_online(user),
    }


def _create_jwt(user: User) -> str:
    now = _utc_now()
    payload = {
        "sub": str(user.id),
        "username": user.username,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(hours=JWT_EXPIRES_HOURS)).timestamp()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def _extract_bearer_token() -> str | None:
    header = request.headers.get("Authorization", "").strip()
    if not header.lower().startswith("bearer "):
        return None
    token = header[7:].strip()
    return token or None


def _user_from_token(session, *, touch: bool = False) -> User | None:
    token = _extract_bearer_token()
    if token is None:
        return None
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except InvalidTokenError:
        return None
    user_id = _parse_user_id(payload.get("sub"), default=0)
    if user_id == 0:
        return None
    user = session.query(User).filter(User.id == user_id).one_or_none()
    if user is not None and touch:
        _touch_user_presence(session, user)
    return user


def _user_from_raw_token(session, token: str, *, touch: bool = False) -> User | None:
    token_value = (token or "").strip()
    if not token_value:
        return None
    try:
        payload = jwt.decode(token_value, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except InvalidTokenError:
        return None
    user_id = _parse_user_id(payload.get("sub"), default=0)
    if user_id == 0:
        return None
    user = session.query(User).filter(User.id == user_id).one_or_none()
    if user is not None and touch:
        _touch_user_presence(session, user)
    return user


def _resolve_request_user(session, default: int = 1) -> User | None:
    from_token = _user_from_token(session, touch=True)
    if from_token is not None:
        return from_token
    fallback_user_id = _parse_user_id(request.args.get("user_id"), default=default)
    return session.query(User).filter(User.id == fallback_user_id).one_or_none()


def _conversation_summary(session, conversation: Conversation, viewer_id: int) -> dict[str, Any]:
    viewer_participant = None
    other_participant = None
    for participant in conversation.participants:
        if participant.user_id == viewer_id:
            viewer_participant = participant
        else:
            other_participant = participant

    if viewer_participant is None:
        raise ValueError("Viewer is not a participant in this conversation")

    other_user = None
    if other_participant is not None:
        other_user = session.query(User).filter(User.id == other_participant.user_id).one_or_none()
    if other_user is None:
        other_user = session.query(User).filter(User.id == viewer_id).one_or_none()
    if other_user is None:
        raise ValueError("User not found")

    last_message_row = (
        session.query(
            Message.text,
            Message.file_name,
            func.length(Message.image_base64),
            func.length(Message.file_base64),
        )
        .filter(Message.conversation_id == conversation.id)
        .order_by(Message.id.desc())
        .limit(1)
        .one_or_none()
    )
    last_read_id = viewer_participant.last_read_message_id or 0
    unread_count = (
        session.query(func.count(Message.id))
        .filter(
            Message.conversation_id == conversation.id,
            Message.id > last_read_id,
            Message.sender_id != viewer_id,
        )
        .scalar()
        or 0
    )

    if last_message_row is None:
        last_message_text = ""
    else:
        last_message_text_raw = str(last_message_row[0] or "").strip()
        last_message_file_name = str(last_message_row[1] or "").strip()
        has_image = (last_message_row[2] or 0) > 0
        has_file = (last_message_row[3] or 0) > 0
        if last_message_text_raw:
            last_message_text = last_message_text_raw
        elif has_image:
            last_message_text = "[Photo]"
        elif has_file:
            last_message_text = (
                f"[File] {last_message_file_name}"
                if last_message_file_name
                else "[File]"
            )
        else:
            last_message_text = ""

    return {
        "id": str(conversation.id),
        "name": other_user.display_name,
        "handle": f"@{other_user.username}",
        "online": _is_user_online(other_user),
        "pinned": bool(viewer_participant.pinned),
        "unread_count": int(unread_count),
        "last_message": last_message_text,
        "updated_at": _iso(conversation.updated_at),
    }


def _message_payload(
    message: Message,
    viewer_id: int,
    peer_last_read_id: int | None = None,
) -> dict[str, Any]:
    read_by_peer = False
    if message.sender_id == viewer_id:
        if peer_last_read_id is None:
            conversation = message.conversation
            peer_last_read_id = 0
            if conversation is not None:
                for participant in conversation.participants:
                    if participant.user_id != viewer_id:
                        peer_last_read_id = participant.last_read_message_id or 0
                        break
        read_by_peer = (peer_last_read_id or 0) >= message.id
    return {
        "id": str(message.id),
        "conversation_id": str(message.conversation_id),
        "sender": "me" if message.sender_id == viewer_id else "contact",
        "sender_id": message.sender_id,
        "text": message.text,
        "image_base64": message.image_base64,
        "file_base64": message.file_base64,
        "file_name": message.file_name,
        "file_mime_type": message.file_mime_type,
        "file_size": message.file_size,
        "read_by_peer": read_by_peer,
        "created_at": _iso(message.created_at),
    }


def _normalize_message_image_base64(raw_value: Any) -> str | None:
    if raw_value is None:
        return None
    value = str(raw_value).strip()
    if not value:
        return None
    if value.startswith("data:"):
        _, _, value = value.partition(",")
    value = value.replace("\n", "").replace("\r", "")
    if not value:
        return None

    # Quick guard to avoid very large payloads before full decode.
    if len(value) > MAX_MESSAGE_IMAGE_BYTES * 2:
        raise ValueError("Image is too large")

    try:
        decoded = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("Field 'image_base64' must be valid base64") from exc
    if not decoded:
        return None
    if len(decoded) > MAX_MESSAGE_IMAGE_BYTES:
        raise ValueError("Image is too large")
    return base64.b64encode(decoded).decode("ascii")


def _normalize_message_file_payload(
    raw_file_base64: Any,
    raw_file_name: Any,
    raw_file_mime_type: Any,
    raw_file_size: Any,
) -> tuple[str | None, str | None, str | None, int | None]:
    if raw_file_base64 is None and raw_file_name is None and raw_file_mime_type is None and raw_file_size is None:
        return (None, None, None, None)

    value = str(raw_file_base64 or "").strip()
    if value.startswith("data:"):
        _, _, value = value.partition(",")
    value = value.replace("\n", "").replace("\r", "")
    if not value:
        raise ValueError("Field 'file_base64' is required when sending a file")

    file_name = str(raw_file_name or "").strip()
    if not file_name:
        raise ValueError("Field 'file_name' is required when sending a file")
    if len(file_name) > 255:
        file_name = file_name[:255]

    file_mime_type = str(raw_file_mime_type or "").strip()
    if len(file_mime_type) > 255:
        file_mime_type = file_mime_type[:255]
    if not file_mime_type:
        file_mime_type = "application/octet-stream"

    try:
        decoded = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("Field 'file_base64' must be valid base64") from exc
    if not decoded:
        raise ValueError("File is empty")
    if len(decoded) > MAX_MESSAGE_FILE_BYTES:
        raise ValueError("File is too large")

    if raw_file_size is None:
        file_size = len(decoded)
    else:
        try:
            file_size = int(raw_file_size)
        except (TypeError, ValueError) as exc:
            raise ValueError("Field 'file_size' must be an integer") from exc
        if file_size <= 0:
            raise ValueError("Field 'file_size' must be positive")
        if file_size != len(decoded):
            file_size = len(decoded)

    return (base64.b64encode(decoded).decode("ascii"), file_name, file_mime_type, file_size)


def _call_participants_for_conversation(session, conversation_id: int) -> list[int]:
    rows = (
        session.query(ConversationParticipant.user_id)
        .filter(ConversationParticipant.conversation_id == conversation_id)
        .all()
    )
    return [row[0] for row in rows]


def _call_other_user_id(call: CallSession, user_id: int) -> int | None:
    if call.caller_id == user_id:
        return call.callee_id
    if call.callee_id == user_id:
        return call.caller_id
    return None


def _call_for_user(session, call_id: int, user_id: int) -> CallSession | None:
    call = session.query(CallSession).filter(CallSession.id == call_id).one_or_none()
    if call is None:
        return None
    if user_id not in {call.caller_id, call.callee_id}:
        return None
    return call


def _call_payload(session, call: CallSession, viewer_id: int) -> dict[str, Any]:
    other_id = _call_other_user_id(call, viewer_id) or call.caller_id
    other = session.query(User).filter(User.id == other_id).one_or_none()
    return {
        "id": str(call.id),
        "conversation_id": str(call.conversation_id),
        "caller_id": call.caller_id,
        "callee_id": call.callee_id,
        "state": call.state,
        "started_at": _iso(call.started_at),
        "answered_at": _iso(call.answered_at) if isinstance(call.answered_at, datetime) else None,
        "ended_at": _iso(call.ended_at) if isinstance(call.ended_at, datetime) else None,
        "updated_at": _iso(call.updated_at),
        "peer": _public_user(other) if other is not None else None,
    }


def _call_signal_payload(signal: CallSignal) -> dict[str, Any]:
    payload_obj: Any = None
    if signal.payload:
        try:
            payload_obj = json.loads(signal.payload)
        except json.JSONDecodeError:
            payload_obj = {"raw": signal.payload}
    return {
        "id": signal.id,
        "call_id": str(signal.call_id),
        "sender_id": signal.sender_id,
        "recipient_id": signal.recipient_id,
        "kind": signal.kind,
        "payload": payload_obj,
        "created_at": _iso(signal.created_at),
    }


def _push_call_signal(
    session,
    *,
    call_id: int,
    sender_id: int,
    recipient_id: int,
    kind: str,
    payload: dict[str, Any] | None = None,
) -> CallSignal:
    signal = CallSignal(
        call_id=call_id,
        sender_id=sender_id,
        recipient_id=recipient_id,
        kind=kind,
        payload=json.dumps(payload) if payload is not None else None,
        created_at=_utc_now(),
    )
    session.add(signal)
    session.flush()
    return signal


def _as_utc(value: datetime | None) -> datetime | None:
    if not isinstance(value, datetime):
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _is_call_stale(call: CallSession, now: datetime) -> bool:
    reference = _as_utc(call.updated_at) or _as_utc(call.started_at) or now
    age_seconds = (now - reference).total_seconds()
    if call.state == "ringing":
        return age_seconds > CALL_RINGING_STALE_SECONDS
    if call.state == "active":
        return age_seconds > CALL_ACTIVE_STALE_SECONDS
    return False


def _mark_call_ended(call: CallSession, now: datetime) -> None:
    if call.state in {"ended", "rejected"}:
        return
    _set_call_state(call, "ended")
    _set_call_ended_at(call, now)
    _set_call_updated_at(call, now)


def _call_debug(event: str, **fields: Any) -> None:
    if not CALL_DEBUG_LOGGING:
        return
    text_fields = " ".join(f"{key}={value}" for key, value in fields.items())
    print(f"[CALL_DEBUG] {event} {text_fields}")


def _rtc_loop_worker(loop: asyncio.AbstractEventLoop) -> None:
    def _loop_exception_handler(loop_obj: asyncio.AbstractEventLoop, context: dict[str, Any]) -> None:
        exc = context.get("exception")
        message = str(context.get("message", ""))
        text = str(exc) if exc is not None else message

        # aiortc can emit late transport-close exceptions after peer teardown.
        # These are expected in reconnect flows and should not spam logs.
        if "RTCIceTransport is closed" in text:
            _call_debug("rtc.loop_ignored", error=text)
            return

        if exc is not None:
            _call_debug("rtc.loop_exception", error=str(exc), message=message)
            return
        if message:
            _call_debug("rtc.loop_exception", message=message)

    loop.set_exception_handler(_loop_exception_handler)
    asyncio.set_event_loop(loop)
    loop.run_forever()


def _start_rtc_loop_if_needed() -> None:
    global _rtc_loop, _rtc_loop_thread
    if not AIORTC_AVAILABLE:
        return
    with _rtc_rooms_lock:
        if _rtc_loop is not None:
            return
        loop = asyncio.new_event_loop()
        thread = threading.Thread(
            target=_rtc_loop_worker,
            args=(loop,),
            name="th4der-aiortc-loop",
            daemon=True,
        )
        thread.start()
        _rtc_loop = loop
        _rtc_loop_thread = thread


def _run_on_rtc_loop(coro: Any, *, timeout: float = 20.0) -> Any:
    _start_rtc_loop_if_needed()
    if _rtc_loop is None:
        raise RuntimeError("aiortc loop is not initialized")
    future = asyncio.run_coroutine_threadsafe(coro, _rtc_loop)
    return future.result(timeout=timeout)


def _rtc_ice_servers() -> list[Any]:
    urls_raw = os.getenv("TH4DER_RTC_ICE_SERVERS", "stun:stun.l.google.com:19302")
    urls = [item.strip() for item in urls_raw.split(",") if item.strip()]
    servers = [RTCIceServer(urls=[url]) for url in urls]
    turn_url = os.getenv("TH4DER_RTC_TURN_URL", "").strip()
    if turn_url:
        servers.append(
            RTCIceServer(
                urls=[turn_url],
                username=os.getenv("TH4DER_RTC_TURN_USERNAME", "").strip(),
                credential=os.getenv("TH4DER_RTC_TURN_CREDENTIAL", "").strip(),
            )
        )
    return servers


def _rtc_get_peer(call_id: int, user_id: int) -> _RtcCallPeer | None:
    with _rtc_rooms_lock:
        room = _rtc_rooms.get(call_id)
        if room is None:
            return None
        return room.peers.get(user_id)


async def _rtc_replace_sender_track(sender: Any, track: Any) -> None:
    if sender is None:
        return
    try:
        # aiortc replaceTrack may be sync (returns None) or awaitable depending on version.
        result = sender.replaceTrack(track)
        if pyinspect.isawaitable(result):
            await result
    except Exception as exc:
        _call_debug("rtc.replace_track_error", error=str(exc))


async def _rtc_refresh_room_tracks(call_id: int) -> None:
    with _rtc_rooms_lock:
        room = _rtc_rooms.get(call_id)
        peers = list(room.peers.values()) if room is not None else []

    if not peers:
        return

    if len(peers) < 2:
        only = peers[0]
        await _rtc_replace_sender_track(only.audio_sender, None)
        await _rtc_replace_sender_track(only.video_sender, None)
        _call_debug(
            "rtc.refresh",
            call_id=call_id,
            peers=len(peers),
            user_id=only.user_id,
            audio_sender=only.audio_sender is not None,
            video_sender=only.video_sender is not None,
            inbound_audio=only.inbound_audio is not None,
            inbound_video=only.inbound_video is not None,
        )
        return

    left = peers[0]
    right = peers[1]
    await _rtc_replace_sender_track(left.audio_sender, right.inbound_audio)
    await _rtc_replace_sender_track(left.video_sender, right.inbound_video)
    await _rtc_replace_sender_track(right.audio_sender, left.inbound_audio)
    await _rtc_replace_sender_track(right.video_sender, left.inbound_video)
    _call_debug(
        "rtc.refresh",
        call_id=call_id,
        peers=len(peers),
        left_user=left.user_id,
        right_user=right.user_id,
        left_audio_sender=left.audio_sender is not None,
        left_video_sender=left.video_sender is not None,
        right_audio_sender=right.audio_sender is not None,
        right_video_sender=right.video_sender is not None,
        left_in_audio=left.inbound_audio is not None,
        left_in_video=left.inbound_video is not None,
        right_in_audio=right.inbound_audio is not None,
        right_in_video=right.inbound_video is not None,
    )

    for extra in peers[2:]:
        await _rtc_replace_sender_track(extra.audio_sender, None)
        await _rtc_replace_sender_track(extra.video_sender, None)


async def _rtc_remove_peer(
    call_id: int,
    user_id: int,
    *,
    reason: str = "",
    expected_pc: Any | None = None,
) -> None:
    peer: _RtcCallPeer | None = None
    with _rtc_rooms_lock:
        room = _rtc_rooms.get(call_id)
        if room is not None:
            candidate = room.peers.get(user_id)
            if candidate is None:
                return
            if expected_pc is not None and candidate.pc is not expected_pc:
                return
            peer = room.peers.pop(user_id, None)
            if not room.peers:
                _rtc_rooms.pop(call_id, None)
    if peer is None:
        return

    try:
        await peer.pc.close()
    except Exception:
        pass
    _call_debug(
        "rtc.peer_closed",
        call_id=call_id,
        user_id=user_id,
        reason=reason or "removed",
    )
    await _rtc_refresh_room_tracks(call_id)


async def _rtc_close_call_room(call_id: int, *, reason: str = "") -> None:
    with _rtc_rooms_lock:
        room = _rtc_rooms.pop(call_id, None)
    if room is None:
        return
    peers = list(room.peers.values())
    for peer in peers:
        try:
            await peer.pc.close()
        except Exception:
            pass
    _call_debug("rtc.room_closed", call_id=call_id, reason=reason or "closed")


async def _rtc_connect_offer(
    *,
    call_id: int,
    user_id: int,
    sdp: str,
    sdp_type: str,
) -> dict[str, str]:
    if not AIORTC_AVAILABLE:
        raise RuntimeError("aiortc is not installed")

    existing_peer = _rtc_get_peer(call_id, user_id)
    if existing_peer is not None:
        existing_pc = existing_peer.pc
        existing_state = getattr(existing_pc, "connectionState", "unknown")
        existing_remote = getattr(existing_pc, "remoteDescription", None)
        existing_local = getattr(existing_pc, "localDescription", None)
        same_offer = (
            existing_peer.last_offer_sdp == sdp
            or (
                existing_remote is not None
                and existing_remote.type == sdp_type
                and existing_remote.sdp == sdp
            )
        )
        if (
            same_offer
            and existing_local is not None
            and existing_state in {"new", "connecting", "connected"}
        ):
            _call_debug(
                "rtc.connect_reuse",
                call_id=call_id,
                user_id=user_id,
                state=existing_state,
            )
            await _rtc_refresh_room_tracks(call_id)
            return {"type": existing_local.type, "sdp": existing_local.sdp}

        await _rtc_remove_peer(
            call_id,
            user_id,
            reason="reconnect",
            expected_pc=existing_pc,
        )

    config = RTCConfiguration(iceServers=_rtc_ice_servers())
    pc = RTCPeerConnection(configuration=config)
    peer = _RtcCallPeer(
        call_id=call_id,
        user_id=user_id,
        pc=pc,
    )

    with _rtc_rooms_lock:
        room = _rtc_rooms.get(call_id)
        if room is None:
            room = _RtcCallRoom(call_id=call_id)
            _rtc_rooms[call_id] = room
        room.peers[user_id] = peer

    @pc.on("connectionstatechange")
    async def _on_connectionstatechange() -> None:
        state = pc.connectionState
        _call_debug("rtc.pc_state", call_id=call_id, user_id=user_id, state=state)
        if state in {"failed", "closed"}:
            await _rtc_remove_peer(
                call_id,
                user_id,
                reason=f"pc_{state}",
                expected_pc=pc,
            )

    @pc.on("track")
    def _on_track(track: Any) -> None:
        relayed = _rtc_relay.subscribe(track) if _rtc_relay is not None else track
        if track.kind == "audio":
            peer.inbound_audio = relayed
        elif track.kind == "video":
            peer.inbound_video = relayed
        _call_debug("rtc.track_in", call_id=call_id, user_id=user_id, kind=track.kind)
        asyncio.create_task(_rtc_refresh_room_tracks(call_id))

        @track.on("ended")
        async def _on_track_ended() -> None:
            if track.kind == "audio":
                peer.inbound_audio = None
            elif track.kind == "video":
                peer.inbound_video = None
            _call_debug(
                "rtc.track_ended",
                call_id=call_id,
                user_id=user_id,
                kind=track.kind,
            )
            await _rtc_refresh_room_tracks(call_id)

    try:
        offer = RTCSessionDescription(sdp=sdp, type=sdp_type)
        await pc.setRemoteDescription(offer)
        peer.last_offer_sdp = sdp

        # Bind to negotiated offer m-lines first and force sendrecv in the
        # answer. Without this, aiortc can settle on recvonly while sender
        # tracks are still empty, and later replaceTrack will not start media.
        for transceiver in pc.getTransceivers():
            if transceiver.kind == "audio" and peer.audio_sender is None:
                try:
                    transceiver.direction = "sendrecv"
                except Exception:
                    pass
                peer.audio_sender = transceiver.sender
            elif transceiver.kind == "video" and peer.video_sender is None:
                try:
                    transceiver.direction = "sendrecv"
                except Exception:
                    pass
                peer.video_sender = transceiver.sender
        if peer.audio_sender is None:
            peer.audio_sender = pc.addTransceiver("audio", direction="sendrecv").sender
        if peer.video_sender is None:
            peer.video_sender = pc.addTransceiver("video", direction="sendrecv").sender

        answer = await pc.createAnswer()
        await pc.setLocalDescription(answer)

        for _ in range(60):
            if pc.iceGatheringState == "complete":
                break
            await asyncio.sleep(0.05)

        await _rtc_refresh_room_tracks(call_id)
        local = pc.localDescription
        if local is None:
            raise RuntimeError("failed to create local description")
        _call_debug("rtc.answer_ready", call_id=call_id, user_id=user_id)
        return {"type": local.type, "sdp": local.sdp}
    except Exception:
        await _rtc_remove_peer(call_id, user_id, reason="connect_failed")
        raise


async def _rtc_add_remote_candidate(
    *,
    call_id: int,
    user_id: int,
    candidate: str,
    sdp_mid: str | None,
    sdp_mline_index: int | None,
) -> None:
    if candidate_from_sdp is None:
        raise RuntimeError("aiortc candidate parser is unavailable")

    peer = _rtc_get_peer(call_id, user_id)
    if peer is None:
        raise LookupError("peer_not_found")
    state = getattr(peer.pc, "connectionState", "unknown")
    if state in {"closed", "failed"}:
        raise LookupError("peer_closed")

    # flutter_webrtc sends "candidate:<...>", while aiortc parser expects the SDP body.
    candidate_sdp = candidate[10:] if candidate.startswith("candidate:") else candidate
    ice = candidate_from_sdp(candidate_sdp)
    ice.sdpMid = sdp_mid
    ice.sdpMLineIndex = sdp_mline_index
    await peer.pc.addIceCandidate(ice)


def _ws_register_client(user_id: int, ws: Any) -> None:
    with _ws_clients_lock:
        bucket = _ws_clients.get(user_id)
        if bucket is None:
            bucket = set()
            _ws_clients[user_id] = bucket
        bucket.add(ws)


def _ws_unregister_client(user_id: int, ws: Any) -> None:
    with _ws_clients_lock:
        bucket = _ws_clients.get(user_id)
        if not bucket:
            return
        bucket.discard(ws)
        if not bucket:
            _ws_clients.pop(user_id, None)


def _ws_send_to_user(user_id: int, payload: dict[str, Any]) -> int:
    encoded = json.dumps(payload)
    with _ws_clients_lock:
        targets = list(_ws_clients.get(user_id, set()))
    if not targets:
        return 0

    delivered = 0
    dead: list[Any] = []
    for ws in targets:
        try:
            ws.send(encoded)
            delivered += 1
        except Exception:
            dead.append(ws)
    if dead:
        with _ws_clients_lock:
            bucket = _ws_clients.get(user_id)
            if bucket:
                for ws in dead:
                    bucket.discard(ws)
                if not bucket:
                    _ws_clients.pop(user_id, None)
    return delivered


def _ws_emit_call_signal(signal_payload: dict[str, Any]) -> None:
    recipient_id = _parse_user_id(signal_payload.get("recipient_id"), default=0)
    if recipient_id == 0:
        return
    sent_to = _ws_send_to_user(recipient_id, {"event": "signal", "signal": signal_payload})
    _call_debug(
        "ws.emit_signal",
        signal_id=signal_payload.get("id"),
        call_id=signal_payload.get("call_id"),
        recipient_id=recipient_id,
        sockets=sent_to,
    )


def _conversation_for_user(session, conversation_id: int, user_id: int) -> Conversation | None:
    conversation = session.query(Conversation).filter(Conversation.id == conversation_id).one_or_none()
    if conversation is None:
        return None
    participant_ids = {participant.user_id for participant in conversation.participants}
    if user_id not in participant_ids:
        return None
    return conversation


def _find_direct_conversation(session, user_a_id: int, user_b_id: int) -> Conversation | None:
    candidate_rows = (
        session.query(ConversationParticipant.conversation_id)
        .filter(ConversationParticipant.user_id == user_a_id)
        .all()
    )
    for (conversation_id,) in candidate_rows:
        participants = (
            session.query(ConversationParticipant)
            .filter(ConversationParticipant.conversation_id == conversation_id)
            .all()
        )
        participant_ids = {participant.user_id for participant in participants}
        if participant_ids == {user_a_id, user_b_id} and len(participants) == 2:
            return session.query(Conversation).filter(Conversation.id == conversation_id).one_or_none()
    return None


def _create_direct_conversation(
    session,
    user_a_id: int,
    user_b_id: int,
    pinned_for_a: bool = False,
    pinned_for_b: bool = False,
) -> Conversation:
    now = datetime.now(UTC)
    conversation = Conversation(created_at=now, updated_at=now)
    session.add(conversation)
    session.flush()

    session.add_all(
        [
            ConversationParticipant(
                conversation_id=conversation.id,
                user_id=user_a_id,
                pinned=pinned_for_a,
            ),
            ConversationParticipant(
                conversation_id=conversation.id,
                user_id=user_b_id,
                pinned=pinned_for_b,
            ),
        ]
    )
    session.flush()
    return conversation


def _ensure_schema() -> None:
    inspector = inspect(engine)
    if "users" not in inspector.get_table_names():
        return
    user_columns = {column["name"] for column in inspector.get_columns("users")}
    message_columns = {column["name"] for column in inspector.get_columns("messages")}
    with engine.begin() as connection:
        if "password_hash" not in user_columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN password_hash VARCHAR(255)"))
            connection.execute(text("UPDATE users SET password_hash = '' WHERE password_hash IS NULL"))
        if "last_seen_at" not in user_columns:
            last_seen_type = "DATETIME" if IS_SQLITE_DB else "TIMESTAMP WITH TIME ZONE"
            connection.execute(text(f"ALTER TABLE users ADD COLUMN last_seen_at {last_seen_type}"))
        if "image_base64" not in message_columns:
            connection.execute(text("ALTER TABLE messages ADD COLUMN image_base64 TEXT"))
        if "file_base64" not in message_columns:
            connection.execute(text("ALTER TABLE messages ADD COLUMN file_base64 TEXT"))
        if "file_name" not in message_columns:
            connection.execute(text("ALTER TABLE messages ADD COLUMN file_name VARCHAR(255)"))
        if "file_mime_type" not in message_columns:
            connection.execute(text("ALTER TABLE messages ADD COLUMN file_mime_type VARCHAR(255)"))
        if "file_size" not in message_columns:
            connection.execute(text("ALTER TABLE messages ADD COLUMN file_size INTEGER"))
        connection.execute(
            text(
                """
                UPDATE call_sessions
                SET
                    state = 'ended',
                    ended_at = COALESCE(ended_at, CURRENT_TIMESTAMP),
                    updated_at = COALESCE(updated_at, CURRENT_TIMESTAMP)
                WHERE state IN ('ringing', 'active')
                  AND id NOT IN (
                      SELECT MAX(id)
                      FROM call_sessions
                      WHERE state IN ('ringing', 'active')
                      GROUP BY conversation_id
                  )
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS ix_call_sessions_one_open_per_conversation
                ON call_sessions (conversation_id)
                WHERE state IN ('ringing', 'active')
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS ix_call_signals_fetch
                ON call_signals (call_id, recipient_id, id)
                """
            )
        )
        connection.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS ix_call_sessions_conversation_state
                ON call_sessions (conversation_id, state, id)
                """
            )
        )

    with SessionLocal() as session:
        legacy_users = (
            session.query(User)
            .filter(or_(User.password_hash.is_(None), User.password_hash == ""))
            .all()
        )
        if legacy_users:
            for user in legacy_users:
                user.password_hash = generate_password_hash("password123")
            session.commit()


def _remove_seed_users(usernames: set[str]) -> None:
    if not usernames:
        return

    with SessionLocal() as session:
        users = session.query(User).filter(User.username.in_(usernames)).all()
        if not users:
            return

        user_ids = [user.id for user in users]
        conversation_rows = (
            session.query(ConversationParticipant.conversation_id)
            .filter(ConversationParticipant.user_id.in_(user_ids))
            .all()
        )
        conversation_ids = [row[0] for row in conversation_rows]

        if conversation_ids:
            (
                session.query(Message)
                .filter(Message.conversation_id.in_(conversation_ids))
                .delete(synchronize_session=False)
            )
            (
                session.query(ConversationParticipant)
                .filter(ConversationParticipant.conversation_id.in_(conversation_ids))
                .delete(synchronize_session=False)
            )
            (
                session.query(Conversation)
                .filter(Conversation.id.in_(conversation_ids))
                .delete(synchronize_session=False)
            )

        (
            session.query(ConversationParticipant)
            .filter(ConversationParticipant.user_id.in_(user_ids))
            .delete(synchronize_session=False)
        )
        session.query(User).filter(User.id.in_(user_ids)).delete(synchronize_session=False)
        session.commit()


def _remove_generated_test_users() -> None:
    prefixes = ("u1_", "u2_", "s1_", "s2_", "codex_")
    with SessionLocal() as session:
        filters = [User.username.like(f"{prefix}%") for prefix in prefixes]
        rows = session.query(User.username).filter(or_(*filters)).all()
    usernames = {str(row[0]) for row in rows if row and row[0]}
    _remove_seed_users(usernames)


def _seed_database() -> None:
    return None


def _initialize_database() -> None:
    Base.metadata.create_all(bind=engine)
    _ensure_schema()
    _remove_seed_users({"alex", "marta", "iryna", "nick"})
    _remove_generated_test_users()
    _seed_database()


@app.after_request
def _cors(response):  # type: ignore[no-untyped-def]
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    response.headers["Access-Control-Allow-Methods"] = "GET,POST,DELETE,OPTIONS"
    return response


@app.route("/health", methods=["GET"])
def health() -> Any:
    db_kind = "sqlite" if IS_SQLITE_DB else "postgresql"
    db_value = DATABASE_PATH if IS_SQLITE_DB else db_kind
    return jsonify({"status": "ok", "db": db_value, "timestamp": _iso(datetime.now(UTC))})


@app.route("/api/auth/register", methods=["POST"])
def auth_register() -> Any:
    data = request.get_json(silent=True) or {}
    username = str(data.get("username", "")).strip().lower()
    display_name = str(data.get("display_name", "")).strip()
    password = str(data.get("password", "")).strip()

    if not username or not display_name or not password:
        return jsonify({"error": "username, display_name and password are required"}), 400
    if len(password) < 6:
        return jsonify({"error": "password must be at least 6 characters"}), 400

    with SessionLocal() as session:
        exists = session.query(User).filter(User.username == username).one_or_none()
        if exists is not None:
            return jsonify({"error": "username already exists"}), 409

        user = User(
            username=username,
            display_name=display_name,
            password_hash=generate_password_hash(password),
            online=True,
            last_seen_at=_utc_now(),
        )
        session.add(user)
        session.commit()
        session.refresh(user)

        token = _create_jwt(user)
        payload = {"token": token, "user": _public_user(user)}
    return jsonify(payload), 201


@app.route("/api/auth/login", methods=["POST"])
def auth_login() -> Any:
    data = request.get_json(silent=True) or {}
    username = str(data.get("username", "")).strip().lower()
    password = str(data.get("password", "")).strip()
    if not username or not password:
        return jsonify({"error": "username and password are required"}), 400

    with SessionLocal() as session:
        user = session.query(User).filter(User.username == username).one_or_none()
        if user is None or not check_password_hash(user.password_hash or "", password):
            return jsonify({"error": "invalid credentials"}), 401
        _set_user_online(user, True)
        _set_user_last_seen(user, _utc_now())
        session.commit()
        session.refresh(user)

        token = _create_jwt(user)
        payload = {"token": token, "user": _public_user(user)}
    return jsonify(payload)


@app.route("/api/auth/me", methods=["GET"])
def auth_me() -> Any:
    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401
        return jsonify({"user": _public_user(user)})


@app.route("/api/auth/profile", methods=["POST"])
def auth_update_profile() -> Any:
    data = request.get_json(silent=True) or {}
    username_raw = data.get("username")
    display_name_raw = data.get("display_name")
    password_raw = data.get("password")

    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401

        user_model = user
        user_any = cast(Any, user_model)
        changed = False

        if username_raw is not None:
            username = str(username_raw).strip().lower()
            if not username:
                return jsonify({"error": "username is required"}), 400
            if username != user_model.username:
                exists = (
                    session.query(User)
                    .filter(User.username == username, User.id != user_model.id)
                    .one_or_none()
                )
                if exists is not None:
                    return jsonify({"error": "username already exists"}), 409
                user_any.username = username
                changed = True

        if display_name_raw is not None:
            display_name = str(display_name_raw).strip()
            if not display_name:
                return jsonify({"error": "display_name is required"}), 400
            if display_name != user_model.display_name:
                user_any.display_name = display_name
                changed = True

        if password_raw is not None:
            password = str(password_raw).strip()
            if not password:
                return jsonify({"error": "password is required"}), 400
            if len(password) < 6:
                return jsonify({"error": "password must be at least 6 characters"}), 400
            user_any.password_hash = generate_password_hash(password)
            changed = True

        if not changed:
            return jsonify({"error": "no profile changes provided"}), 400

        _set_user_last_seen(user_model, _utc_now())
        session.commit()
        session.refresh(user_model)
        return jsonify({"user": _public_user(user_model)})


@app.route("/api/auth/logout", methods=["POST"])
def auth_logout() -> Any:
    with SessionLocal() as session:
        user = _user_from_token(session)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401
        _set_user_online(user, False)
        _set_user_last_seen(user, _utc_now())
        session.commit()
    return jsonify({"ok": True})


@app.route("/api/users", methods=["GET"])
def get_users() -> Any:
    with SessionLocal() as session:
        users = session.query(User).order_by(User.id.asc()).all()
        payload = [_public_user(user) for user in users]
    return jsonify(payload)


@app.route("/api/conversations", methods=["GET"])
def get_conversations() -> Any:
    with SessionLocal() as session:
        viewer = _resolve_request_user(session, default=1)
        if viewer is None:
            return jsonify({"error": "unauthorized or unknown user"}), 401
        viewer_id = viewer.id

        links = (
            session.query(ConversationParticipant)
            .filter(ConversationParticipant.user_id == viewer_id)
            .all()
        )
        conversations: list[dict[str, Any]] = []
        for link in links:
            conversation = (
                session.query(Conversation)
                .filter(Conversation.id == link.conversation_id)
                .one_or_none()
            )
            if conversation is None:
                continue
            conversations.append(_conversation_summary(session, conversation, viewer_id))

        conversations.sort(
            key=lambda item: (
                0 if item["pinned"] else 1,
                -datetime.fromisoformat(item["updated_at"].replace("Z", "+00:00")).timestamp(),
            )
        )
    return jsonify(conversations)


@app.route("/api/conversations/direct", methods=["POST"])
def create_or_get_direct_conversation() -> Any:
    data = request.get_json(silent=True) or {}

    with SessionLocal() as session:
        actor = _resolve_request_user(session, default=1)
        token_user = _user_from_token(session, touch=True)

        if token_user is not None:
            user_a_id = token_user.id
            user_b_id = _parse_user_id(data.get("partner_user_id"), default=0)
        else:
            user_a_id = _parse_user_id(data.get("user_a_id"), default=actor.id if actor else 0)
            user_b_id = _parse_user_id(
                data.get("user_b_id") or data.get("partner_user_id"),
                default=0,
            )

        if user_a_id == 0 or user_b_id == 0 or user_a_id == user_b_id:
            return jsonify({"error": "user ids must be valid and different"}), 400

        user_a = session.query(User).filter(User.id == user_a_id).one_or_none()
        user_b = session.query(User).filter(User.id == user_b_id).one_or_none()
        if user_a is None or user_b is None:
            return jsonify({"error": "One or both users not found"}), 404

        existing = _find_direct_conversation(session, user_a_id, user_b_id)
        created = False
        conversation = existing
        if conversation is None:
            conversation = _create_direct_conversation(session, user_a_id, user_b_id)
            session.commit()
            session.refresh(conversation)
            created = True

        payload = _conversation_summary(session, conversation, user_a_id)
    return jsonify({"conversation": payload}), 201 if created else 200


@app.route("/api/conversations/<conversation_id>/messages", methods=["GET"])
def get_messages(conversation_id: str) -> Any:
    try:
        conversation_int_id = int(conversation_id)
    except ValueError:
        return jsonify({"error": "conversation_id must be numeric"}), 400

    since_id = _parse_user_id(request.args.get("since_id"), default=0)
    if since_id < 0:
        since_id = 0

    requested_limit = _parse_user_id(request.args.get("limit"), default=0)
    if requested_limit <= 0:
        requested_limit = 80 if since_id <= 0 else 200
    limit = max(1, min(requested_limit, 400))

    with SessionLocal() as session:
        viewer = _resolve_request_user(session, default=1)
        if viewer is None:
            return jsonify({"error": "unauthorized or unknown user"}), 401
        viewer_id = viewer.id

        conversation = _conversation_for_user(session, conversation_int_id, viewer_id)
        if conversation is None:
            return jsonify({"error": "Conversation not found for this user"}), 404

        if since_id > 0:
            messages = (
                session.query(Message)
                .filter(
                    Message.conversation_id == conversation_int_id,
                    Message.id > since_id,
                )
                .order_by(Message.id.asc())
                .limit(limit)
                .all()
            )
            has_more = len(messages) >= limit
        else:
            # Initial page: return only the latest `limit` messages.
            latest_chunk = (
                session.query(Message)
                .filter(Message.conversation_id == conversation_int_id)
                .order_by(Message.id.desc())
                .limit(limit)
                .all()
            )
            messages = list(reversed(latest_chunk))
            has_more = (
                session.query(func.count(Message.id))
                .filter(Message.conversation_id == conversation_int_id)
                .scalar()
                or 0
            ) > len(messages)

        peer_last_read_id = 0
        for participant in conversation.participants:
            if participant.user_id != viewer_id:
                peer_last_read_id = participant.last_read_message_id or 0
                break
        payload = [
            _message_payload(message, viewer_id, peer_last_read_id=peer_last_read_id)
            for message in messages
        ]
        last_message_id = messages[-1].id if messages else since_id
    return jsonify(
        {
            "conversation_id": conversation_id,
            "messages": payload,
            "has_more": bool(has_more),
            "last_message_id": int(last_message_id),
        }
    )


@app.route("/api/conversations/<conversation_id>/messages", methods=["POST", "OPTIONS"])
def post_message(conversation_id: str) -> Any:
    if request.method == "OPTIONS":
        return ("", 204)

    data = request.get_json(silent=True) or {}
    text_value = str(data.get("text", "")).strip()
    try:
        image_base64_value = _normalize_message_image_base64(data.get("image_base64"))
        file_base64_value, file_name_value, file_mime_type_value, file_size_value = (
            _normalize_message_file_payload(
                data.get("file_base64"),
                data.get("file_name"),
                data.get("file_mime_type"),
                data.get("file_size"),
            )
        )
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    if not text_value and image_base64_value is None and file_base64_value is None:
        return jsonify({"error": "Either 'text', 'image_base64' or file payload is required"}), 400

    try:
        conversation_int_id = int(conversation_id)
    except ValueError:
        return jsonify({"error": "conversation_id must be numeric"}), 400

    with SessionLocal() as session:
        auth_user = _user_from_token(session, touch=True)
        if auth_user is not None:
            sender_id = auth_user.id
            viewer_id = auth_user.id
        else:
            sender_id = _parse_user_id(data.get("sender_id"), default=1)
            viewer_id = _parse_user_id(request.args.get("user_id"), default=sender_id)

        conversation = _conversation_for_user(session, conversation_int_id, sender_id)
        if conversation is None:
            return jsonify({"error": "Conversation not found for sender"}), 404

        sender_participant = (
            session.query(ConversationParticipant)
            .filter(
                ConversationParticipant.conversation_id == conversation_int_id,
                ConversationParticipant.user_id == sender_id,
            )
            .one_or_none()
        )
        if sender_participant is None:
            return jsonify({"error": "Sender is not a participant"}), 403

        message = Message(
            conversation_id=conversation_int_id,
            sender_id=sender_id,
            text=text_value,
            image_base64=image_base64_value,
            file_base64=file_base64_value,
            file_name=file_name_value,
            file_mime_type=file_mime_type_value,
            file_size=file_size_value,
            created_at=datetime.now(UTC),
        )
        session.add(message)
        session.flush()

        _set_conversation_updated_at(conversation, message.created_at)
        sender_participant.last_read_message_id = message.id
        session.commit()
        session.refresh(conversation)

        if _conversation_for_user(session, conversation_int_id, viewer_id) is None:
            viewer_id = sender_id

        peer_last_read_id = 0
        for participant in conversation.participants:
            if participant.user_id != viewer_id:
                peer_last_read_id = participant.last_read_message_id or 0
                break

        response = {
            "conversation": _conversation_summary(session, conversation, viewer_id),
            "messages": [
                _message_payload(
                    message,
                    viewer_id,
                    peer_last_read_id=peer_last_read_id,
                )
            ],
        }
    return jsonify(response), 201


@app.route(
    "/api/conversations/<conversation_id>/messages/<message_id>",
    methods=["DELETE", "OPTIONS"],
)
def delete_message(conversation_id: str, message_id: str) -> Any:
    if request.method == "OPTIONS":
        return ("", 204)

    try:
        conversation_int_id = int(conversation_id)
        message_int_id = int(message_id)
    except ValueError:
        return jsonify({"error": "conversation_id and message_id must be numeric"}), 400

    with SessionLocal() as session:
        viewer = _resolve_request_user(session, default=1)
        if viewer is None:
            return jsonify({"error": "unauthorized or unknown user"}), 401
        viewer_id = viewer.id

        conversation = _conversation_for_user(session, conversation_int_id, viewer_id)
        if conversation is None:
            return jsonify({"error": "Conversation not found for this user"}), 404

        message = (
            session.query(Message)
            .filter(
                Message.id == message_int_id,
                Message.conversation_id == conversation_int_id,
            )
            .one_or_none()
        )
        if message is None:
            return jsonify({"error": "Message not found"}), 404
        if message.sender_id != viewer_id:
            return jsonify({"error": "Only sender can delete this message"}), 403

        session.delete(message)
        session.flush()

        remaining_last = (
            session.query(Message)
            .filter(Message.conversation_id == conversation_int_id)
            .order_by(Message.id.desc())
            .first()
        )
        replacement_read_id = remaining_last.id if remaining_last is not None else None
        for participant in conversation.participants:
            if participant.last_read_message_id == message_int_id:
                participant.last_read_message_id = replacement_read_id

        _set_conversation_updated_at(conversation, datetime.now(UTC))
        session.commit()
        session.refresh(conversation)

        response = {
            "ok": True,
            "deleted_message_id": str(message_int_id),
            "conversation": _conversation_summary(session, conversation, viewer_id),
        }
    return jsonify(response)


@app.route("/api/conversations/<conversation_id>/read", methods=["POST"])
def mark_read(conversation_id: str) -> Any:
    try:
        conversation_int_id = int(conversation_id)
    except ValueError:
        return jsonify({"error": "conversation_id must be numeric"}), 400

    with SessionLocal() as session:
        viewer = _resolve_request_user(session, default=1)
        if viewer is None:
            return jsonify({"error": "unauthorized or unknown user"}), 401
        viewer_id = viewer.id

        conversation = _conversation_for_user(session, conversation_int_id, viewer_id)
        if conversation is None:
            return jsonify({"error": "Conversation not found for this user"}), 404

        participant = (
            session.query(ConversationParticipant)
            .filter(
                ConversationParticipant.conversation_id == conversation_int_id,
                ConversationParticipant.user_id == viewer_id,
            )
            .one_or_none()
        )
        if participant is None:
            return jsonify({"error": "Participant not found"}), 404

        latest_message = (
            session.query(Message)
            .filter(Message.conversation_id == conversation_int_id)
            .order_by(Message.id.desc())
            .first()
        )
        participant.last_read_message_id = latest_message.id if latest_message else None
        session.commit()
        session.refresh(conversation)
        payload = _conversation_summary(session, conversation, viewer_id)
    return jsonify({"conversation": payload})


@app.route("/api/calls/start", methods=["POST"])
def start_call() -> Any:
    data = request.get_json(silent=True) or {}
    conversation_id = _parse_user_id(data.get("conversation_id"), default=0)
    if conversation_id == 0:
        return jsonify({"error": "conversation_id is required"}), 400

    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401

        conversation = _conversation_for_user(session, conversation_id, user.id)
        if conversation is None:
            return jsonify({"error": "Conversation not found for this user"}), 404

        participant_ids = _call_participants_for_conversation(session, conversation_id)
        if len(participant_ids) != 2:
            return jsonify({"error": "Only direct chats are supported for calls"}), 400
        if user.id not in participant_ids:
            return jsonify({"error": "You are not a participant of this conversation"}), 403

        callee_id = participant_ids[0] if participant_ids[1] == user.id else participant_ids[1]
        open_calls = (
            session.query(CallSession)
            .filter(
                CallSession.conversation_id == conversation_id,
                CallSession.state.in_(["ringing", "active"]),
            )
            .order_by(CallSession.id.desc())
            .all()
        )
        now = _utc_now()
        for open_call in open_calls:
            if _is_call_stale(open_call, now):
                _mark_call_ended(open_call, now)
        if open_calls:
            session.commit()

        existing = (
            session.query(CallSession)
            .filter(
                CallSession.conversation_id == conversation_id,
                CallSession.state.in_(["ringing", "active"]),
            )
            .order_by(CallSession.id.desc())
            .first()
        )
        if existing is not None:
            _call_debug(
                "start.reuse_open_call",
                user_id=user.id,
                conversation_id=conversation_id,
                call_id=existing.id,
                state=existing.state,
            )
            return jsonify({"call": _call_payload(session, existing, user.id)})

        call = CallSession(
            conversation_id=conversation_id,
            caller_id=user.id,
            callee_id=callee_id,
            state="ringing",
            started_at=now,
            updated_at=now,
        )
        session.add(call)
        try:
            session.flush()
            ringing_signal = _push_call_signal(
                session,
                call_id=call.id,
                sender_id=user.id,
                recipient_id=callee_id,
                kind="ringing",
                payload={"call_id": str(call.id), "conversation_id": str(conversation_id)},
            )
            session.commit()
            session.refresh(call)
            _ws_emit_call_signal(_call_signal_payload(ringing_signal))
            _call_debug(
                "start.created",
                user_id=user.id,
                conversation_id=conversation_id,
                call_id=call.id,
                caller_id=call.caller_id,
                callee_id=call.callee_id,
            )
            payload = _call_payload(session, call, user.id)
            status_code = 201
        except IntegrityError:
            session.rollback()
            existing = (
                session.query(CallSession)
                .filter(
                    CallSession.conversation_id == conversation_id,
                    CallSession.state.in_(["ringing", "active"]),
                )
                .order_by(CallSession.id.desc())
                .first()
            )
            if existing is None:
                return jsonify({"error": "Failed to create call session"}), 409
            _call_debug(
                "start.integrity_reuse",
                user_id=user.id,
                conversation_id=conversation_id,
                call_id=existing.id,
                state=existing.state,
            )
            payload = _call_payload(session, existing, user.id)
            status_code = 200
    return jsonify({"call": payload}), status_code


@app.route("/api/calls/incoming", methods=["GET"])
def incoming_calls() -> Any:
    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401

        calls = (
            session.query(CallSession)
            .filter(
                CallSession.callee_id == user.id,
                CallSession.state == "ringing",
                CallSession.ended_at.is_(None),
            )
            .order_by(CallSession.id.desc())
            .all()
        )
        payload = [_call_payload(session, call, user.id) for call in calls]
    return jsonify({"calls": payload})


@app.route("/api/calls/<call_id>/accept", methods=["POST"])
def accept_call(call_id: str) -> Any:
    try:
        call_int_id = int(call_id)
    except ValueError:
        return jsonify({"error": "call_id must be numeric"}), 400

    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401

        call = _call_for_user(session, call_int_id, user.id)
        if call is None:
            return jsonify({"error": "Call not found for this user"}), 404
        if user.id != call.callee_id:
            return jsonify({"error": "Only callee can accept call"}), 403

        if call.state == "ringing":
            now = _utc_now()
            _set_call_state(call, "active")
            _set_call_answered_at(call, now)
            _set_call_updated_at(call, now)
            accepted_signal = _push_call_signal(
                session,
                call_id=call.id,
                sender_id=user.id,
                recipient_id=call.caller_id,
                kind="accept",
                payload={"call_id": str(call.id), "state": "active"},
            )
            session.commit()
            session.refresh(call)
            _ws_emit_call_signal(_call_signal_payload(accepted_signal))
            _call_debug(
                "call.accept",
                call_id=call.id,
                user_id=user.id,
                caller_id=call.caller_id,
                callee_id=call.callee_id,
            )

        payload = _call_payload(session, call, user.id)
    return jsonify({"call": payload})


@app.route("/api/calls/<call_id>/reject", methods=["POST"])
def reject_call(call_id: str) -> Any:
    try:
        call_int_id = int(call_id)
    except ValueError:
        return jsonify({"error": "call_id must be numeric"}), 400

    should_close_rtc_room = False
    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401

        call = _call_for_user(session, call_int_id, user.id)
        if call is None:
            return jsonify({"error": "Call not found for this user"}), 404

        if call.state not in {"rejected", "ended"}:
            now = _utc_now()
            _set_call_state(call, "rejected")
            _set_call_ended_at(call, now)
            _set_call_updated_at(call, now)
            should_close_rtc_room = True
            other_id = _call_other_user_id(call, user.id)
            rejected_signal: CallSignal | None = None
            if other_id is not None:
                rejected_signal = _push_call_signal(
                    session,
                    call_id=call.id,
                    sender_id=user.id,
                    recipient_id=other_id,
                    kind="reject",
                    payload={"call_id": str(call.id)},
                )
            session.commit()
            session.refresh(call)
            if rejected_signal is not None:
                _ws_emit_call_signal(_call_signal_payload(rejected_signal))

        payload = _call_payload(session, call, user.id)
    if should_close_rtc_room and AIORTC_AVAILABLE:
        try:
            _run_on_rtc_loop(
                _rtc_close_call_room(call_int_id, reason="call_rejected"),
                timeout=8.0,
            )
        except Exception:
            pass
    return jsonify({"call": payload})


@app.route("/api/calls/<call_id>/end", methods=["POST"])
def end_call(call_id: str) -> Any:
    try:
        call_int_id = int(call_id)
    except ValueError:
        return jsonify({"error": "call_id must be numeric"}), 400

    should_close_rtc_room = False
    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401

        call = _call_for_user(session, call_int_id, user.id)
        if call is None:
            return jsonify({"error": "Call not found for this user"}), 404

        if call.state not in {"rejected", "ended"}:
            now = _utc_now()
            _set_call_state(call, "ended")
            _set_call_ended_at(call, now)
            _set_call_updated_at(call, now)
            should_close_rtc_room = True
            other_id = _call_other_user_id(call, user.id)
            ended_signal: CallSignal | None = None
            if other_id is not None:
                ended_signal = _push_call_signal(
                    session,
                    call_id=call.id,
                    sender_id=user.id,
                    recipient_id=other_id,
                    kind="end",
                    payload={"call_id": str(call.id)},
                )
            session.commit()
            session.refresh(call)
            if ended_signal is not None:
                _ws_emit_call_signal(_call_signal_payload(ended_signal))

        payload = _call_payload(session, call, user.id)
    if should_close_rtc_room and AIORTC_AVAILABLE:
        try:
            _run_on_rtc_loop(
                _rtc_close_call_room(call_int_id, reason="call_ended"),
                timeout=8.0,
            )
        except Exception:
            pass
    return jsonify({"call": payload})


@app.route("/api/calls/<call_id>/signal", methods=["POST"])
def send_call_signal(call_id: str) -> Any:
    try:
        call_int_id = int(call_id)
    except ValueError:
        return jsonify({"error": "call_id must be numeric"}), 400

    data = request.get_json(silent=True) or {}
    kind = str(data.get("kind", "")).strip().lower()
    payload_obj = data.get("payload")
    if kind not in {"offer", "answer", "ice"}:
        return jsonify({"error": "Unsupported signal kind"}), 400
    if payload_obj is not None and not isinstance(payload_obj, dict):
        return jsonify({"error": "payload must be object"}), 400

    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401

        call = _call_for_user(session, call_int_id, user.id)
        if call is None:
            return jsonify({"error": "Call not found for this user"}), 404
        if call.state in {"rejected", "ended"}:
            return jsonify({"error": "Call is no longer active"}), 409

        recipient_id = _call_other_user_id(call, user.id)
        if recipient_id is None:
            return jsonify({"error": "Cannot resolve recipient"}), 403

        _set_call_updated_at(call, _utc_now())
        payload_size = len(json.dumps(payload_obj)) if isinstance(payload_obj, dict) else 0
        signal = _push_call_signal(
            session,
            call_id=call.id,
            sender_id=user.id,
            recipient_id=recipient_id,
            kind=kind,
            payload=payload_obj if isinstance(payload_obj, dict) else None,
        )
        try:
            session.commit()
        except OperationalError:
            session.rollback()
            _call_debug(
                "signal.send_busy",
                call_id=call.id,
                kind=kind,
                sender_id=user.id,
                recipient_id=recipient_id,
            )
            return jsonify({"error": "temporary signaling storage busy"}), 503
        _call_debug(
            "signal.send",
            call_id=call.id,
            signal_id=signal.id,
            kind=kind,
            sender_id=user.id,
            recipient_id=recipient_id,
            payload_size=payload_size,
        )
        payload = _call_signal_payload(signal)
        _ws_emit_call_signal(payload)
    return jsonify({"signal": payload}), 201


@app.route("/api/calls/<call_id>/signals", methods=["GET"])
def get_call_signals(call_id: str) -> Any:
    try:
        call_int_id = int(call_id)
    except ValueError:
        return jsonify({"error": "call_id must be numeric"}), 400

    since_id = _parse_user_id(request.args.get("since_id"), default=0)
    if since_id < 0:
        since_id = 0

    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401

        call = _call_for_user(session, call_int_id, user.id)
        if call is None:
            return jsonify({"error": "Call not found for this user"}), 404

        signals = (
            session.query(CallSignal)
            .filter(
                CallSignal.call_id == call_int_id,
                CallSignal.recipient_id == user.id,
                CallSignal.id > since_id,
            )
            .order_by(CallSignal.id.asc())
            .all()
        )
        payload = [_call_signal_payload(signal) for signal in signals]
        last_signal_id = payload[-1]["id"] if payload else since_id
        call_payload = _call_payload(session, call, user.id)
        _call_debug(
            "signals.fetch",
            call_id=call.id,
            user_id=user.id,
            since_id=since_id,
            fetched=len(payload),
            last_signal_id=last_signal_id,
            state=call.state,
        )
    return jsonify(
        {
            "call": call_payload,
            "signals": payload,
            "last_signal_id": last_signal_id,
        }
    )


@app.route("/api/calls/<call_id>/rtc/connect", methods=["POST"])
def rtc_connect(call_id: str) -> Any:
    if not AIORTC_AVAILABLE:
        return jsonify({"error": "aiortc is not installed on server"}), 503

    try:
        call_int_id = int(call_id)
    except ValueError:
        return jsonify({"error": "call_id must be numeric"}), 400

    data = request.get_json(silent=True) or {}
    sdp = str(data.get("sdp", "")).strip()
    sdp_type = str(data.get("type", "offer")).strip().lower()
    if not sdp:
        return jsonify({"error": "sdp is required"}), 400
    if sdp_type != "offer":
        return jsonify({"error": "only offer is supported"}), 400

    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401
        call = _call_for_user(session, call_int_id, user.id)
        if call is None:
            return jsonify({"error": "Call not found for this user"}), 404
        if call.state in {"rejected", "ended"}:
            return jsonify({"error": "Call is no longer active"}), 409
        _set_call_updated_at(call, _utc_now())
        session.commit()
        session.refresh(call)
        call_payload = _call_payload(session, call, user.id)

    try:
        answer = _run_on_rtc_loop(
            _rtc_connect_offer(
                call_id=call_int_id,
                user_id=user.id,
                sdp=sdp,
                sdp_type=sdp_type,
            ),
            timeout=25.0,
        )
    except TimeoutError:
        return jsonify({"error": "aiortc connect timeout"}), 504
    except Exception as exc:
        _call_debug(
            "rtc.connect_error",
            call_id=call_int_id,
            error=str(exc),
        )
        return jsonify({"error": "failed to establish aiortc connection"}), 500

    return jsonify({"call": call_payload, "answer": answer})


@app.route("/api/calls/<call_id>/rtc/candidate", methods=["POST"])
def rtc_add_candidate(call_id: str) -> Any:
    if not AIORTC_AVAILABLE:
        return jsonify({"error": "aiortc is not installed on server"}), 503

    try:
        call_int_id = int(call_id)
    except ValueError:
        return jsonify({"error": "call_id must be numeric"}), 400

    data = request.get_json(silent=True) or {}
    candidate = str(data.get("candidate", "")).strip()
    sdp_mid = data.get("sdpMid")
    sdp_mline_index = data.get("sdpMLineIndex")
    if not candidate:
        return jsonify({"error": "candidate is required"}), 400

    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401
        call = _call_for_user(session, call_int_id, user.id)
        if call is None:
            return jsonify({"error": "Call not found for this user"}), 404
        if call.state in {"rejected", "ended"}:
            return jsonify({"error": "Call is no longer active"}), 409
        _set_call_updated_at(call, _utc_now())
        session.commit()

    _call_debug(
        "rtc.candidate_in",
        call_id=call_int_id,
        user_id=user.id,
        sdp_mid=str(sdp_mid) if sdp_mid is not None else None,
        sdp_mline_index=sdp_mline_index,
        candidate_len=len(candidate),
    )

    try:
        _run_on_rtc_loop(
            _rtc_add_remote_candidate(
                call_id=call_int_id,
                user_id=user.id,
                candidate=candidate,
                sdp_mid=str(sdp_mid) if sdp_mid is not None else None,
                sdp_mline_index=int(sdp_mline_index)
                if sdp_mline_index is not None
                else None,
            ),
            timeout=10.0,
        )
    except LookupError as exc:
        _call_debug(
            "rtc.candidate_ignored",
            call_id=call_int_id,
            user_id=user.id,
            reason=str(exc),
        )
        return jsonify({"ok": True, "accepted": False, "reason": str(exc)}), 202
    except Exception as exc:
        _call_debug(
            "rtc.candidate_error",
            call_id=call_int_id,
            error=str(exc),
        )
        lowered = str(exc).lower()
        if "closed" in lowered or "invalidstate" in lowered:
            return jsonify({"ok": True, "accepted": False, "reason": "transport_closed"}), 202
        return jsonify({"error": "failed to add candidate"}), 500
    _call_debug("rtc.candidate_added", call_id=call_int_id, user_id=user.id)
    return jsonify({"ok": True}), 202


@app.route("/api/calls/<call_id>/rtc/disconnect", methods=["POST"])
def rtc_disconnect(call_id: str) -> Any:
    if not AIORTC_AVAILABLE:
        return jsonify({"error": "aiortc is not installed on server"}), 503

    try:
        call_int_id = int(call_id)
    except ValueError:
        return jsonify({"error": "call_id must be numeric"}), 400

    with SessionLocal() as session:
        user = _user_from_token(session, touch=True)
        if user is None:
            return jsonify({"error": "unauthorized"}), 401
        call = _call_for_user(session, call_int_id, user.id)
        if call is None:
            return jsonify({"error": "Call not found for this user"}), 404
    try:
        _run_on_rtc_loop(
            _rtc_remove_peer(call_int_id, user.id, reason="client_disconnect"),
            timeout=8.0,
        )
    except Exception:
        pass
    return jsonify({"ok": True})


@sock.route("/ws/calls")
def ws_calls(ws) -> None:  # type: ignore[no-untyped-def]
    token = request.args.get("token", "").strip()
    ws_user_id = _parse_user_id(request.args.get("user_id"), default=0)

    with SessionLocal() as session:
        user = _user_from_raw_token(session, token, touch=True)
        if user is None and ws_user_id > 0:
            user = session.query(User).filter(User.id == ws_user_id).one_or_none()
            if user is not None:
                _touch_user_presence(session, user)
        if user is None:
            ws.send(json.dumps({"event": "error", "error": "unauthorized"}))
            try:
                ws.close()
            except Exception:
                pass
            return
        user_id = user.id

    _ws_register_client(user_id, ws)
    _call_debug("ws.connected", user_id=user_id)
    try:
        ws.send(json.dumps({"event": "ready", "user_id": user_id}))
        while True:
            raw = ws.receive()
            if raw is None:
                break
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                ws.send(json.dumps({"event": "error", "error": "invalid_json"}))
                continue
            if not isinstance(data, dict):
                ws.send(json.dumps({"event": "error", "error": "invalid_payload"}))
                continue

            action = str(data.get("action", "")).strip().lower()
            if action == "ping":
                ws.send(json.dumps({"event": "pong"}))
                continue
            if action != "signal":
                ws.send(json.dumps({"event": "error", "error": "unsupported_action"}))
                continue

            call_int_id = _parse_user_id(data.get("call_id"), default=0)
            kind = str(data.get("kind", "")).strip().lower()
            payload_obj = data.get("payload")
            tx_id = str(data.get("tx_id", "")).strip()

            if call_int_id == 0 or kind not in {"offer", "answer", "ice"}:
                ws.send(
                    json.dumps(
                        {
                            "event": "error",
                            "error": "invalid_signal",
                            "tx_id": tx_id,
                        }
                    )
                )
                continue
            if payload_obj is not None and not isinstance(payload_obj, dict):
                ws.send(
                    json.dumps(
                        {
                            "event": "error",
                            "error": "invalid_payload",
                            "tx_id": tx_id,
                        }
                    )
                )
                continue

            with SessionLocal() as session:
                sender = session.query(User).filter(User.id == user_id).one_or_none()
                if sender is None:
                    ws.send(json.dumps({"event": "error", "error": "unauthorized", "tx_id": tx_id}))
                    break
                call = _call_for_user(session, call_int_id, user_id)
                if call is None:
                    ws.send(json.dumps({"event": "error", "error": "call_not_found", "tx_id": tx_id}))
                    continue
                if call.state in {"rejected", "ended"}:
                    ws.send(json.dumps({"event": "error", "error": "call_closed", "tx_id": tx_id}))
                    continue
                recipient_id = _call_other_user_id(call, user_id)
                if recipient_id is None:
                    ws.send(
                        json.dumps(
                            {
                                "event": "error",
                                "error": "cannot_resolve_recipient",
                                "tx_id": tx_id,
                            }
                        )
                    )
                    continue

                _set_call_updated_at(call, _utc_now())
                signal = _push_call_signal(
                    session,
                    call_id=call.id,
                    sender_id=user_id,
                    recipient_id=recipient_id,
                    kind=kind,
                    payload=payload_obj if isinstance(payload_obj, dict) else None,
                )
                try:
                    session.commit()
                except OperationalError:
                    session.rollback()
                    ws.send(
                        json.dumps(
                            {
                                "event": "error",
                                "error": "temporary_signaling_storage_busy",
                                "tx_id": tx_id,
                            }
                        )
                    )
                    continue

                signal_payload = _call_signal_payload(signal)

            ws.send(
                json.dumps(
                    {
                        "event": "ack",
                        "tx_id": tx_id,
                        "signal_id": signal_payload.get("id"),
                    }
                )
            )
            _ws_emit_call_signal(signal_payload)
            _call_debug(
                "ws.signal_send",
                user_id=user_id,
                call_id=call_int_id,
                kind=kind,
                signal_id=signal_payload.get("id"),
            )
    finally:
        _ws_unregister_client(user_id, ws)
        _call_debug("ws.disconnected", user_id=user_id)


_initialize_database()


if __name__ == "__main__":
    debug_mode = os.getenv("TH4DER_DEBUG", "0") == "1"
    host = os.getenv("TH4DER_HOST", "0.0.0.0")
    port = int(os.getenv("TH4DER_PORT", os.getenv("PORT", "8000")))
    app.run(host=host, port=port, debug=debug_mode, use_reloader=debug_mode)
