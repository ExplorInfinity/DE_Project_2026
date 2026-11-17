# Phase 4 — Query Optimization Report

## 1. Overview & Team Allocation

This report documents the performance analysis, query rewriting, and indexing optimizations for Phase 4 (Checkpoint 3) of the DBMS Course Project on the WhatsApp messaging workload.

### Team Allocation of Queries

To ensure modularity and avoid git conflicts, the workload of 25 read queries (R01–R25) and 5 write queries (W01–W05) was divided among team members:
* **Adarsh Balu:** Read queries **R01–R20** (user onboarding, direct messaging, chat screens, receipt delivery, growth, and group statistics).
* **Ramit Layek (This Report):** Read queries **R20–R25** (capacity planning, product analytics, deep pagination, device cleanup, deduplication, and recursive thread traversal) and Write queries **W01–W05** (message sending, batch read receipts, message deletion, broadcast delivery, and group membership updates).
* **Aditya Singla:** Project coordination, schema verification, and final end-to-end benchmark aggregation.

The baseline workload file `queries/workload_30.sql` was preserved unchanged. All optimized queries are maintained in `sql/06_optimized_queries.sql`, and all tuning indexes and extended statistics are defined in `sql/05_indexes.sql`.

---

## 2. Read Workload Optimization (R20–R25)

### 2.1 R20 — Hourly Message Distribution (Capacity Planning)

**Original Query:**
```sql
SELECT EXTRACT(HOUR FROM sent_at) AS hour, message_type, count(*) AS messages
FROM messages
GROUP BY 1, 2
ORDER BY 1, 2;
```

**Bottleneck Analysis:**
* The messages table contains 120,000 rows.
* In the baseline plan, PostgreSQL performs a sequential scan of `messages` followed by a sort on `(EXTRACT(hour FROM sent_at), message_type)` and a `GroupAggregate`.
* Because `sent_at` is a timestamp with time zone, the query planner lacks cross-column distribution statistics for the `EXTRACT(hour FROM ...)` expression combined with `message_type`.
* The planner estimated **120,000 distinct groups**, assuming nearly every row produced a unique group. Consequently, it assumed an in-memory hash table would exceed `work_mem`, choosing an **external merge disk sort**:
  ```
  Sort Key: (EXTRACT(hour FROM sent_at)), message_type
  Sort Method: external merge  Disk: 2576kB
  Buffers: shared hit=1299, temp read=322 written=324
  ```
* This spilled over 2.5 MB of temporary data to disk, causing high disk I/O and latency (~45–80 ms).

**Optimization:**
* Created extended multivariate statistics on the expression and column:
  ```sql
  CREATE STATISTICS IF NOT EXISTS stats_messages_hour_type
  ON (EXTRACT(HOUR FROM sent_at)), message_type
  FROM messages;
  ```
* With this statistic in place, PostgreSQL discovers the true cardinality is at most **144 distinct groups** (24 hours × 6 message types).
* The planner immediately switches to an in-memory **HashAggregate** (48 kB memory usage), followed by a quicksort of only 144 rows (33 kB memory).
* **Impact:** 100% elimination of disk spills (`temp read=0 written=0`), reducing execution cost from `18897.60` down to `3698.32`.

---

### 2.2 R21 — Share of Edited and Deleted Messages

**Original Query:**
```sql
SELECT message_type,
       count(*) AS messages,
       round(100.0 * count(*) FILTER (WHERE edited_at IS NOT NULL) / count(*), 2) AS edited_pct,
       round(100.0 * count(*) FILTER (WHERE is_deleted) / count(*), 2) AS deleted_pct
FROM messages
GROUP BY message_type
ORDER BY messages DESC;
```

**Analysis & Decision:**
* The query scans all 120,000 messages to aggregate edit and deletion rates across message types.
* The baseline execution uses a sequential scan (1,291 buffer hits) followed by an in-memory `HashAggregate` (24 kB memory) and a quicksort of 6 rows (25 kB memory), executing in ~11 ms.
* Creating a covering index on `(message_type) INCLUDE (edited_at, is_deleted)` would occupy ~5–7 MB of storage and would need to be updated on every single message insert (W01) and deletion (W03).
* Because a sequential scan over 1,291 cached pages is already fast, adding index maintenance overhead would significantly penalize write performance for negligible read benefit.
* **Decision:** Retained as-is with no index overhead.

---

### 2.3 R22 — Trust & Safety Console Deep Pagination

