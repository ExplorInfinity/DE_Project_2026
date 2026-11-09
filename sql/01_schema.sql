CREATE SCHEMA whatsapp;
SET search_path TO whatsapp;

CREATE TYPE user_status AS ENUM ('ACTIVE', 'BANNED', 'DELETED');
CREATE TYPE device_type AS ENUM ('ANDROID', 'DESKTOP', 'WEB', 'IOS');
CREATE TYPE chat_type AS ENUM ('DIRECT', 'GROUP');
CREATE TYPE member_role AS ENUM ('MEMBER', 'ADMIN');
CREATE TYPE media_type AS ENUM ('IMAGE', 'AUDIO', 'DOCUMENT', 'VIDEO');
CREATE TYPE mime_type AS ENUM ('image/jpeg', 'audio/ogg', 'application/pdf', 'video/mp4');
CREATE TYPE call_type AS ENUM ('VOICE', 'VIDEO');
CREATE TYPE call_status AS ENUM ('COMPLETED', 'FAILED', 'MISSED', 'REJECTED');
CREATE TYPE message_type AS ENUM ('AUDIO', 'DOCUMENT', 'IMAGE', 'LOCATION', 'TEXT', 'VIDEO');

CREATE TABLE users (
    user_id         INTEGER PRIMARY KEY,
    phone_e164      VARCHAR(13) NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    about           TEXT,
    is_business     BOOLEAN NOT NULL DEFAULT FALSE,
    joined_on       DATE NOT NULL,
    last_seen_at    TIMESTAMPTZ,
    status          user_status NOT NULL DEFAULT 'ACTIVE',

    CONSTRAINT chk_phone
        CHECK (phone_e164 ~ '^\+91[1-9][0-9]{9}$')
);

CREATE TABLE devices (
    device_id       INTEGER PRIMARY KEY,
    user_id         INTEGER NOT NULL,
    device_type     device_type NOT NULL,
    app_version     TEXT NOT NULL,
    registered_at   TIMESTAMPTZ NOT NULL,
    last_active_at  TIMESTAMPTZ NOT NULL,

    CONSTRAINT chk_app_version
        CHECK (app_version ~ '^[0-9]+(\.[0-9]+)+$'),

    CONSTRAINT chk_device_times
        CHECK (last_active_at >= registered_at),

    CONSTRAINT fk_devices
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT
);

CREATE TABLE chats (
    chat_id     INTEGER PRIMARY KEY,
    chat_type   chat_type NOT NULL,
    group_name  TEXT,
    created_by  INTEGER NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL,

    CONSTRAINT chk_group_name
        CHECK (
            (chat_type = 'DIRECT' AND group_name IS NULL) OR
            (chat_type = 'GROUP' AND group_name IS NOT NULL)
        ),

    CONSTRAINT fk_chat_user
        FOREIGN KEY (created_by)
        REFERENCES users(user_id)
        ON DELETE RESTRICT
);

CREATE TABLE chat_members (
    chat_id     INTEGER NOT NULL,
    user_id     INTEGER NOT NULL,
    role        member_role NOT NULL,
    joined_at   TIMESTAMPTZ NOT NULL,
    left_at     TIMESTAMPTZ,
    is_muted    BOOLEAN NOT NULL DEFAULT FALSE,

    PRIMARY KEY (chat_id, user_id),

    CONSTRAINT chk_left_at
        CHECK (left_at IS NULL OR left_at >= joined_at),

    CONSTRAINT fk_chat_member
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_chats
        FOREIGN KEY (chat_id)
        REFERENCES chats(chat_id)
        ON DELETE CASCADE
);

