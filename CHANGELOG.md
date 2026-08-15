# Changelog

## 0.1.0

- Add immutable uniform-grid indexing for two-dimensional worlds.
- Add AABB, circle, and swept-circle broad-phase queries.
- Add deterministic layer filtering and batch updates.
- Add exhaustive-scan comparison benchmarks.
- Add a supervised `Grid2D.Server` for serialized partition-owned indexes.
- Add optional ECS query sources and incremental change-set indexing.
- Add deterministic whole-index and layer candidate sources without geometry scans.
- Add incremental observer/entity interest graphs and deterministic membership deltas.
- Add swept-trajectory recipient routing across multiple cells.
- Add a serialized interest-graph server compatible with existing grid entity operations.