**Original Query:**
```sql
SELECT message_id, chat_id, sender_id, message_type, sent_at
FROM messages
ORDER BY message_id DESC
OFFSET 100000
LIMIT 25;
```

**Bottleneck Analysis:**
* In baseline execution, PostgreSQL uses a backward index scan on `messages_pkey`.
* However, because the query projects `chat_id, sender_id, message_type, sent_at`, PostgreSQL must visit the table heap for **every single one of the 100,025 traversed rows** just to discard 100,000 rows.
* This caused **100,025 heap visits** and **1,639 shared buffer hits**, resulting in unnecessary memory bandwidth consumption.

**Optimization (Deferred Join / Late Row Lookup):**
* Rewrote the query using the **Deferred Join** pattern:
  ```sql
  SELECT m.message_id, m.chat_id, m.sender_id, m.message_type, m.sent_at
  FROM (
      SELECT message_id
      FROM messages
      ORDER BY message_id DESC
      OFFSET 100000
      LIMIT 25
  ) sub
  JOIN messages m ON m.message_id = sub.message_id
  ORDER BY m.message_id DESC;
  ```
* **Execution Plan Difference:**
  * The inner subquery requires only `message_id`. Since `message_id` is the primary key, PostgreSQL satisfies the 100,000 row offset entirely via an **Index-Only Scan** on `messages_pkey` without reading the message heap.
  * Only the final 25 matching keys are joined back to `messages` via nested loop index scans to fetch the remaining columns.
* **Performance Impact:**
  * Shared buffer hits dropped from **1,639 to 352** (a **78.5% reduction** in buffer reads).
  * Execution time was reduced from ~30 ms down to ~12–13 ms.
  * Correctness was verified via two-way `EXCEPT ALL` tests returning 0 differing rows.

---

### 2.4 R23 — Stale Web and Desktop Device Cleanup

**Original Query:**
```sql
SELECT d.device_id, d.user_id, d.device_type, d.last_active_at
FROM devices d
WHERE d.device_type IN ('WEB', 'DESKTOP')
  AND d.last_active_at < '2026-06-01'
ORDER BY d.last_active_at;
```

**Bottleneck Analysis:**
* The devices table contains 24,000 devices.
* Without a supporting index, PostgreSQL performed a full sequential scan of `devices`, filtered for device types and dates, and performed an in-memory quicksort on the matching rows (~3.54 ms baseline average).

**Optimization (Partial Covering Index):**
* Created a partial covering B-tree index tailored to the query predicate and projection:
  ```sql
  CREATE INDEX IF NOT EXISTS idx_devices_inactive_web_desktop
  ON devices (last_active_at)
  INCLUDE (device_id, user_id, device_type)
  WHERE device_type IN ('WEB', 'DESKTOP');
  ```
* **Why this design:**
  * `WHERE device_type IN ('WEB', 'DESKTOP')`: Keeps the index partial and compact (only 496 kB), excluding mobile devices.
  * Key column `last_active_at`: Provides direct range filtering and outputs rows in sorted order, eliminating the explicit sort step.
  * `INCLUDE (device_id, user_id, device_type)`: Satisfies all projected columns directly from the index.
* **Performance Impact:**
  * The execution plan switched from `Seq Scan + Sort` to a pure **Index Only Scan**.
  * Heap fetches dropped to **0**.
  * Shared buffer hits decreased from 353 to **37** (89.5% reduction).
  * Average execution time dropped from 3.539 ms to **0.483 ms (~86% speedup)**.

---

### 2.5 R24 — Duplicate Media Files by SHA-256

**Original Query:**
```sql
SELECT sha256, count(*) AS copies, sum(size_bytes) AS total_bytes
FROM media
GROUP BY sha256
HAVING count(*) > 1
ORDER BY copies DESC;
```

**Analysis & Decision:**
* The `media` table contains 27,634 rows stored across only 454 disk blocks (3.5 MB).
* Baseline execution uses a sequential scan (454 buffer hits) and a `HashAggregate` to find the 48 duplicate hashes out of 24,371 distinct values, completing in ~9 ms.
* Because `sha256` is a 64-character hexadecimal text column, a B-tree index on `(sha256, size_bytes)` would consume ~2.5–3.5 MB (nearly equal to the size of the table). An index scan would require reading index blocks followed by table blocks, which offers no benefit over streaming 454 sequential heap blocks from RAM cache.
* **Decision:** Preserved baseline plan as optimal.

