# Cache engineering plan

Last updated: 2026-07-27

Status: approved for implementation. This is a foreground performance and
resilience cache, not full offline synchronization.

## Outcome

Make signed-in screens feel immediate without serving another account's data,
hiding refresh failures, or polling GitLab unnecessarily:

- keep the current observable models as the in-memory cache;
- add a small account-scoped response cache under `Library/Caches`;
- show cached content immediately;
- skip the network while an entry is fresh;
- show stale content while one request revalidates it;
- preserve stale content when revalidation fails;
- make pull-to-refresh always contact GitLab;
- purge an account's cached API data on sign-out or authentication invalidation.

## Deliberate boundaries

- Cache only successful authenticated REST `GET` responses. Never cache
  mutations, authentication exchanges, errors, credentials, or authorization
  headers.
- Store the raw response body plus the safe metadata needed for decoding,
  pagination, and conditional requests. Do not add `Encodable` conformance to
  every API model solely for caching.
- Start with the first page of each collection. Later pages remain in memory.
- Use GitLab's returned `Link` URL for pagination rather than constructing
  cursors.
- Use `ETag` and `Last-Modified` opportunistically when GitLab returns them.
  Do not assume every GitLab.com or self-managed endpoint supports conditional
  requests.
- Do not add background polling, offline mutations, conflict resolution, or a
  normalized entity database.

## Architecture

The dependency path remains MV with injected services:

```text
SwiftUI view
  -> observable feature model (memory)
  -> cache-aware request loader
     -> account-scoped file response cache
     -> GitLabSessionClient (authentication, refresh, retry, network)
```

### Cache identity

Each entry is identified by:

- a cache format version;
- canonical GitLab host;
- authenticated GitLab user ID;
- HTTP method, API path, normalized query, and first-page marker.

The filename and account directory use SHA-256 digests so private hostnames and
resource paths do not appear in filenames. Credentials are never key material.

### Stored record

Each binary property-list record contains:

- raw response data;
- trusted next-page URL and total count;
- optional `ETag` and `Last-Modified`;
- stored and last-accessed dates;
- a format version.

Writes are atomic. Files use iOS data protection and live under
`Library/Caches`, so losing or pruning the cache only causes a normal reload.

### Initial policy

| Resource | Fresh window | Maximum stale fallback |
| --- | ---: | ---: |
| Home summaries | 60 seconds | 24 hours |
| Pending/done Todos | 60 seconds | 24 hours |
| Issue and merge-request lists | 2 minutes | 24 hours |
| Project lists | 5 minutes | 24 hours |
| Issue and merge-request details | 5 minutes | 24 hours |

The cache has a 25 MB total limit and evicts least-recently-used entries.
These values are injected policy, not scattered feature constants.

## Loading state contract

1. A fresh in-memory or disk value renders immediately and causes no request.
2. A stale disk value renders immediately while exactly one network request
   revalidates it.
3. A cache miss uses the existing initial loading UI.
4. A successful response atomically replaces the disk and in-memory value.
5. HTTP `304 Not Modified` refreshes the entry timestamp and retains its body.
6. A failed revalidation retains stale rows and exposes the existing inline
   recovery presentation.
7. Pull-to-refresh ignores the fresh window but still preserves content on
   failure.
8. Concurrent loads for the same account/request key share one in-flight
   request.

## Test-first implementation checklist

### Cache foundation

- [x] Write behavior tests for account isolation, fresh/stale/expired
  classification, atomic replacement, corruption recovery, purge, and LRU
  pruning.
- [x] Add immutable cache keys/records and an actor-isolated cache protocol.
- [x] Implement an in-memory cache double and protected file-backed store.
- [x] Verify no cache file or diagnostic contains a token or authorization
  header.

### Home and Projects vertical slice

- [x] Prove a cached Home section publishes before a gated request completes.
- [x] Prove a fresh Home entry skips the network.
- [x] Prove a stale Home entry survives GitLab HTTP 500.
- [x] Cache the first recent/starred Projects page and preserve pagination
  metadata.
- [ ] Inspect cached, stale, failed-refresh, and manual-refresh UI in Simulator.

### Generic paginated resources

- [x] Add cache timestamps and cache-source state to the generic paginated
  model without changing its existing pagination/cancellation behavior.
- [x] Apply the behavior to assigned Issues and both merge-request modes.
- [x] Keep later pages memory-only and clear them after a successful first-page
  replacement.
- [x] Cache issue and merge-request details while preserving saved content
  when their revalidation fails.

### Todos and mutations

- [x] Persist each state/target first-page query independently.
- [x] Preserve the current in-memory filter cache and badge derivation.
- [x] Evict affected Todo entries after successful mark-one or mark-all
  mutations so old pending items cannot reappear after relaunch.
- [x] Preserve optimistic rollback behavior when a mutation fails or cancels.

### Conditional requests and coalescing

- [x] Store response validators only from successful trusted responses.
- [x] Send `If-None-Match` or `If-Modified-Since` when revalidating.
- [x] Treat HTTP 304 as successful revalidation with the cached body.
- [x] Coalesce concurrent exact-key foreground reads without weakening task
  cancellation.

### Final verification

- [ ] Run focused tests after each slice and the complete signed suite at the
  end.
- [ ] Run Xcode static analysis and source/cache privacy scans.
- [ ] Verify cached first paint, fresh request suppression, stale fallback,
  manual refresh, relaunch, offline behavior, and sign-out purge.
- [ ] Launch and tap through affected UI on iPhone 17 Pro Simulator, inspect
  light/dark appearance, and shut the Simulator down afterward.
- [ ] Keep the work in small tested commits pushed to `master`.

## Success criteria

- A warm cached screen publishes its first meaningful content within 100 ms on
  a physical iPhone.
- A fresh cache hit makes zero GitLab requests.
- A stale hit publishes before a gated network request completes and creates
  exactly one request.
- Offline and HTTP 5xx revalidation failures retain cached content.
- Pull-to-refresh always attempts one request.
- No data crosses host/user boundaries.
- Sign-out and invalid authentication remove the account cache.
- Cache corruption or format changes never crash or block a network reload.
- The cache remains at or below 25 MB after pruning.

## Official GitLab contracts

- [REST API pagination](https://docs.gitlab.com/api/rest/#pagination)
- [Polling with ETag caching](https://docs.gitlab.com/development/polling/)
- [Issues API](https://docs.gitlab.com/api/issues/)
- [Merge requests API](https://docs.gitlab.com/api/merge_requests/)
- [Projects API](https://docs.gitlab.com/api/projects/)
- [To-Do List API](https://docs.gitlab.com/api/todos/)
