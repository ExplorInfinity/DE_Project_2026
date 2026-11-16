# Phase 4 — Query Optimization Report

## 1. Overview

Phase 4 focused on improving the performance and correctness of the WhatsApp messaging database workload.

The optimization work included:

- Rewriting inefficient SQL queries.
- Creating B-tree, partial, and covering indexes.
- Evaluating execution plans using `EXPLAIN ANALYZE`.
- Comparing baseline and optimized benchmark results.
- Validating query correctness.
- Measuring index storage overhead.
- Evaluating the impact of indexes on write operations.

The original workload file `queries/workload_30.sql` was preserved. The optimized workload is maintained separately in `sql/06_optimized_queries.sql`.

The workload contains 25 read queries (R01–R25) and 5 write queries (W01–W05).

All official benchmark comparisons use five runs:

```bash
./benchmarks/run_benchmark.sh whatsapp_phase4 optimized 5 sql/06_optimized_queries.sql
```

## 2. Optimizations Implemented

### 2.1 R13 — Unanswered Group Questions

**Problem**

The original query used `NOT IN` with a subquery that could return NULL values. In SQL, a NULL inside a `NOT IN` subquery can cause the condition to evaluate to UNKNOWN, resulting in no matching rows.

The original query returned zero rows even though seven unanswered questions existed.

**Optimization**

Replaced `NOT IN` with a correlated `NOT EXISTS` condition.

Created a partial index:

```sql
CREATE INDEX IF NOT EXISTS idx_messages_reply_to
ON messages (reply_to_message_id)
WHERE reply_to_message_id IS NOT NULL;
```

The query also benefits from `idx_messages_chat_id`, which filters messages by chat.

**Correctness observation**

- Original query: 0 rows.
- Corrected query: 7 rows.

This is an intentional correctness fix. The rewritten query does not preserve the incorrect original output; it returns the seven logically valid unanswered questions.

**Performance**

| Metric | Time |
|---|---:|
| Baseline average | 19.877 ms |
| Optimized average | 0.122 ms |
| Improvement | 99.39% |

The optimized plan uses:

- Bitmap Index Scan on `idx_messages_chat_id`.
- Bitmap Heap Scan on `messages`.
- Nested Loop Anti Join.
- Index Only Scan on `idx_messages_reply_to`.

The index-only scan reported zero heap fetches.

### 2.2 R19 — Group Health Report

**Problem**

The original query used two correlated subqueries for every group. Each subquery repeatedly scanned the messages table.

With 3,000 groups, this resulted in approximately 6,000 sequential scans of the messages table.

The baseline plan recorded approximately 7,746,156 shared buffer hits.

**Optimization**

Replaced the repeated correlated subqueries with a common table expression that aggregates messages once by `chat_id`, followed by a LEFT JOIN with the chats table.

The aggregation calculates:

- Latest message timestamp.
- Number of messages since June 1, 2026.

**Correctness validation**

The original and optimized queries were compared using `EXCEPT ALL` in both directions.

Both comparisons returned zero differing rows:

- `original_only = 0`
- `optimized_only = 0`

This confirms that the rewritten query preserves the original results.

**Performance**

| Metric | Time |
|---|---:|
| Baseline average | 17,217.756 ms |
| Optimized average | 14.443 ms |
| Improvement | 99.92% |

The optimized plan uses:

- One sequential scan of `messages`.
- HashAggregate grouped by `messages.chat_id`.
- Hash Right Join with `chats`.
- Sort of the resulting 3,000 rows.

Shared buffer hits decreased from approximately 7,746,156 to 1,447.

This rewrite eliminated repeated correlated scans and significantly reduced database work.

### 2.3 R23 — Inactive Devices

**Problem**

The original query performed a sequential scan of the devices table, filtered WEB and DESKTOP devices, and sorted the matching records.

**Optimization**

Created a partial covering index:

```sql
CREATE INDEX IF NOT EXISTS idx_devices_inactive_web_desktop
ON devices (last_active_at)
INCLUDE (device_id, user_id, device_type)
WHERE device_type IN ('WEB', 'DESKTOP');
```

The index:

