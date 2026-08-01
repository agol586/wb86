# Fixture policy

- Fixtures are versioned, deterministic, and redistribution-safe.
- Synthetic user data must be used for invalid-input, migration, privacy, and stress scenarios.
- No fixture may contain captured user input, application identity, document context, device identity,
  absolute paths, or reconstructable input timelines.
- Large fixtures must document their generator, record count, checksum, and license/provenance.
- Corrupt fixtures must identify only the fixed error category they exercise, never sensitive bytes.
