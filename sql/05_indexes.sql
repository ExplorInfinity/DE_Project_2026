SET search_path TO whatsapp;

-- R13: Partial index for checking whether messages have replies.
-- Excludes NULL reply references to keep the index smaller.
CREATE INDEX IF NOT EXISTS idx_messages_reply_to
ON messages (reply_to_message_id)
WHERE reply_to_message_id IS NOT NULL;

-- R23: Partial covering index for inactive WEB/DESKTOP devices.
-- Uses last_active_at for filtering and includes projected columns.
CREATE INDEX IF NOT EXISTS idx_devices_inactive_web_desktop
ON devices (last_active_at)
INCLUDE (device_id, user_id, device_type)
WHERE device_type IN ('WEB', 'DESKTOP');

-- R01, R02, R04, R13, W02: B-tree index for chat_id lookups.
-- Supports equality filtering and targeted message retrieval.
CREATE INDEX IF NOT EXISTS idx_messages_chat_id
ON messages (chat_id);

ANALYZE messages;
ANALYZE devices;