- Includes only WEB and DESKTOP devices.
- Uses `last_active_at` as its B-tree key.
- Includes projected columns to support index-only scans.

**Performance**

| Metric | Time |
|---|---:|
| Baseline average | 3.028 ms |
| Optimized average | 0.483 ms |
| Improvement | 84.05% |

The optimized plan uses an Index Only Scan on `idx_devices_inactive_web_desktop`.

It returned 6,945 rows with zero heap fetches and reduced shared buffer hits from 353 to 37.

### 2.4 W02 — Message Lookup by Chat

**Problem**

The original W02 operation needed to locate messages belonging to a specific chat before updating their associated unread receipts.

The baseline plan performed a sequential scan of the 120,000-row messages table.

**Optimization**

Created a B-tree index:

```sql
CREATE INDEX IF NOT EXISTS idx_messages_chat_id
ON messages (chat_id);
```

This index also benefits R01, R02, R04, and R13.

**Performance**

| Metric | Time |
|---|---:|
| Baseline average | 8.852 ms |
| Optimized average | 1.429 ms |
| Improvement | 83.86% |

The optimized plan uses a Bitmap Index Scan on `idx_messages_chat_id`, followed by a Bitmap Heap Scan. It avoids scanning the entire messages table.

## 3. Index Design and Rationale

The following indexes were added in `sql/05_indexes.sql`.

| Index | Queries served | Design rationale |
|---|---|---|
| `idx_messages_reply_to` | R13 | Partial B-tree index on non-NULL reply references, supporting efficient reply-existence checks |
| `idx_devices_inactive_web_desktop` | R23 | Partial covering index for WEB/DESKTOP devices, supporting timestamp filtering and index-only retrieval |
| `idx_messages_chat_id` | R01, R02, R04, R13, W02 | B-tree index for equality lookups by chat ID |

All three indexes are documented in the SQL file with comments explaining their purpose.

The index definitions are followed by `ANALYZE` statements to refresh table statistics used by the PostgreSQL query planner.

## 4. Full Workload Performance Summary

The following table compares the official five-run baseline and optimized benchmark averages.

Improvement is calculated as:

`((Baseline - Optimized) / Baseline) × 100`

A positive value represents a performance improvement. A negative value represents a slower measured average.

| Query | Baseline (ms) | Optimized (ms) | Improvement |
|---|---:|---:|---:|
| R01 | 20.071 | 5.352 | +73.33% |
| R02 | 3.821 | 0.262 | +93.14% |
| R03 | 12.310 | 14.696 | -19.38% |
| R04 | 24.927 | 1.604 | +93.57% |
| R05 | 0.029 | 0.097 | -234.48% |
| R06 | 1.267 | 3.139 | -147.75% |
| R07 | 0.388 | 0.566 | -45.88% |
| R08 | 21.495 | 19.365 | +9.91% |
| R09 | 10.085 | 9.976 | +1.08% |
| R10 | 8.929 | 9.625 | -7.79% |
| R11 | 5.828 | 6.258 | -7.38% |
| R12 | 7.258 | 7.930 | -9.26% |
| R13 | 19.877 | 0.122 | +99.39% |
| R14 | 6.577 | 12.109 | -84.11% |
| R15 | 0.020 | 0.047 | -135.00% |
| R16 | 0.077 | 0.237 | -207.79% |
| R17 | 26.118 | 23.665 | +9.39% |
| R18 | 13.913 | 14.362 | -3.23% |
| R19 | 17,217.756 | 14.443 | +99.92% |
| R20 | 46.258 | 43.453 | +6.06% |
| R21 | 11.454 | 11.012 | +3.86% |
| R22 | 7.891 | 8.025 | -1.70% |
| R23 | 3.028 | 0.483 | +84.05% |
| R24 | 8.968 | 9.117 | -1.66% |
| R25 | 0.053 | 0.101 | -90.57% |
| W01 | 1.188 | 1.676 | -41.08% |
| W02 | 8.852 | 1.429 | +83.86% |
| W03 | 0.302 | 0.465 | -53.97% |
| W04 | 34.181 | 33.514 | +1.95% |
| W05 | 0.114 | 0.116 | -1.75% |

