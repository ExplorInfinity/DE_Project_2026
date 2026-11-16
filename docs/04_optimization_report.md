# Phase 4 — Query Optimization Report

## 1. Overview

This phase focused on improving the performance and correctness of selected queries in the WhatsApp messaging database.

The optimization work involved:
- Rewriting inefficient SQL queries.
- Designing partial and covering indexes.
- Evaluating query execution plans using `EXPLAIN ANALYZE`.
- Comparing baseline and optimized benchmark results.
- Measuring index storage and examining write workload overhead.

The original workload file `queries/workload_30.sql` was preserved. Optimized queries are maintained separately in `sql/06_optimized_queries.sql`.

## 2. Optimizations Implemented

### 2.1 R13 — Unanswered Group Questions

**Problem:** The original query used `NOT IN` with a subquery that could return NULL values. This caused the query to return zero rows, even though unanswered questions existed.

**Optimization:** Replaced `NOT IN` with a correlated `NOT EXISTS` condition and created a partial index:

```sql
CREATE INDEX IF NOT EXISTS idx_messages_reply_to
ON messages (reply_to_message_id)
WHERE reply_to_message_id IS NOT NULL;
```

**Correctness observation:** The original query returned 0 rows, while the rewritten query returned 7 rows. This demonstrates the NULL-related issue in the original query.

**Performance:**

| Metric | Time |
|---|---:|
| Baseline average | 19.877 ms |
| Optimized average | 8.381 ms |
| Improvement | 57.8% |

The optimized execution plan uses an index-only scan on `idx_messages_reply_to`.

### 2.2 R19 — Group Health Report

**Problem:** The original query used two correlated subqueries for every group. Each subquery repeatedly accessed the messages table.

**Optimization:** Replaced the repeated correlated subqueries with a common table expression that aggregates messages once by `chat_id`, followed by a LEFT JOIN with the chats table.

The aggregation calculates:
- Latest message timestamp.
- Number of messages since June 1, 2026.

**Performance:**

| Metric | Time |
|---|---:|
| Baseline average | 17,217.756 ms |
| Optimized average | 14.471 ms |
| Improvement | 99.92% |

**Correctness validation:** The original and optimized queries were compared using `EXCEPT ALL` in both directions. Both comparisons returned zero differing rows (`original_only = 0`, `optimized_only = 0`), confirming that the optimized query preserves the original results.

This rewrite substantially reduces repeated scanning of the messages table.

### 2.3 R23 — Inactive Devices

**Problem:** The original query performed a sequential scan of the devices table and sorted the matching records.

**Optimization:** Created a partial covering index:

```sql
CREATE INDEX IF NOT EXISTS idx_devices_inactive_web_desktop
ON devices (last_active_at)
INCLUDE (device_id, user_id, device_type)
WHERE device_type IN ('WEB', 'DESKTOP');
```

**Performance:**

| Metric | Time |
|---|---:|
| Baseline average | 3.028 ms |
| Optimized average | 0.509 ms |
| Improvement | 83.2% |

The optimized plan uses an index-only scan, with no heap fetches in the inspected plan.

## 3. Performance Summary

| Query | Baseline (ms) | Optimized (ms) | Improvement |
|---|---:|---:|---:|
| R13 | 19.877 | 8.381 | 57.8% |
| R19 | 17217.756 | 14.471 | 99.92% |
| R23 | 3.028 | 0.509 | 83.2% |

## 4. Index Storage Overhead

The following indexes were added:

| Index | Storage |
|---|---:|
| idx_messages_reply_to | 344 KB |
| idx_devices_inactive_web_desktop | 496 KB |
| **Total** | **840 KB** |

Relevant table sizes:

| Table | Total storage |
|---|---:|
| messages | 13 MB |
| devices | 4,272 KB |

The additional index storage is modest compared with the measured query performance improvements.

## 5. Write Workload Analysis

The five write queries were benchmarked before and after the optimizations.

The new indexes do not materially affect the tested write operations:

- W01 inserts a message without a reply reference, so it does not enter the partial reply index.
- W02 and W04 operate on message_receipts.
- W03 updates messages but does not modify reply_to_message_id.
- W05 updates chat_members.

The benchmark results show no clear systematic write-performance regression attributable to these indexes. Small timing differences may be caused by normal benchmark variation.

## 6. Queries Not Rewritten

### R22 — Deep Offset Pagination

R22 uses the primary-key index through a backward index scan. However, it scans approximately 100,025 rows to return only 25 rows because of `OFFSET 100000`.

An additional index would not eliminate this cost.

For production pagination, keyset pagination using the last-seen message ID is a more scalable alternative. The original workload query was retained to preserve its semantics.

### R20 — Hourly Message Aggregation

The query already performs a full-table aggregation. The attempted explicit GROUP BY rewrite did not produce a meaningful performance improvement, so the original query was retained.

Other queries using sequential scans were evaluated according to their access patterns. A sequential scan can be more efficient than an index scan when a large proportion of a table must be processed.

## 7. Conclusion

The Phase 4 optimization work produced substantial improvements in three important queries.

R13 was corrected to handle NULL values safely, R19 eliminated repeated correlated scans, and R23 benefited from a partial covering index.

The two added indexes require only 840 KB of storage. The tested write workload showed no clear systematic regression attributable to the new indexes.

The optimization decisions were based on measured execution times, execution plans, correctness considerations, and index storage costs.