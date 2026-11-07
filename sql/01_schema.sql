CREATE TYPE status AS ENUM ('ACTIVE', 'BANNED', 'DELETED');
CREATE TYPE device_type AS ENUM ('ANDROID', 'DESKTOP', 'WEB', 'IOS');
CREATE TYPE chat_type AS ENUM ('DIRECT', 'GROUP');
CREATE TYPE role AS ENUM ('MEMBER', 'ADMIN');
CREATE TYPE media_type AS ENUM ('IMAGE', 'AUDIO', 'DOCUMENT', 'VIDEO');
CREATE TYPE mime_type AS ENUM ('image/jpeg', 'audio/ogg', 'application/pdf', 'video/mp4');

CREATE TABLE Users (
    user_id             INTEGER PRIMARY KEY,
    phone_e164          VARCHAR(13) NOT NULL UNIQUE,
    display_name        VARCHAR(50) NOT NULL,
    about               TEXT,
    is_business         BOOLEAN NOT NULL,
    joined_on           DATE NOT NULL,
    last_seen_at        TIMESTAMPTZ,
    status              status NOT NULL,

    CONSTRAINT chk_phone
        CHECK (phone_e164 ~ '^\+91[1-9][0-9]{9}$')
);

CREATE TABLE Devices (
    device_id       INTEGER PRIMARY KEY,
    user_id         INTEGER,
    device_type     device_type NOT NULL,
    app_version     VARCHAR(7) NOT NULL,
    registered_at   TIMESTAMPTZ NOT NULL,
    last_active_at  TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_devices
        FOREIGN KEY (user_id)
        REFERENCES Users(user_id)
        ON DELETE SET NULL
);

CREATE TABLE Chats (
    chat_id     INTEGER PRIMARY KEY,
    chat_type   chat_type NOT NULL,
    group_name  VARCHAR(50),
    created_by  INTEGER,
    created_at  TIMESTAMPTZ NOT NULL,

    CONSTRAINT chk_group_name
        CHECK ((chat_type = 'DIRECT' AND group_name IS NULL) OR
              (chat_type = 'GROUP' AND group_name IS NOT NULL)),
    CONSTRAINT fk_chat_user
        FOREIGN KEY (created_by)
        REFERENCES Users(user_id)
        ON DELETE SET NULL
);