**Interpretation**

The strongest improvements occurred in R19, R13, R04, R02, R23, and W02.

Several queries showed small timing regressions. These should be interpreted carefully because some baseline execution times were already extremely small. Relative percentage changes can be misleading when the absolute difference is only a fraction of a millisecond.

The optimized workload did not rewrite every query. Queries without a demonstrated optimization opportunity were retained.

## 5. Before-and-After Execution Plan Analysis

Five major improvements were examined using `EXPLAIN ANALYZE`.

### 5.1 R19 — Correlated Subqueries to Aggregation

| Metric | Before | After |
|---|---:|---:|
| Execution time | 17,217.756 ms | 14.443 ms |
| Shared buffer hits | 7,746,156 | 1,447 |
| Messages scans | Approximately 6,000 | 1 |
| Output rows | 3,000 | 3,000 |

**Before:** Repeated sequential scans of `messages` inside two correlated subqueries.

**After:** One sequential scan, one HashAggregate, and one Hash Right Join.

### 5.2 R13 — NOT IN to NOT EXISTS

| Metric | Before | After |
|---|---:|---:|
| Execution time | 19.877 ms | 0.122 ms |
| Shared buffer hits | 2,582 | 48 |
| Main access method | Sequential Scan | Bitmap Heap Scan |
| Reply lookup | Hashed subplan | Index Only Scan |

**Before:** Full sequential scans of the messages table for the outer query and subquery.

**After:** Bitmap Index Scan using `idx_messages_chat_id`, followed by an Index Only Scan using `idx_messages_reply_to`.

The rewrite also corrects the NULL-related logical error.

### 5.3 R04 — User's Chat Messages

| Metric | Before | After |
|---|---:|---:|
| Execution time | 24.927 ms | 1.604 ms |
| Shared buffer hits | 1,583 | 378 |
| Messages access | Sequential Scan | Bitmap Heap Scan |
| Output rows | 6 | 6 |

**Before:** PostgreSQL scanned all 120,000 messages and applied the case-insensitive body filter.

**After:** PostgreSQL retrieved chat memberships through `chat_members_pkey`, then used `idx_messages_chat_id` to access messages in those chats.

The leading-wildcard `ILIKE` condition is still evaluated on candidate messages; the B-tree index accelerates the chat lookup, not the text search.

### 5.4 R02 — Messages in a Specific Chat

| Metric | Before | After |
|---|---:|---:|
| Execution time | 3.821 ms | 0.262 ms |
| Shared buffer hits | 1,294 | 38 |
| Scan method | Sequential Scan | Bitmap Heap Scan |
| Output rows | 34 | 34 |

**Before:** PostgreSQL examined 120,000 messages and discarded 119,966.

**After:** A Bitmap Index Scan on `idx_messages_chat_id` identified matching entries, followed by a Bitmap Heap Scan.

### 5.5 R23 — Partial Covering Index

| Metric | Before | After |
|---|---:|---:|
| Execution time | 3.028 ms | 0.483 ms |
| Shared buffer hits | 353 | 37 |
| Scan method | Sequential Scan | Index Only Scan |
| Heap fetches | Not applicable | 0 |
| Output rows | 6,945 | 6,945 |

**Before:** A full sequential scan of the devices table, followed by sorting.

**After:** PostgreSQL used `idx_devices_inactive_web_desktop` directly. The plan reported zero heap fetches.

These five comparisons demonstrate the impact of query rewriting, targeted B-tree indexes, and partial covering indexes.

## 6. Index Storage Overhead

The following storage figures were measured after creating the three indexes.

| Created index | Index size | Associated table size |
|---|---:|---:|
| `idx_messages_reply_to` | 344 KB | messages: 13 MB |
| `idx_messages_chat_id` | 1,304 KB | messages: 13 MB |
| `idx_devices_inactive_web_desktop` | 496 KB | devices: 4,272 KB |
| **Total new index storage** | **2,144 KB** | — |

The total additional index storage is approximately 2.09 MB.

The existing `messages_pkey` index is not included in this total because it was not created as part of Phase 4.

