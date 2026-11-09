-- Load the seed CSV exports into the whatsapp schema.
-- Run this file from the repository root on a database where 01_schema.sql
-- has already been executed.

\set ON_ERROR_STOP on
SET search_path TO whatsapp;

BEGIN;

-- Parent table
\copy whatsapp.users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true)

-- User-dependent tables
\copy whatsapp.devices FROM 'seed_data/devices.csv' WITH (FORMAT csv, HEADER true)

-- Chat parent must be loaded before memberships, messages, and calls
\copy whatsapp.chats FROM 'seed_data/chats.csv' WITH (FORMAT csv, HEADER true)
\copy whatsapp.chat_members FROM 'seed_data/chat_members.csv' WITH (FORMAT csv, HEADER true)

-- Media must be loaded before messages that reference it
\copy whatsapp.media FROM 'seed_data/media.csv' WITH (FORMAT csv, HEADER true)
\copy whatsapp.blocked_users FROM 'seed_data/blocked_users.csv' WITH (FORMAT csv, HEADER true)
\copy whatsapp.calls FROM 'seed_data/calls.csv' WITH (FORMAT csv, HEADER true)
\copy whatsapp.messages FROM 'seed_data/messages.csv' WITH (FORMAT csv, HEADER true)
\copy whatsapp.message_receipts FROM 'seed_data/message_receipts.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;

COMMIT;

-- Expected row counts from the supplied seed data.
SELECT 'users' AS table_name, COUNT(*) AS row_count FROM whatsapp.users
UNION ALL
SELECT 'devices', COUNT(*) FROM whatsapp.devices
UNION ALL
SELECT 'chats', COUNT(*) FROM whatsapp.chats
UNION ALL
SELECT 'chat_members', COUNT(*) FROM whatsapp.chat_members
UNION ALL
SELECT 'media', COUNT(*) FROM whatsapp.media
UNION ALL
SELECT 'messages', COUNT(*) FROM whatsapp.messages
UNION ALL
SELECT 'message_receipts', COUNT(*) FROM whatsapp.message_receipts
UNION ALL
SELECT 'calls', COUNT(*) FROM whatsapp.calls
UNION ALL
SELECT 'blocked_users', COUNT(*) FROM whatsapp.blocked_users
ORDER BY table_name;

-- Integrity check 1: every message sender belongs to the message chat.
SELECT COUNT(*) AS message_sender_membership_violations
FROM whatsapp.messages m
WHERE NOT EXISTS (
    SELECT 1
    FROM whatsapp.chat_members cm
    WHERE cm.chat_id = m.chat_id
      AND cm.user_id = m.sender_id
);

-- Integrity check 2: every reply points to a message in the same chat.
SELECT COUNT(*) AS cross_chat_reply_violations
FROM whatsapp.messages m
JOIN whatsapp.messages parent
  ON parent.message_id = m.reply_to_message_id
WHERE parent.chat_id <> m.chat_id;

-- Integrity check 3: every direct chat has exactly two members.
SELECT COUNT(*) AS invalid_direct_chat_count
FROM (
    SELECT c.chat_id
    FROM whatsapp.chats c
    LEFT JOIN whatsapp.chat_members cm ON cm.chat_id = c.chat_id
    WHERE c.chat_type = 'DIRECT'
    GROUP BY c.chat_id
    HAVING COUNT(cm.user_id) <> 2
) invalid_direct_chats;

-- Integrity check 4: every receipt recipient belongs to the message chat.
SELECT COUNT(*) AS receipt_membership_violations
FROM whatsapp.message_receipts r
JOIN whatsapp.messages m ON m.message_id = r.message_id
WHERE NOT EXISTS (
    SELECT 1
    FROM whatsapp.chat_members cm
    WHERE cm.chat_id = m.chat_id
      AND cm.user_id = r.user_id
);

-- Integrity check 5: a referenced media row has the same type as its message.
SELECT COUNT(*) AS message_media_type_violations
FROM whatsapp.messages m
JOIN whatsapp.media me ON me.media_id = m.media_id
WHERE m.message_type::TEXT <> me.media_type::TEXT;
