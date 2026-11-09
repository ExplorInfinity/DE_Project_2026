# Problem Understanding

## Business problems and stakeholders

| Problem | Business need | Main stakeholder | Classification |
|---|---|---|---|
| P1. Slow Chats screen | Show a user's chats, latest message, and unread badges quickly. | End user / mobile app | Customer-facing, real-time |
| P2. Slow group history | Open a busy group and scroll its newest messages without delay. | End user / mobile app | Customer-facing, real-time |
| P3. Slow message search and info | Search message text and show delivery/read information quickly. | End user / mobile app | Customer-facing, real-time |
| P4. Slow registration/contact checks | Look up phone numbers, last-seen information, and block status immediately. | Identity and privacy teams | Customer-facing, real-time |
| P5. Slow pending receipts | Find undelivered messages and mark messages as read under load. | Delivery service | Real-time service |
| P6. Empty unanswered-question report | Find questions in groups that have not received a reply. | Group admins | Reporting / analytics |
| P7. Slow spam reports | Identify forwarding patterns and inspect suspicious messages. | Trust and Safety | Reporting / operational console |
| P8. Rising media storage cost | Find heavy uploaders and duplicate media for storage optimization. | Storage team | Reporting / analytics |
| P9. Slow product analytics | Measure activity, read time, edits, deletes, group engagement, and hourly volume. | Product and growth analytics | Reporting / analytics |
| P10. Slow security clean-up | Find stale devices, inactive users, missed calls, and users leaving groups. | Security and platform teams | Operational / scheduled jobs |

## Assumptions

- A user is soft-deleted by changing `users.status` to `DELETED`; the user row and historical references remain available.
- Historical messages, calls, media ownership, receipts, and membership records should retain their user IDs.
- A direct chat has exactly two members; a group has at least three members in the supplied export.
- A chat creator is stored in `chats.created_by`; a message sender is stored separately in `messages.sender_id`.
- `message_type` is broader than `media_type`: text and location messages do not require media, while a referenced media row must have the matching media type.
- Empty CSV fields represent SQL `NULL`, not empty strings.
- Timestamps include a time-zone offset and are stored as `TIMESTAMPTZ`.
- The baseline database will contain only indexes created automatically by primary-key and unique constraints. Performance indexes are deferred to the optimization phase.
