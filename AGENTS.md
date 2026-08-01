# Cue Agent Instructions

## Persistent-data compatibility contract

This contract applies to every change made by an agent or developer. Any change
that affects user-data locations, `UserDefaults` keys, persisted formats,
schemas, or deletion behavior must update this file, migration code, fixtures,
and tests together.

### Stable identities

- The bundle identifier is permanently `io.github.haotzops.cue-notchpad`.
- Settings remain in the `UserDefaults` domain for that bundle identifier.
- The API-key file remains at `~/Library/Application Support/Cue Notchpad/config.json`.
- The Usage archive key is `cueUsageArchive.v1` in that same `UserDefaults` domain.

### Ownership and deletion

Settings, API keys, and Usage belong to the user. Cue must not delete, clear,
shorten, or overwrite them without an explicit user action.

- `UserDefaults.register(defaults:)` may provide only missing defaults; it must
  not reset user values.
- Usage is append-only history. Archiving may copy or relocate data, but must
  not delete history.
- Removing an API key must be an explicit UI action and may remove only the
  API-key field.
- A migration, capacity limit, or retention policy must never delete user data.

### Schema evolution

- Every structured persisted format needs an integer `schemaVersion`.
- A schema may add optional/defaulted fields, but must not rename, remove, or
  change the meaning of existing fields.
- Migrations must be ordered, idempotent, atomic, and retain recoverable source
  data before changing it.
- A whole-document store with a newer unsupported schema is read-only: it may
  read known data but must never write back and overwrite unknown data.
- `UserDefaults` settings use independent stable keys; a newer schema must never
  reset, delete, or rewrite the whole domain.
- Rewriting supported JSON documents must preserve unknown fields.

### Required verification

For every persistent-format change:

1. Add or update a fixture under `Tests/Fixtures/Persistence/`.
2. Add tests for reading every supported fixture, preserving unknown fields, and
   refusing to overwrite a future schema.
3. Run `make test`, `swift build`, and `git diff --check`.
4. Treat edits involving `UserDefaults`, `Application Support`, `JSONEncoder`,
   `JSONDecoder`, `removeObject`, `removeItem`, bundle identifiers, or
   persistence keys as compatibility-sensitive and review them against this
   contract before committing.
