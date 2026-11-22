# Phase 5 — Scalability and Final Submission Report

## 1. Executive summary

The optimized workload remains within every CP4 target on the supplied large
dataset. The large run contains 2,400,000 messages and 10,022,212 message
receipts, approximately 20 times the seed message volume. All 30 query
averages are below their target: the slowest real-time query is W01 at
4.741 ms, the slowest interactive query is R08 at 15.181 ms, the slowest
report query is R17 at 233.339 ms, and W04 is 474.833 ms against a 2,000 ms
batch target.

The raw plans are committed in `benchmarks/results/large/`. The optimized seed
values below come from the committed optimized summary and the large values
come from `benchmarks/results/large/summary.csv`. Each large summary value is
the arithmetic average of five captured runs; the raw plan files preserve all
five runs.

## 2. Dataset and method

| Dataset | Users | Chats | Chat members | Messages | Receipts | Media | Devices | Calls |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Seed | 30,000 | 23,000 | 104,514 | 120,000 | 501,590 | 27,634 | 42,000 | 25,000 |
| Large | 600,000 | 460,000 | 2,090,014 | 2,400,000 | 10,022,212 | 551,121 | 840,000 | 500,000 |

The large database was loaded with the project schema, tuned with
`sql/05_indexes.sql`, analyzed, and measured using the optimized workload in
`sql/06_optimized_queries.sql`. Read and write queries were run with
`EXPLAIN (ANALYZE, BUFFERS)`; writes were rolled back by the benchmark runner.

## 3. Results against CP4 targets

Growth is `large average / optimized seed average`. A `PASS` means the large
average is below the applicable CP4 target.

| Query | Seed optimized (ms) | Large (ms) | Growth | Target (ms) | Result |
|---|---:|---:|---:|---:|:---:|
| R01 | 0.686 | 0.364 | 0.53x | <5 | PASS |
| R02 | 0.551 | 0.245 | 0.45x | <5 | PASS |
| R03 | 0.713 | 0.335 | 0.47x | <5 | PASS |
| R04 | 0.688 | 0.525 | 0.76x | <250 | PASS |
| R05 | 0.105 | 0.097 | 0.92x | <5 | PASS |
| R06 | 0.536 | 0.269 | 0.50x | <5 | PASS |
| R07 | 0.361 | 0.232 | 0.64x | <5 | PASS |
| R08 | 14.524 | 15.181 | 1.05x | <250 | PASS |
| R09 | 14.023 | 217.440 | 15.51x | <5,000 | PASS |
| R10 | 3.741 | 37.586 | 10.05x | <5,000 | PASS |
| R11 | 0.454 | 0.075 | 0.17x | <250 | PASS |
| R12 | 5.567 | 32.198 | 5.78x | <5,000 | PASS |
| R13 | 0.571 | 0.037 | 0.06x | <250 | PASS |
| R14 | 7.909 | 35.600 | 4.50x | <5,000 | PASS |
| R15 | 0.079 | 0.024 | 0.30x | <5 | PASS |
| R16 | 0.303 | 0.160 | 0.53x | <5 | PASS |
| R17 | 22.553 | 233.339 | 10.35x | <5,000 | PASS |
| R18 | 15.220 | 142.969 | 9.39x | <5,000 | PASS |
| R19 | 6.653 | 116.506 | 17.51x | <5,000 | PASS |
| R20 | 21.638 | 144.270 | 6.67x | <5,000 | PASS |
| R21 | 10.520 | 75.679 | 7.19x | <5,000 | PASS |
| R22 | 5.413 | 5.512 | 1.02x | <250 | PASS |
| R23 | 0.992 | 11.590 | 11.68x | <250 | PASS |
| R24 | 15.761 | 210.416 | 13.35x | <5,000 | PASS |
| R25 | 0.240 | 0.083 | 0.35x | <5 | PASS |
| W01 | 4.855 | 4.741 | 0.98x | <5 | PASS |
| W02 | 1.433 | 0.463 | 0.32x | <5 | PASS |
| W03 | 2.746 | 2.577 | 0.94x | <5 | PASS |
| W04 | 37.452 | 474.833 | 12.68x | <2,000 | PASS |
| W05 | 0.130 | 0.063 | 0.49x | <5 | PASS |

## 4. Growth analysis

### Stayed approximately constant or sub-linear

R01–R07, R08, R11, R13, R15, R16, R22, R25, W01–W03, and W05 stayed at or
near seed latency. Their plans use primary-key, unique-key, partial, or
chat/user selective indexes. R01, R02, R03, R11, R13, and W02 continue to
use the added indexes on the large data. The amount of data outside the
requested user, chat, receipt, or status slice does not need to be read.

### Grew with the data, but remained well below target

R09, R10, R12, R14, R17, R18, R20, R21, R23, R24, and W04 process a broad
portion of a table or perform aggregation/foreign-key work. Their growth is
roughly 4.5–15.5x rather than a full 20x because the query shape, selected
columns, caching, and index-only scans reduce the amount of work. R09 and R24
correctly remain sequential media scans: both aggregate most media rows.

R19 grew 17.51x, the largest read growth, because it evaluates per-group
latest-message and June-message aggregates across 460,000 chats. It still
uses `idx_messages_chat_id_sent_at` for index-only per-chat lookups and is only
116.506 ms, far below the 5,000 ms report target.

No query grew beyond 20x and no large-data query missed its target.

## 5. What changed at scale

No scale-only correctness or target failure required a new query rewrite. The
plans show the intended access paths continuing to work:

- R01 uses `idx_chat_members_user_chat` and
  `idx_messages_chat_id_sent_at`.
- R08 uses the `sent_at` index plus the partial undelivered-receipt index.
- R13 uses the partial question index and the `reply_to_message_id` index;
  the NULL-safe `NOT EXISTS` rewrite remains correct.
