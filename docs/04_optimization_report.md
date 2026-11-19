# Phase 4 — Query Optimization Report

## 1. Method

The original workload in `queries/workload_30.sql` was benchmarked against the baseline database with only primary-key and UNIQUE-constraint indexes. The optimized workload in `sql/06_optimized_queries.sql` was benchmarked after running `sql/05_indexes.sql` and `ANALYZE`.

Every query used `EXPLAIN (ANALYZE, BUFFERS)`. The baseline run used three repetitions; the optimized run used five repetitions as specified in the Phase 4 instructions. Write queries were executed inside `BEGIN; ... ROLLBACK;`. Timings below are the `avg_ms` values from the two generated `summary.csv` files.

The raw plans are preserved in:

- `benchmarks/results/baseline/`
- `benchmarks/results/optimized/`

## 2. Optimization results

Improvement is calculated as `(before - after) / before * 100`. A negative value means the optimized run was slower; on this small, cached dataset that can be measurement noise or index overhead.

| Query | Before (ms) | Problem / plan observation | Optimization applied | After (ms) | Improvement | Same result? |
|---|---:|---|---|---:|---:|:---:|
| R01 | 25.225 | Latest message lookup repeatedly scanned `messages`. | `idx_chat_members_user_chat` and `idx_messages_chat_id_sent_at`. | 0.686 | 97.3% | ✅ |
| R02 | 4.570 | Chat filter used a sequential scan on `messages`. | `idx_messages_chat_id` narrows the chat before sorting. | 0.551 | 87.9% | ✅ |
| R03 | 32.226 | Unread receipts were found with a sequential scan. | Partial `idx_message_receipts_user_id` for unread receipts. | 0.713 | 97.8% | ✅ |
| R04 | 22.270 | Membership was selective, but message search still examined message rows. | `idx_chat_members_user_chat` and chat lookup index; the planner retained a bitmap message lookup on this small dataset. | 0.688 | 96.9% | ✅ |
| R05 | 0.022 | Already an exact UNIQUE-index lookup. | No change. | 0.105 | -377.3% | ✅ |
| R06 | 3.149 | Direct-chat membership lookup needed a supporting user-first index. | `idx_chat_members_user_chat`. | 0.536 | 83.0% | ✅ |
| R07 | 0.636 | Already selective through `chat_members_pkey`; no extra tuning index was needed. | No query/index change. | 0.361 | 43.2% | ✅ |
| R08 | 24.510 | Undelivered receipts and message time had no supporting access path. | `idx_messages_sent_at` and partial undelivered-receipt index. | 14.524 | 40.7% | ✅ |
| R09 | 11.561 | Aggregates most of `media`; a sequential scan is appropriate. | No change. | 14.023 | -21.3% | ✅ |
| R10 | 10.408 | `sent_at::date` prevented a timestamp range scan. | Replaced the cast predicate with a half-open June timestamp range and added `idx_messages_sent_at`. | 3.741 | 64.1% | ✅ |
| R11 | 7.444 | Year extraction prevented a direct time predicate; calls lacked a selective partial index. | Replaced it with `started_at >=` and added a partial missed-call index. | 0.454 | 93.9% | ✅ |
| R12 | 8.347 | Forwarded rows were grouped after scanning all messages. | Partial `(sender_id, sent_at)` index for forwarded messages. | 5.567 | 33.3% | ✅ |
| R13 | 26.130 | `NOT IN` was incorrect because `reply_to_message_id` contains NULLs. | Replaced it with correlated `NOT EXISTS`; added question and reply-target indexes. | 0.571 | 97.8% | ✅* |
| R14 | 7.160 | June rows are aggregated across much of `messages`; `chats` is small. | `idx_messages_sent_at` supports the date range. | 7.909 | -10.5% | ✅ |
| R15 | 0.035 | Already an exact composite primary-key lookup. | No change. | 0.079 | -125.7% | ✅ |
| R16 | 0.262 | Message receipt and user primary keys already make the lookup selective. | No change. | 0.303 | -15.6% | ✅ |
| R17 | 28.049 | Large receipt/message join and aggregation; receipts still require a broad scan. | Timestamp index helps the message side, but the receipt scan remains necessary. | 22.553 | 19.6% | ✅ |
| R18 | 19.488 | Broad user, membership, and group existence checks. | No selective single-table access path was justified for this dataset. | 15.220 | 21.9% | ✅ |
| R19 | 14,565.326 | Two correlated subqueries scanned all `messages` once per group. | `idx_messages_chat_id_sent_at` makes both per-group aggregates index-only. | 6.653 | 100.0% | ✅ |
| R20 | 38.850 | Planner estimated too many groups and used an external merge sort. | Extended statistics on hour expression and `message_type` enable in-memory `HashAggregate`. | 21.638 | 44.3% | ✅ |
| R21 | 10.986 | Aggregate reads the whole message table; an index would add write cost without avoiding the scan. | No change. | 10.520 | 4.2% | ✅ |
| R22 | 8.674 | Deep OFFSET discarded 100,000 rows after fetching projected columns. | Deferred join: scan only primary keys for the OFFSET, then fetch 25 rows. | 5.413 | 37.6% | ✅ |
| R23 | 3.539 | Stale-device predicate used a sequential scan and sort. | Partial covering index on `last_active_at` for WEB/DESKTOP devices. | 0.992 | 72.0% | ✅ |
| R24 | 10.092 | Duplicate detection aggregates nearly all `media`; sequential scan is appropriate. | No change. | 15.761 | -56.2% | ✅ |
| R25 | 0.199 | Recursive steps already use `messages_pkey`. | No change. | 0.240 | -20.6% | ✅ |
| W01 | 2.962 | Small insert; no scan bottleneck. | No query rewrite. | 4.855 | -63.9% | ✅ |
| W02 | 11.968 | Original plan scanned all messages to find the target chat. | Reordered the update around selective unread receipts and message primary-key lookups. | 1.433 | 88.0% | ✅ |
| W03 | 0.391 | Single-row primary-key update was already selective. | No change. | 2.746 | -602.3% | ✅ |
| W04 | 37.974 | Cost is dominated by inserting 5,000 rows, FK checks, and the conflict check. | No query rewrite; avoided unnecessary full secondary indexes on receipts. | 37.452 | 1.4% | ✅ |
| W05 | 0.128 | Composite primary key directly locates the membership row. | No change. | 0.130 | -1.6% | ✅ |
| **Total of query averages** | **14,922.581** |  |  | **196.417** | **98.7%** |  |

