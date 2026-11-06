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