- R19 uses `idx_messages_chat_id_sent_at` for both per-chat aggregates.
- R23 uses the partial covering inactive-device index with an index-only scan.
- W02 uses the unread-receipt index and chat/message lookup paths.

### R22 — deep pagination explanation

R22 requests page 4,001, which means `OFFSET 100000 LIMIT 25` when pages
contain 25 rows. The optimized query uses a deferred join:

1. An index-only scan of `messages_pkey` walks the `message_id DESC` order,
   discards the first 100,000 IDs, and returns only the next 25 IDs.
2. Those 25 IDs are joined back to `messages` to fetch the projected columns.

This preserves the original ordering and result while avoiding heap reads for
the 100,000 skipped rows. The large-data average is 5.512 ms, compared with
the 250 ms interactive target. We did not replace R22 with keyset pagination,
so there is no last-seen value to choose for the submitted implementation.

If the console later adopts keyset pagination, the cursor should be the
`message_id` of the last row returned on the previous page. The next page
would use `WHERE message_id < :last_seen_message_id ORDER BY message_id DESC
LIMIT 25`; `message_id` is unique, so it gives a stable cursor without
scanning and discarding earlier pages.

W04 is the main write-scale cost: it inserts 5,000 receipts and performs
foreign-key checks. Its five runs range from 38.373 ms to 663.986 ms, but the
average is 474.833 ms and remains below the 2,000 ms batch target. The
variability is consistent with buffer and page-write state, not a query
correctness issue.

## 6. Storage accounting

The benchmark runner records timings and plan nodes, but does not collect
`pg_database_size` or `pg_relation_size`. The committed artifacts therefore
do not contain trustworthy seed/large byte totals, and this report does not
invent them. Run the following query once in each benchmark database after
the indexes and `ANALYZE` have been applied, then paste the two result sets
into this section:

```sql
SELECT current_database() AS database_name,
       pg_size_pretty(pg_database_size(current_database())) AS database_size;

SELECT c.relname AS table_name,
       pg_size_pretty(pg_table_size(c.oid)) AS table_size,
       pg_size_pretty(pg_indexes_size(c.oid)) AS index_size,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'whatsapp'
  AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;
```

The timing evidence already identifies the likely storage drivers: the large
`messages` and `message_receipts` tables dominate row volume, while the
chat/time, receipt-status, timestamp, and device indexes trade additional
storage for the sub-250 ms interactive paths.

## 7. Architecture for 100× volume

### Partitioning

Partition `messages` by `RANGE (sent_at)`, using monthly partitions for the
hot/current period and a coarser historical bucket where appropriate. Message
history and the large analytics queries are time-oriented, so time partitions
enable pruning, make old-data archival operationally simple, and keep
vacuum/index maintenance bounded. The design DDL is in
`sql/08_partitioning.sql`.

For example, a June 2026 query should prune to the June partition:

```sql
EXPLAIN (COSTS OFF)
SELECT count(*)
FROM whatsapp.messages_partitioned
WHERE sent_at >= '2026-06-01 00:00:00+05:30'
  AND sent_at <  '2026-07-01 00:00:00+05:30';
```

The expected plan contains only the `messages_2026_06` child below the
aggregate. This is a deployment design; the current benchmark database was
not changed destructively to install it.

PostgreSQL requires every partitioned-table primary key or unique constraint
to include the partition key. Therefore the partitioned design uses
`PRIMARY KEY (message_id, sent_at)`, not the current single-column key. A
production migration must carry the message timestamp into receipt/reply
references or keep a separate non-partitioned message identity map; the
existing `message_receipts(message_id)` foreign key cannot be copied
unchanged to that partitioned parent.

### Sharding

Shard messages by `chat_id` (hash or a directory mapping), because R02 is a
single-chat history query and R19/R07 can route by chat. R01 first obtains a
user's active chat list from the membership directory and then fans out to
the relevant chat shards for the latest message. User-wide queries such as
R03, R05, R10, R17, R18, R20, and R21 become fan-out/merge operations unless
they read pre-aggregated summaries. Receipt writes should route through the
message's chat shard so message and receipt locality is preserved.

### Read replicas and caching

Send R04, R08–R14, R17–R24 to read replicas when replica lag is acceptable;
these are search, operational, reporting, and analytics reads. Keep W01–W05
on the primary. R01, R03, R15, R16, and R25 should use the primary when the
user needs read-your-write freshness, with short-lived cache entries only
when invalidation is tied to message/receipt/block updates. R05 is a good
candidate for a phone-to-user cache with privacy-safe invalidation. R02 can
use a short-lived per-chat latest-history cache, but message edits/deletes
must invalidate it.

### Maintenance

- Run `ANALYZE` after bulk loads and refresh statistics after large daily
  changes; retain the extended statistics used by R20.
- Tune autovacuum for `messages` and `message_receipts` more aggressively
  than append-only reference tables because receipts and message flags are
  updated frequently. Monitor dead tuples, vacuum lag, and index bloat.
- Archive or detach old message partitions after the retention policy allows
  it; keep a read-only archive path for compliance and historical reports.
- Refresh daily/hourly summary tables for analytics queries such as R10,
  R17, R19, R20, and R21 so 100× traffic does not require repeated full
  history scans.

## 8. Conclusion and remaining risks

The database is ready for the next 20× dataset under the supplied CP4
targets: every benchmark passes, the scale-sensitive plans remain indexed
where selective access is possible, and broad scans remain under the report
budgets. The main 100× risks are storage/index growth, receipt-update write
amplification, R19-style fan-out aggregation, and replica lag. Monthly
partitioning, chat-local sharding, replicas, and refreshed summary tables are
the recommended next architectural steps.