---

### 2.6 R25 — Recursive Reply Thread Traversal

**Original Query:**
```sql
WITH RECURSIVE thread AS (
    SELECT message_id, reply_to_message_id, sender_id, body, 0 AS depth
    FROM messages WHERE message_id = 119989
    UNION ALL
    SELECT m.message_id, m.reply_to_message_id, m.sender_id, m.body, t.depth + 1
    FROM messages m JOIN thread t ON m.message_id = t.reply_to_message_id
)
SELECT * FROM thread ORDER BY depth DESC;
```

**Analysis & Decision:**
* The anchor member looks up message 119989 using `messages_pkey` (Index Scan, 3 buffer hits).
* Each recursive iteration looks up the parent message using `messages_pkey` (`message_id = t.reply_to_message_id`).
* With depth 3, the entire query executes in **~0.19 ms** and hits only 12 shared buffers.
* **Decision:** Already highly optimized via the existing primary key index.

---

## 3. Write Workload Optimization & Trade-Offs (W01–W05)

### 3.1 W01 — Insert Message in Group 22556

```sql
INSERT INTO messages (message_id, chat_id, sender_id, sent_at, message_type, body)
VALUES (90000001, 22556, 965, '2026-07-01 09:00:00+05:30', 'TEXT', 'Good morning everyone');
```

**Analysis & Indexing Overhead:**
* Inserting a message requires checking 4 foreign key constraints:
  * `fk_messages_chat` on `chats(chat_id)`
  * `fk_messages_sender` on `users(user_id)`
  * `fk_messages_media` (NULL, skipped)
  * `fk_messages_reply` (NULL, skipped)
* In addition, every new index defined on the `messages` table must be updated on insert.
* Baseline insert execution time was ~1.19 ms. Adding excessive indexes on `messages` directly degrades insert throughput.
* **Design Precaution:** For Phase 4, we avoided adding unnecessary secondary indexes on `messages`. For example, our R20 optimization used **extended statistics** instead of an index, adding **zero insert maintenance overhead** to W01.

---

### 3.2 W02 — Mark Unread Group Messages as Read

**Original Query:**
```sql
UPDATE message_receipts r
SET read_at = TIMESTAMPTZ '2026-07-01 09:05:00+05:30',
    delivered_at = coalesce(r.delivered_at, TIMESTAMPTZ '2026-07-01 09:05:00+05:30')
FROM messages m
WHERE m.message_id = r.message_id
  AND m.chat_id = 22556
  AND r.user_id = 965
  AND r.read_at IS NULL;
```

**Bottleneck Analysis:**
* In the baseline database, locating messages for group 22556 required a **full sequential scan of all 120,000 rows** in `messages`.
* Baseline execution time averaged **11.968 ms** (or 8.852 ms in 5-run tests), reading 1,291 message heap blocks.

**Optimization (Index + Sargable Rewrite):**
* Supported by the B-tree index on `messages(chat_id)` / `messages(chat_id, sent_at DESC)`.
* Rewrote the update using an explicit subquery:
  ```sql
  UPDATE message_receipts r
  SET read_at = TIMESTAMPTZ '2026-07-01 09:05:00+05:30',
      delivered_at = coalesce(r.delivered_at, TIMESTAMPTZ '2026-07-01 09:05:00+05:30')
  WHERE r.user_id = 965
    AND r.read_at IS NULL
    AND r.message_id IN (
        SELECT m.message_id
        FROM messages m
        WHERE m.chat_id = 22556
    );
  ```
* **Performance Impact:**
  * Avoids scanning 120,000 message rows; uses a Bitmap Index Scan on `idx_messages_chat_id` and an index scan on `message_receipts(user_id) WHERE read_at IS NULL`.
  * Execution time dropped from 11.968 ms to **0.85 ms (>92% improvement)**.
  * Correctness confirmed: updates exactly 14 unread message receipts.

---

### 3.3 W03 — Delete Message for Everyone

```sql
UPDATE messages
SET is_deleted = TRUE, body = NULL, media_id = NULL
WHERE message_id = 119989;
```

**Analysis:**
* Targets a single message by primary key.
* The plan performs an Index Scan on `messages_pkey` (3 shared buffer hits) and updates the tuple in-place.
* Execution time is **~0.28 ms**.
* Because our added indexes do not index `body` or `is_deleted` as B-tree keys, this update does not incur secondary index re-indexing.

---

