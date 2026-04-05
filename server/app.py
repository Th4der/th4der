from __future__ import annotations

import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import jwt
from flask import Flask, jsonify, request
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
    func,
    inspect,
    or_,
    text,
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship, sessionmaker
from werkzeug.security import check_password_hash, generate_password_hash

BASE_DIR = Path(__file__).resolve().parent
DATABASE_PATH = (BASE_DIR / "th4der.db").as_posix()
DATABASE_URL = f"sqlite:///{DATABASE_PATH}"

JWT_SECRET = os.getenv("TH4DER_JWT_SECRET", "th4der-dev-secret")
JWT_ALGORITHM = "HS256"
JWT_EXPIRES_HOURS = int(os.getenv("TH4DER_JWT_EXPIRES_HOURS", "72"))
ONLINE_WINDOW_SECONDS = int(os.getenv("TH4DER_ONLINE_WINDOW_SECONDS", "20"))

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},
)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)

app = Flask(__name__)
Base = declarative_base()


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
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )

    conversation = relationship("Conversation", back_populates="messages")
    sender = relationship("User", back_populates="sent_messages")


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

    last_message = conversation.messages[-1] if conversation.messages else None
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

    return {
        "id": str(conversation.id),
        "name": other_user.display_name,
        "handle": f"@{other_user.username}",
        "online": _is_user_online(other_user),
        "pinned": bool(viewer_participant.pinned),
        "unread_count": int(unread_count),
        "last_message": last_message.text if last_message else "",
        "updated_at": _iso(conversation.updated_at),
    }


def _message_payload(message: Message, viewer_id: int) -> dict[str, Any]:
    return {
        "id": str(message.id),
        "conversation_id": str(message.conversation_id),
        "sender": "me" if message.sender_id == viewer_id else "contact",
        "sender_id": message.sender_id,
        "text": message.text,
        "created_at": _iso(message.created_at),
    }


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
    with engine.begin() as connection:
        if "password_hash" not in user_columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN password_hash VARCHAR(255)"))
            connection.execute(text("UPDATE users SET password_hash = '' WHERE password_hash IS NULL"))
        if "last_seen_at" not in user_columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN last_seen_at DATETIME"))

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


def _seed_database() -> None:
    return None


def _initialize_database() -> None:
    Base.metadata.create_all(bind=engine)
    _ensure_schema()
    _remove_seed_users({"alex", "marta", "iryna", "nick"})
    _seed_database()


@app.after_request
def _cors(response):  # type: ignore[no-untyped-def]
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    response.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
    return response


@app.route("/health", methods=["GET"])
def health() -> Any:
    return jsonify({"status": "ok", "db": DATABASE_PATH, "timestamp": _iso(datetime.now(UTC))})


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

    with SessionLocal() as session:
        viewer = _resolve_request_user(session, default=1)
        if viewer is None:
            return jsonify({"error": "unauthorized or unknown user"}), 401
        viewer_id = viewer.id

        conversation = _conversation_for_user(session, conversation_int_id, viewer_id)
        if conversation is None:
            return jsonify({"error": "Conversation not found for this user"}), 404

        messages = (
            session.query(Message)
            .filter(Message.conversation_id == conversation_int_id)
            .order_by(Message.id.asc())
            .all()
        )
        payload = [_message_payload(message, viewer_id) for message in messages]
    return jsonify({"conversation_id": conversation_id, "messages": payload})


@app.route("/api/conversations/<conversation_id>/messages", methods=["POST", "OPTIONS"])
def post_message(conversation_id: str) -> Any:
    if request.method == "OPTIONS":
        return ("", 204)

    data = request.get_json(silent=True) or {}
    text_value = str(data.get("text", "")).strip()
    if not text_value:
        return jsonify({"error": "Field 'text' is required"}), 400

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

        response = {
            "conversation": _conversation_summary(session, conversation, viewer_id),
            "messages": [_message_payload(message, viewer_id)],
        }
    return jsonify(response), 201


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


_initialize_database()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
