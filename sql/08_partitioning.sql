-- CP4 architecture design: monthly RANGE partitioning for messages.
--
-- This is intentionally non-destructive and uses a new table name. The
-- existing whatsapp.messages table is the benchmark table and is not changed
-- by this file. A production migration must first backfill this parent,
-- update receipt/reply references, validate row counts, and then cut over.

SET search_path TO whatsapp, public;

CREATE TABLE IF NOT EXISTS messages_partitioned (
    message_id           INTEGER NOT NULL,
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

    CONSTRAINT messages_partitioned_pkey PRIMARY KEY (message_id, sent_at),
    CONSTRAINT messages_partitioned_edited_at
        CHECK (edited_at IS NULL OR edited_at >= sent_at),
    CONSTRAINT messages_partitioned_chat_fk
        FOREIGN KEY (chat_id) REFERENCES chats(chat_id),
    CONSTRAINT messages_partitioned_sender_fk
        FOREIGN KEY (sender_id) REFERENCES users(user_id),
    CONSTRAINT messages_partitioned_media_fk
        FOREIGN KEY (media_id) REFERENCES media(media_id)
) PARTITION BY RANGE (sent_at);

CREATE TABLE IF NOT EXISTS messages_2025
    PARTITION OF messages_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30')
               TO   ('2026-01-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS messages_2026_01
    PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30')
               TO   ('2026-02-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS messages_2026_02
    PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-02-01 00:00:00+05:30')
               TO   ('2026-03-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS messages_2026_03
    PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-03-01 00:00:00+05:30')
               TO   ('2026-04-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS messages_2026_04
    PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30')
               TO   ('2026-05-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS messages_2026_05
    PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-05-01 00:00:00+05:30')
               TO   ('2026-06-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS messages_2026_06
    PARTITION OF messages_partitioned
    FOR VALUES FROM ('2026-06-01 00:00:00+05:30')
               TO   ('2026-07-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS messages_default
    PARTITION OF messages_partitioned DEFAULT;

-- Local indexes preserve the Phase 4 access path inside each partition.
CREATE INDEX IF NOT EXISTS idx_messages_partitioned_chat_sent
    ON messages_partitioned (chat_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_partitioned_sent_at
    ON messages_partitioned (sent_at) INCLUDE (sender_id);

-- Example pruning check; after deployment, EXPLAIN should show only
-- messages_2026_06 below the aggregate for this half-open June range.
-- EXPLAIN (COSTS OFF)
-- SELECT count(*)
-- FROM messages_partitioned
-- WHERE sent_at >= '2026-06-01 00:00:00+05:30'
--   AND sent_at <  '2026-07-01 00:00:00+05:30';