### 3.4 W04 — Broadcast Delivery Receipt Batch Insert

```sql
INSERT INTO message_receipts (message_id, user_id)
SELECT 1, g
FROM generate_series(2, 5001) AS g
ON CONFLICT (message_id, user_id) DO NOTHING;
```

**Analysis & Write Concurrency Trade-Off:**
* Inserts 5,000 receipts in a single statement.
* Baseline execution takes ~34–38 ms.
* Breakdown of execution cost:
  * Foreign key trigger `fk_receipts_message`: verified 5,000 times against message 1.
  * Foreign key trigger `fk_receipts_user`: verified 5,000 times against `users(user_id)`.
  * Index insertion into `message_receipts_pkey` for 5,000 rows.
* **Crucial Architectural Lesson:** If a full secondary index were added on `message_receipts(message_id, delivered_at, read_at)`, W04 would be forced to perform an additional 5,000 B-tree index page writes. By ensuring any receipt index is strictly partial (e.g., `WHERE read_at IS NULL` or `WHERE delivered_at IS NULL`), we protect bulk broadcast ingestion performance.

---

### 3.5 W05 — User Leaves Group

```sql
UPDATE chat_members
SET left_at = TIMESTAMPTZ '2026-07-01 10:00:00+05:30'
WHERE chat_id = 20898 AND user_id = 965 AND left_at IS NULL;
```

**Analysis:**
* Direct update on `chat_members` using the composite primary key `(chat_id, user_id)`.
* Plan uses an Index Scan on `chat_members_pkey`, executing in **~0.12 ms**.
* Retained as optimal.

---

## 4. Summary of Index & Statistics Additions

The table below summarizes the indexes and statistics added in `sql/05_indexes.sql` specifically supporting this workload:

| Object Name | Object Type | Target Table / Columns | Supported Queries | Storage Size | Rationale |
|---|---|---|---|---:|---|
| `idx_devices_inactive_web_desktop` | Partial Covering Index | `devices (last_active_at) INCLUDE (...) WHERE device_type IN ('WEB', 'DESKTOP')` | R23 | 496 kB | Provides pre-sorted index-only scan with 0 heap fetches for inactive device cleanup. |
| `idx_messages_chat_id` | B-tree Index | `messages (chat_id)` | W02 (and chat reads) | 1,304 kB | Accelerates chat message lookups and prevents 120,000-row table scans during unread updates. |
| `stats_messages_hour_type` | Multivariate Extended Statistics | `messages ((EXTRACT(HOUR FROM sent_at)), message_type)` | R20 | ~8 kB | Fixes planner cardinality estimation from 120,000 to 144, replacing external disk sort with in-memory HashAggregate. Zero write penalty. |

---

## 5. Correctness Verification

All query rewrites were verified for strict semantic equivalence against the baseline database:

1. **R22 (Late Row Lookup Pagination):**
   * Verified by running a two-way `EXCEPT ALL` comparison between the baseline `OFFSET 100000 LIMIT 25` query and the optimized deferred join query:
     ```sql
     ( <baseline_query> ) EXCEPT ALL ( <optimized_query> );  -- Returns 0 rows
     ( <optimized_query> ) EXCEPT ALL ( <baseline_query> );  -- Returns 0 rows
     ```
   * Result: Exactly 0 differing rows. The 25 messages, order, and projected attributes match 100%.

2. **W02 (Targeted Unread Receipt Update):**
   * Tested inside `BEGIN ... ROLLBACK` transactions using `RETURNING`:
     * Baseline update affected rows: **14**
     * Optimized update affected rows: **14**
   * The updated message IDs and timestamp modifications are identical.

---

## 6. Conclusion & Next Steps

* **Read Workload (R20–R25):** Major wins achieved in **R22** (78.5% buffer reduction via deferred joins), **R23** (86% speedup via partial covering index), and **R20** (elimination of 2.5 MB disk spills via extended statistics). R21, R24, and R25 were verified as optimal without bloating storage.
* **Write Workload (W01–W05):** **W02** execution time dropped by >92% (from ~12 ms to 0.85 ms). Write overhead on W01 and W04 was protected by avoiding unnecessary secondary indexes on `messages` and `message_receipts`.
* **Team Coordination:** The work on R20–R25 and W01–W05 is complete, isolated, and tested. Once Adarsh pushes his completed batch for R01–R20, the team will execute the complete 30-query benchmark suite (`./benchmarks/run_benchmark.sh`) to produce the unified summary report.
