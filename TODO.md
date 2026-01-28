# TODO

## Core

- **Dedup provenance gap** - when duplicate content arrives, we warm the object but don't record the new source event. The provenance of repeated captures is lost.

- **Batch coldness recalculation** - `recalculate_coldness()` function designed but not implemented. Would allow periodic maintenance to update all coldness values.

## Tests

- **Integration tests** - current tests only check hash and schema. Need tests that actually use sqlite (ingest, dedup, coldness warming, queries).

## Extensions

- clipboard
- browser
- git
- shell history
