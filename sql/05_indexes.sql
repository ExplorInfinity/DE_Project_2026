SET search_path TO whatsapp;

-- R13: Partial index for finding messages that have replies
CREATE INDEX IF NOT EXISTS idx_messages_reply_to
ON messages (reply_to_message_id)
WHERE reply_to_message_id IS NOT NULL;

-- R23: Partial covering index for inactive WEB/DESKTOP devices
CREATE INDEX IF NOT EXISTS idx_devices_inactive_web_desktop
ON devices (last_active_at)
INCLUDE (device_id, user_id, device_type)
WHERE device_type IN ('WEB', 'DESKTOP');

ANALYZE messages;
ANALYZE devices;