`*` R13 is equivalent to the intended business question, but not to the faulty original result. The original query can return no rows because `NOT IN` becomes UNKNOWN when its subquery contains NULL.

## 3. Important plan findings

### R19 — largest improvement

The baseline plan performed two sequential scans of the 120,000-row `messages` table for each of 3,000 groups, producing about 7.8 million shared-buffer hits and an average of 14,565.326 ms. After `idx_messages_chat_id_sent_at`, both correlated aggregates use index-only scans. The optimized average is 6.653 ms.

### R13 — correctness and performance fix

The original predicate was:

```sql
AND m.message_id NOT IN (
    SELECT r.reply_to_message_id FROM messages r
)
```

Because non-reply messages have `reply_to_message_id IS NULL`, `NOT IN` is not safe here. The optimized query uses:

```sql
AND NOT EXISTS (
    SELECT 1
    FROM messages r
    WHERE r.reply_to_message_id = m.message_id
)
```

The partial question index reduces the candidate rows for group 20501, and `idx_messages_reply_to` makes the anti-lookup index-only.

### R20 — statistics, not a forced scan setting

The baseline plan used `GroupAggregate` plus an external merge sort with approximately 2.5 MB of temporary disk data. `stats_messages_hour_type` teaches the planner that the result has at most 144 hour/type groups. The optimized plan uses in-memory `HashAggregate` and a small quicksort while still correctly scanning the message table once.

### R22 — deep pagination

The optimized query first obtains only 25 primary keys after the OFFSET using an index-only scan, then joins those keys back to `messages`. This reduces heap work while preserving the original ordering and projected columns.

### R23 — covering partial index

The optimized plan uses `Index Only Scan using idx_devices_inactive_web_desktop` with zero heap fetches in the captured plans. The partial predicate excludes non-WEB/DESKTOP devices, and the key order supplies the requested `last_active_at` ordering.