The additional storage is a trade-off for faster read access and targeted lookups.

## 7. Write Workload Analysis

All five write queries were benchmarked before and after the optimizations.

| Write query | Baseline (ms) | Optimized (ms) | Change |
|---|---:|---:|---:|
| W01 | 1.188 | 1.676 | 41.08% slower |
| W02 | 8.852 | 1.429 | 83.86% faster |
| W03 | 0.302 | 0.465 | 53.97% slower |
| W04 | 34.181 | 33.514 | 1.95% faster |
| W05 | 0.114 | 0.116 | 1.75% slower |

### Analysis

- **W01:** Inserts a message. The new `idx_messages_chat_id` index requires maintenance for inserted messages. The measured operation was slower, although benchmark variation may also contribute.
- **W02:** Improved substantially because the new chat ID index accelerates the message lookup involved in the operation.
- **W03:** Updates a message by its primary key. The measured increase was only 0.163 ms in absolute terms. This difference should not be treated as proof that the new indexes caused the slowdown.
- **W04:** Inserts receipts. Its execution time remained nearly unchanged. Foreign-key checks and the batch of inserted rows remain important parts of its cost.
- **W05:** Updates a chat membership row by its primary key. The measured difference was very small.

Overall, W02 benefited considerably. W01 and W03 were slower in the measured runs, while W04 and W05 remained broadly similar.

These results show the read/write trade-off of indexing. The observed timing differences alone do not establish that every regression was caused by the new indexes.

## 8. Queries Not Rewritten and Further Optimization Opportunities

### R22 — Deep OFFSET Pagination

The original query uses the primary-key index through a backward index scan. However, it must process approximately 100,025 rows to return 25 rows because of `OFFSET 100000`.

An additional ordinary index does not eliminate the cost of skipping a large number of rows.

A separate keyset-pagination experiment used the last-seen message ID:

```sql
SELECT message_id, chat_id, sender_id, message_type, sent_at
FROM messages
WHERE message_id < 20001
ORDER BY message_id DESC
LIMIT 25;
```

The experiment returned the same page as the OFFSET query, verified with `EXCEPT ALL` in both directions. Its measured execution time was approximately 0.068 ms, compared with the original baseline average of 7.891 ms.

This is a separate production-oriented experiment, not the official optimized R22 workload query. The original R22 was retained to preserve the workload's semantics.

### R20 — Hourly Message Aggregation

R20 already performs a full-table aggregation. An explicit GROUP BY rewrite did not produce a meaningful improvement, so the original query was retained.

### Other Queries

Some queries continued to use sequential scans because their access patterns involve processing a substantial proportion of the table or do not benefit sufficiently from the newly created indexes.

Queries with extremely small execution times also showed percentage fluctuations that are not necessarily meaningful in absolute terms.

Optimization decisions were based on measured execution plans and workload behavior rather than forcing index usage for every query.

## 9. Correctness Validation

The original workload file was preserved, and the optimized workload was maintained separately.

Two query rewrites were made:

- **R13:** Replaced `NOT IN` with `NOT EXISTS`. The original query returned zero rows due to NULL behavior, while the corrected query returned seven unanswered questions. This is an intentional correctness correction.
- **R19:** Compared the original and optimized results using `EXCEPT ALL` in both directions. Both directions returned zero rows, confirming result equivalence.

The remaining workload queries were retained without logical rewrites. Index creation changes access paths, not the intended query results.

## 10. Conclusion

Phase 4 introduced three indexes and two SQL query rewrites.

The most significant improvement came from R19, where repeated correlated subqueries were replaced with a single aggregation and join. R13 was corrected to handle NULL values safely and became substantially faster. R04, R02, R23, and W02 also benefited from targeted indexing.

The three new indexes require approximately 2,144 KB of additional storage.

Write workload measurements showed a substantial improvement in W02, while W01 and W03 were slower in the measured runs. These trade-offs were documented rather than assuming that indexes have no write cost.

The optimization decisions were supported by five-run benchmark comparisons, execution-plan analysis, correctness checks, and index storage measurements.

The original workload was preserved, and the optimized SQL and index definitions are maintained separately for reproducibility.