CREATE TABLE Chat_members (
    chat_id     INTEGER NOT NULL,
    user_id     INTEGER NOT NULL,
    role        role NOT NULL,
    joined_at   TIMESTAMPTZ NOT NULL,
    left_at     TIMESTAMPTZ,
    is_muted    BOOLEAN NOT NULL,

    PRIMARY KEY (chat_id, user_id),

    CONSTRAINT chk_left_at
        CHECK (left_at IS NULL OR left_at >= joined_at),
    CONSTRAINT fk_chat_member
        FOREIGN KEY (user_id)
        REFERENCES Users(user_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_chats
        FOREIGN KEY (chat_id)
        REFERENCES Chats(chat_id)
        ON DELETE CASCADE
);

CREATE TABLE Media (
    media_id        INTEGER PRIMARY KEY,
    uploader_id     INTEGER,
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
        CHECK ((media_type = 'IMAGE' AND mime_type = 'image/jpeg') OR
               (media_type = 'AUDIO' AND mime_type = 'audio/ogg') OR
               (media_type = 'DOCUMENT' AND mime_type = 'application/pdf') OR
               (media_type = 'VIDEO' AND mime_type = 'video/mp4')),
    CONSTRAINT fk_media_user
        FOREIGN KEY (uploader_id)
        REFERENCES Users(user_id)
        ON DELETE SET NULL
);

CREATE TYPE call_type AS ENUM ('VOICE', 'VIDEO');
CREATE TYPE call_status AS ENUM ('COMPLETED', 'FAILED', 'MISSED', 'REJECTED');
CREATE TYPE message_type AS ENUM ('AUDIO', 'DOCUMENT', 'IMAGE', 'LOCATION', 'TEXT', 'VIDEO');


CREATE TABLE Blocked_users(
    blocker_id      INTEGER PRIMARY KEY NOT NULL,
    blocked_id,     INTEGER PRIMARY KEY NOT NULL,
    blocked_at      TIMESTAMPTZ NOT NULL

    CONSTRAINT check_no_self_block
        CHECK (blocked_id <> blocker_id),
    CONSTRAINT fk_blocker
        FOREIGN KEY (blocker_id)
        REFERENCES Users(user_id)
        ON DELETE CASCADE
    CONSTRAINT fk_blocked
        FOREIGN KEY (blocked_id)
        REFERENCES Users(user_id)
        ON DELETE CASCADE
);

CREATE TABLE Calls(
    call_id         INTEGER PRIMARY KEY NOT NULL,
    chat_id         INTEGER NOT NULL,
    caller_id       INTEGER NOT NULL,
    call_type       call_type NOT NULL,
    started_at      TIMESTAMPTZ NOT NULL,
    answered_at     TIMESTAMPTZ,
    ended_at        TIMESTAMPTZ,
    status          call_status NOT NULL,

    CONSTRAINT chk_call_timestamps
        CHECK(
            (answered_at is NULL OR answered_at>=started_at)
            AND
            (ended_at is NULL OR ended_at>=started_at)
            AND
            (answered_at IS NULL OR ended_at IS NULL OR ended_at >= answered_at)
        ),
    CONSTRAINT chk_call_status_timestamps
        CHECK (
            (status = 'COMPLETED' AND answered_at IS NOT NULL AND ended_at IS NOT NULL)
            OR
            (status = 'FAILED' AND answered_at IS NULL AND ended_at IS NULL)
            OR
            (status IN ('MISSED', 'REJECTED') AND answered_at IS NULL AND ended_at IS NOT NULL)
        ),
    CONSTRAINT fk_calls_chat
        FOREIGN KEY (chat_id)
        REFERENCES Chats(chat_id)
        ON DELETE CASCADE,
   CONSTRAINT fk_calls_caller
        FOREIGN KEY (caller_id)
        REFERENCES Users(user_id)
        ON DELETE CASCADE
);

CREATE TABLE Messages (
    message_id           INTEGER PRIMARY KEY,
    chat_id              INTEGER NOT NULL,
    sender_id            INTEGER NOT NULL,
    sent_at              TIMESTAMPTZ NOT NULL,
    message_type         message_type NOT NULL,
    body                 TEXT,
    media_id             INTEGER,
    reply_to_message_id  INTEGER,
    is_forwarded         BOOLEAN NOT NULL,
    is_deleted           BOOLEAN NOT NULL,
    edited_at            TIMESTAMPTZ,

    CONSTRAINT chk_edited_at
        CHECK (edited_at IS NULL OR edited_at >= sent_at),

    CONSTRAINT fk_messages_chat
        FOREIGN KEY (chat_id)
        REFERENCES Chats(chat_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_messages_sender
        FOREIGN KEY (sender_id)
        REFERENCES Users(user_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_messages_media
        FOREIGN KEY (media_id)
        REFERENCES Media(media_id)
        ON DELETE SET NULL,

    CONSTRAINT fk_messages_reply
        FOREIGN KEY (reply_to_message_id)
        REFERENCES Messages(message_id)
        ON DELETE SET NULL
);

CREATE TABLE Message_receipts (
    message_id    INTEGER NOT NULL,
    user_id       INTEGER NOT NULL,
    delivered_at  TIMESTAMPTZ,
    read_at       TIMESTAMPTZ,

    PRIMARY KEY (message_id, user_id),

    CONSTRAINT chk_receipt_timestamps
        CHECK (
            (delivered_at IS NOT NULL OR read_at IS NULL)
            AND
            (read_at IS NULL OR read_at >= delivered_at)
        ),

    CONSTRAINT fk_receipts_message
        FOREIGN KEY (message_id)
        REFERENCES Messages(message_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_receipts_user
        FOREIGN KEY (user_id)
        REFERENCES Users(user_id)
        ON DELETE CASCADE
);