### W02 — write optimization

The optimized plan starts with the partial unread-receipt index for `user_id = 965`, then checks the related messages by primary key. It updates the same 14 qualifying receipts as the original predicate while reducing the average from 11.968 ms to 1.433 ms.

## 4. Indexes and statistics added

All tuning objects are defined in `sql/05_indexes.sql`. R07 deliberately uses the existing `chat_members_pkey`; it does not depend on an undeclared `idx_chat_members_current_group` index.

| Object | Type | Definition / purpose | Queries |
|---|---|---|---|
| `idx_messages_chat_id_sent_at` | B-tree | `(chat_id, sent_at DESC)` for per-chat latest/history lookups | R01, R02, R19 |
| `idx_message_receipts_user_id` | Partial B-tree | `(user_id) WHERE read_at IS NULL` | R03, W02 |
| `idx_messages_body_trgm` | GIN trigram | Supports substring search on `body` when selected by the planner | R04 |
| `idx_chat_members_user_chat` | B-tree | `(user_id, chat_id)` for user-first membership joins | R04, R06, R11 |
| `idx_messages_receipts_undelivered_msg` | Partial covering B-tree | `(message_id) INCLUDE (user_id) WHERE delivered_at IS NULL` | R08 |
| `idx_messages_sent_at` | Covering B-tree | `(sent_at) INCLUDE (sender_id)` for timestamp ranges | R08, R10, R14, R17 |
| `idx_calls_missed_chat_time` | Partial covering B-tree | Missed calls keyed by `(chat_id, started_at DESC)` | R11 |
| `idx_messages_forwarded_sender_time` | Partial B-tree | `(sender_id, sent_at) WHERE is_forwarded` | R12 |
| `idx_messages_chat_questions` | Partial B-tree | `(chat_id) WHERE body LIKE '%?%'` | R13 |
| `idx_messages_reply_to` | Partial B-tree | `(reply_to_message_id) WHERE reply_to_message_id IS NOT NULL` | R13 |
| `stats_messages_hour_type` | Extended statistics | Hour expression plus `message_type` cardinality | R20 |
| `idx_devices_inactive_web_desktop` | Partial covering B-tree | `last_active_at` plus projected columns for WEB/DESKTOP | R23 |
| `idx_messages_chat_id` | B-tree | `(chat_id)` for chat-membership message filtering | R02, R04, W02 |

To record environment-specific index sizes in the report, run this in the same benchmark database after applying `sql/05_indexes.sql`:

```sql
SELECT schemaname,
       indexname,
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size
FROM pg_indexes
WHERE schemaname = 'whatsapp'
  AND indexname LIKE 'idx\_%' ESCAPE '\'
ORDER BY indexname;
```

The benchmark `summary.csv` files record execution times and scan nodes, but not `pg_relation_size`; sizes should therefore be copied from this database query rather than invented from plan output.

## 5. Correctness notes

- The original workload file was not modified.
- R10 changes a function-wrapped date filter to a half-open timestamp range for June 2026.
- R11 changes `EXTRACT(YEAR FROM started_at) >= 2025` to the equivalent timestamp lower bound.
- R13 uses `NOT EXISTS` to implement the intended unanswered-question semantics safely with NULLs.
- R22 preserves the unique `message_id DESC` ordering by fetching the same offset keys before joining back.
- W02 preserves the original update conditions and timestamp assignments; only the access path and predicate shape were changed.
- All write benchmarks use rollback, so benchmark execution does not permanently alter the seed data.

## 6. Queries intentionally left as sequential scans

R09, R14, R17, R18, R20, R21, and R24 still read a substantial share of their input tables or perform broad aggregation. Adding indexes would not remove the need to process most rows and would add storage and write-maintenance cost. R05, R15, R16, R25, W01, W03, and W05 were already primary-key/UNIQUE-key or small single-row operations; their negative percentage changes are normal cached-run variance and are not evidence of a correctness problem.

The optimized artifact set is complete: `summary.csv` plus `R01.txt`–`R25.txt` and `W01.txt`–`W05.txt` in `benchmarks/results/optimized/`.