CREATE TABLE media (
    media_id        INTEGER PRIMARY KEY,
    uploader_id     INTEGER NOT NULL,
    media_type      media_type NOT NULL,
    mime_type       mime_type NOT NULL,
    size_bytes      BIGINT NOT NULL,
    sha256          CHAR(64) NOT NULL,
    uploaded_at     TIMESTAMPTZ NOT NULL,

    CONSTRAINT chk_size
        CHECK (size_bytes > 0),

    CONSTRAINT chk_sha256
        CHECK (sha256 ~ '^[a-fA-F0-9]{64}$'),

    CONSTRAINT chk_media_map
        CHECK (
            (media_type = 'IMAGE' AND mime_type = 'image/jpeg') OR
            (media_type = 'AUDIO' AND mime_type = 'audio/ogg') OR
            (media_type = 'DOCUMENT' AND mime_type = 'application/pdf') OR
            (media_type = 'VIDEO' AND mime_type = 'video/mp4')
        ),

    CONSTRAINT fk_media_user
        FOREIGN KEY (uploader_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT
);

CREATE TABLE blocked_users(
    blocker_id  INTEGER NOT NULL,
    blocked_id  INTEGER NOT NULL,
    blocked_at  TIMESTAMPTZ NOT NULL, 

    PRIMARY KEY (blocker_id, blocked_id),

    CONSTRAINT check_no_self_block
        CHECK (blocked_id <> blocker_id),

    CONSTRAINT fk_blocker
        FOREIGN KEY (blocker_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT, 

    CONSTRAINT fk_blocked
        FOREIGN KEY (blocked_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT
);

CREATE TABLE calls(
    call_id         INTEGER PRIMARY KEY,
    chat_id         INTEGER NOT NULL,
    caller_id       INTEGER NOT NULL,
    call_type       call_type NOT NULL,
    started_at      TIMESTAMPTZ NOT NULL,
    answered_at     TIMESTAMPTZ,
    ended_at        TIMESTAMPTZ,
    status          call_status NOT NULL,

    CONSTRAINT chk_call_timestamps
        CHECK(
            (answered_at is NULL OR answered_at >= started_at) AND
            (ended_at is NULL OR ended_at >= started_at) AND
            (answered_at IS NULL OR ended_at IS NULL OR ended_at >= answered_at)
        ),
    
    CONSTRAINT chk_call_status
        CHECK (
            (status = 'COMPLETED' AND answered_at IS NOT NULL AND ended_at IS NOT NULL) OR
            (status = 'FAILED' AND answered_at IS NULL AND ended_at IS NULL) OR
            (status IN ('MISSED', 'REJECTED') AND answered_at IS NULL AND ended_at IS NOT NULL)
        ),

    CONSTRAINT fk_calls_chat
        FOREIGN KEY (chat_id)
        REFERENCES chats(chat_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_calls_caller
        FOREIGN KEY (caller_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT
);

CREATE TABLE messages (
    message_id           INTEGER PRIMARY KEY,
    chat_id              INTEGER NOT NULL,
    sender_id            INTEGER NOT NULL,
    sent_at              TIMESTAMPTZ NOT NULL,
    message_type         message_type NOT NULL,
    body                 TEXT,
    media_id             INTEGER,
    reply_to_message_id  INTEGER,
    is_forwarded         BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted           BOOLEAN NOT NULL DEFAULT FALSE,
    edited_at            TIMESTAMPTZ,

    CONSTRAINT chk_edited_at
        CHECK (edited_at IS NULL OR edited_at >= sent_at),

    CONSTRAINT fk_messages_chat
        FOREIGN KEY (chat_id)
        REFERENCES chats(chat_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_messages_sender
        FOREIGN KEY (sender_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_messages_media
        FOREIGN KEY (media_id)
        REFERENCES media(media_id)
        ON DELETE SET NULL,

    CONSTRAINT fk_messages_reply
        FOREIGN KEY (reply_to_message_id)
        REFERENCES messages(message_id)
        ON DELETE SET NULL
);

CREATE TABLE message_receipts (
    message_id    INTEGER NOT NULL,
    user_id       INTEGER NOT NULL,
    delivered_at  TIMESTAMPTZ,
    read_at       TIMESTAMPTZ,

    PRIMARY KEY (message_id, user_id),

    CONSTRAINT chk_receipt_timestamps
        CHECK (
            (delivered_at IS NOT NULL OR read_at IS NULL) AND
            (read_at IS NULL OR read_at >= delivered_at)
        ),

    CONSTRAINT fk_receipts_message
        FOREIGN KEY (message_id)
        REFERENCES messages(message_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_receipts_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT
);
