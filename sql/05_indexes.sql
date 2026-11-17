-- R01, R02, R19
-- B-tree: chat_id is the equality/filter column first, followed by sent_at DESC
-- so R01 can fetch each chat's latest message and R02 can read recent messages
-- in order without an additional sort.
-- In R19 chat_id supports per-chat lookups; sent_at supports finding the latest message.
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

-- R06, R11
-- B-tree: user_id is first for R06's equality filter on the current user,
-- followed by chat_id for the join to the other member in each direct chat.
-- In R11 user_id supports the membership lookup; chat_id supports the join to calls.
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

-- R11: Missed calls received by a user
-- chat_id supports the join; started_at DESC supports time filtering and ordering.
-- INCLUDE covers returned call details; the partial index stores only missed calls.
CREATE INDEX idx_calls_missed_chat_time
ON whatsapp.calls (chat_id, started_at DESC)
INCLUDE (call_id, caller_id, call_type)
WHERE status = 'MISSED';

-- R12: Users forwarding 2+ messages on the same day
-- sender_id supports grouping by sender; sent_at supports date grouping.
-- The partial index includes only forwarded messages.
CREATE INDEX idx_messages_forwarded_sender_time
ON whatsapp.messages (sender_id, sent_at)
WHERE is_forwarded = TRUE;

-- R13: Questions that nobody has replied to
-- chat_id finds question messages in the target chat; the partial predicate limits entries to questions.
CREATE INDEX idx_messages_chat_questions
ON whatsapp.messages (chat_id)
WHERE body LIKE '%?%';

-- Supports the NOT EXISTS reply lookup; excludes messages that are not replies.
CREATE INDEX idx_messages_reply_to
ON whatsapp.messages (reply_to_message_id)
WHERE reply_to_message_id IS NOT NULL;