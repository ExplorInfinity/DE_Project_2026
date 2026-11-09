# Baseline Timings

## Method

The 25 read queries (`R01`–`R25`) and 5 write queries (`W01`–`W05`) were run with `EXPLAIN (ANALYZE, BUFFERS)` against the seed database. Each query was run three times. Write queries were executed inside `BEGIN; ... ROLLBACK;`, so the data was not changed.

The baseline database contains only the indexes automatically created by primary-key and unique constraints. No tuning indexes were added. Timings are in milliseconds and were taken from the raw plan files in `benchmarks/results/baseline/`.

## Timing table

| Query | Type | Description | Run 1 | Run 2 | Run 3 | Average |
|---|---|---|---:|---:|---:|---:|
| R01 | READ | Chats screen: latest message for user 965 | 33.554 | 21.521 | 20.601 | 25.225 |
| R02 | READ | Latest 50 messages in group 22556 | 3.690 | 4.586 | 5.433 | 4.570 |
| R03 | READ | Unread badge counts for user 965 | 68.339 | 15.117 | 13.223 | 32.226 |
| R04 | READ | Search messages containing “meeting” | 26.145 | 21.217 | 19.449 | 22.270 |
| R05 | READ | Phone-number registration lookup | 0.025 | 0.021 | 0.020 | 0.022 |
| R06 | READ | Last seen for direct-chat contacts | 2.864 | 2.799 | 3.783 | 3.149 |
| R07 | READ | Current members of group 22556 | 0.554 | 0.649 | 0.705 | 0.636 |
| R08 | READ | Undelivered receipts before the cutoff | 33.597 | 21.541 | 18.391 | 24.510 |
| R09 | READ | Top 20 users by uploaded media size | 11.633 | 11.893 | 11.157 | 11.561 |
| R10 | READ | Daily active senders in June 2026 | 10.662 | 10.127 | 10.434 | 10.408 |
| R11 | READ | Missed calls received by user 965 | 8.143 | 6.326 | 7.864 | 7.444 |
| R12 | READ | Users forwarding at least two messages per day | 7.460 | 8.230 | 9.351 | 8.347 |
| R13 | READ | Unanswered questions in group 20501 | 31.141 | 25.409 | 21.841 | 26.130 |
| R14 | READ | Groups with the most distinct June senders | 6.935 | 6.697 | 7.849 | 7.160 |
| R15 | READ | Block check between users 3064 and 17793 | 0.022 | 0.019 | 0.063 | 0.035 |
| R16 | READ | Readers of message 119989 | 0.209 | 0.305 | 0.273 | 0.262 |
| R17 | READ | Average send-to-read time by message type | 37.493 | 24.421 | 22.232 | 28.049 |
| R18 | READ | Inactive users still in groups | 22.501 | 18.983 | 16.979 | 19.488 |
| R19 | READ | Group health: last message and June count | 14455.484 | 14583.903 | 14656.592 | 14565.326 |
| R20 | READ | Messages per hour by message type | 40.166 | 38.979 | 37.404 | 38.850 |
| R21 | READ | Edited/deleted share by message type | 10.913 | 10.851 | 11.195 | 10.986 |
| R22 | READ | Page 4,001 of newest messages | 8.339 | 8.470 | 9.213 | 8.674 |
| R23 | READ | Stale WEB/DESKTOP devices | 3.641 | 3.539 | 3.438 | 3.539 |
| R24 | READ | Duplicate media by SHA-256 | 8.260 | 9.988 | 12.029 | 10.092 |
| R25 | READ | Reply chain from message 119989 | 0.188 | 0.171 | 0.239 | 0.199 |
| W01 | WRITE | Insert a text message in group 22556 | 3.509 | 2.695 | 2.682 | 2.962 |
| W02 | WRITE | Mark user 965's unread group messages as read | 15.327 | 11.009 | 9.567 | 11.968 |
| W03 | WRITE | Delete message 119989 for everyone | 0.295 | 0.382 | 0.496 | 0.391 |
| W04 | WRITE | Insert 5,000 broadcast receipts | 54.387 | 32.667 | 26.868 | 37.974 |
| W05 | WRITE | User 965 leaves group 20898 | 0.153 | 0.119 | 0.112 | 0.128 |
| **Total of query averages** |  |  |  |  |  | **14,922.581** |

