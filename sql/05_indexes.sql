-- R01, R02
-- B-tree: chat_id is the equality/filter column first, followed by sent_at DESC
-- so R01 can fetch each chat's latest message and R02 can read recent messages
-- in order without an additional sort.
CREATE INDEX idx_messages_chat_id_sent_at 
ON messages(chat_id, sent_at DESC);

-- R03
-- B-tree on user_id narrows R03's unread-receipt scan to one recipient; the
-- single equality column is first because it is the query's selective filter.
CREATE INDEX idx_message_receipts_user_id 
ON message_receipts(user_id) 
WHERE read_at IS NULL;

-- R04
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- GIN with pg_trgm accelerates R04's substring predicate (ILIKE '%meeting%');
-- no column order applies because this is a single-column inverted index.
CREATE INDEX idx_messages_body_trgm
ON whatsapp.messages
USING GIN (body gin_trgm_ops);

-- R06
-- B-tree: user_id is first for R06's equality filter on the current user,
-- followed by chat_id for the join to the other member in each direct chat.
CREATE INDEX idx_chat_members_user_chat
ON whatsapp.chat_members (user_id, chat_id);

--R08
-- Partial B-tree stores only undelivered receipts, shrinking R08's pending scan;
-- message_id supports the join to messages, while INCLUDE(user_id) covers the
-- receipt columns selected by the query without changing key order.
CREATE INDEX idx_messages_receipts_undelivered_msg
ON message_receipts(message_id) 
INCLUDE (user_id)
WHERE delivered_at IS NULL;

-- R10
-- B-tree on sent_at supports R10's sargable June 2026 timestamp range; the
-- single range column is the complete predicate, so no composite order is needed.
CREATE INDEX idx_messages_sent_at 
ON messages(sent_at) 
INCLUDE (sender_id);