The total is the sum of the 30 individual average execution times, not one combined transaction.

## Scan types and baseline observations

| Query | Scan type(s) | Why it is slow or fast in the baseline |
|---|---|---|
| R01 | Index scans on `chat_members` and `chats`; sequential scan on `messages` | User/chat lookup is indexed, but finding the latest message for each chat repeatedly scans messages. |
| R02 | Sequential scan on `messages` | The query filters one chat but has no index on `(chat_id, sent_at)`. |
| R03 | Sequential scan on `message_receipts`; primary-key lookup on `messages` | Receipt filtering by user/read state has no supporting index. |
| R04 | Sequential scan on `messages`; index-only scan on `chat_members` | The leading-wildcard `ILIKE '%meeting%'` cannot use a normal B-tree index. |
| R05 | Index scan using the unique phone index | Exact lookup on the unique `phone_e164` column is highly selective. |
| R06 | Index scans on primary keys and `chat_members` | The user and chat joins are selective and use existing key indexes. |
| R07 | Index scans on `chat_members` and `users` | A single group lookup returns a small member set. |
| R08 | Sequential scans on `messages` and `message_receipts` | The delivery filter combines receipt state with message time without a composite index. |
| R09 | Sequential scan on `media` | The report aggregates most media rows, so the baseline reads the table. |
| R10 | Sequential scan on `messages` | Date filtering and grouping by sender require scanning message history. |
| R11 | Sequential scan on `calls`; index-only scan on memberships | Calls are filtered by status/time without a call-supporting index. |
| R12 | Sequential scan on `messages` | Forwarding is grouped by user and date across the message table. |
| R13 | Sequential scan on `messages` | The report checks message text and reply relationships for one group. |
| R14 | Sequential scans on `messages` and `chats` | June filtering and distinct-sender aggregation read substantial portions of both tables. |
| R15 | Index-only scan on `blocked_users` primary key | The composite key directly supports the two-user block lookup. |
| R16 | Index scans on receipt primary key and `users` primary key | A single message ID is highly selective. |
| R17 | Sequential scans on `message_receipts` and `messages` | The analytics query joins and aggregates a large June receipt/message set. |
| R18 | Sequential scans on `chat_members`, `chats`, and `users` | The inactive-user/group report checks several broad conditions and joins. |
| R19 | Sequential scans on `chats` and `messages` | The query computes a result for every group and repeatedly evaluates message history; it is the dominant baseline bottleneck. |
| R20 | Sequential scan on `messages` | Hour and type aggregation requires reading the message table. |
| R21 | Sequential scan on `messages` | The report calculates aggregate shares over message types. |
| R22 | Primary-key index scan on `messages` | The ordering uses the primary key, making the page lookup efficient on this dataset. |
| R23 | Sequential scan on `devices` | The stale-device predicate has no supporting index. |
| R24 | Sequential scan on `media` | Duplicate detection groups by SHA-256 across the media table. |
| R25 | Primary-key index scan on `messages` | The recursive reply lookup starts from one indexed message ID. |
| W01 | No scan node | The insert is small; its main cost is constraint and row insertion work. |
| W02 | Sequential scan on `messages`; primary-key index scans on receipts | The update locates messages by chat without a chat/time index. |
| W03 | Primary-key index scan on `messages` | The target message is found directly by its primary key. |
| W04 | No scan node | The cost is dominated by inserting 5,000 receipt rows and checking uniqueness. |
| W05 | Primary-key index scan on `chat_members` | The composite membership key directly locates the row to update. |

## Key baseline findings

- R19 is the clear bottleneck at **14,565.326 ms average**, representing approximately 97.6% of the total average time.
- The next slowest reads are R20 at 38.850 ms, R03 at 32.226 ms, R17 at 28.049 ms, and R13 at 26.130 ms.
- Exact primary-key and unique-key lookups are already fast, especially R05, R15, R16, R22, R25, and W05.
- Most report and search queries use sequential scans because they aggregate a large portion of a table or use filters that are not supported by the automatic primary-key/unique indexes.
- R03 has high run-to-run variation because its first run took 68.339 ms while the later runs were 15.117 ms and 13.223 ms; the average reported here is the arithmetic mean of all three runs.

