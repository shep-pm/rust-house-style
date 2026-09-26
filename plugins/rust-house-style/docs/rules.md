# Rust house style

The maintainer's rules for Rust in shep-pm repos. One person's house style,
not a claim about what idiomatic Rust is.

Numbered rules, cited as `IR-<n>` in reviews. The evidence, with file:line
citations from a deep read of `rand` 0.10.2, lives in [lenses/](lenses/)
(api, docs, testing, rigor). This doc is the contract; the lenses are the
proof.

A repo's own specifics and exceptions live in its addendum,
`docs/rust-house-style-addendum.md`. Where the addendum and this doc
disagree, the addendum wins for that repo.

Priority when rules collide: **Readability > KISS > DRY** (the maintainer's
global order).

## A. Workspace & Cargo

- **IR-1** Shared config in `[workspace.package]` / `[workspace.dependencies]` /
  `[workspace.lints]`; every crate opts in (`lints.workspace = true`). rand
  predates workspace lints — we use the modern equivalent of its discipline.
- **IR-2** Every dependency `default-features = false` + enumerate needed
  features. Dev-deps too, with purpose comments (`# Only to test serde`).
- **IR-3** Features: additive only, compose upward (`otel = ["metrics", ...]`),
  optional deps via `dep:`, weak deps via `serde?/derive`. Every feature line
  carries a `# Option:` / `# Option (enabled by default):` comment stating its
  consequence. Never a feature that removes behavior. Gate convenience layers,
  never core trait/type definitions.
- **IR-4** Each publishable crate: `rust-version` (the repo's MSRV), `include =
  [...]` slim list, `[package.metadata.docs.rs]` with `all-features = true` +
  `--generate-link-to-definition` + the local repro command as a comment.
- **IR-5** Benches: separate unpublished crate (`publish = false`, own
  `[workspace]`), criterion `harness = false`, deterministic fixtures inside,
  `black_box` in/out, CI compiles+runs them so they never rot.

## B. Lints

- **IR-6** Workspace denies: `missing_docs`, `missing_debug_implementations`,
  `clippy::undocumented_unsafe_blocks`. Each lib.rs adds
  `#![doc(test(attr(deny(warnings))))]` — doctests rot loudly.
- **IR-7** `#![forbid(unsafe_code)]` in every crate that has no unsafe. A crate
  that needs unsafe (nix/libc calls) uses `deny` and confines it — see IR-22
  and IR-24.
- **IR-8** `#[allow]` only at the narrowest scope (fn/block), enumerated lint,
  one-line reason comment. Never file- or crate-wide without justification.
- **IR-9** `clippy.toml`: `doc-valid-idents` lists the repo's domain words
  (`"PID"`, `"SIGKILL"`, `"systemd"`) — keep `..` to preserve defaults;
  comment says why.

## C. API design

- **IR-10** Two-layer traits: minimal dyn-safe core trait + blanket ext trait
  whose methods are ALL defaulted (`impl<T: Core + ?Sized> Ext for T {}`).
  Generic fns take `&mut T where T: Core + ?Sized`. Pin dyn-compat with a
  `&mut dyn Core` smoke test.
- **IR-11** Newtypes pin public contracts (`MemSize(u64)`, `ProcessId(u32)`,
  `AuthToken`); forwarding methods are `#[inline]` one-liners. A `// wire
  format: changing this is a breaking change` comment on every wire-facing type.
- **IR-12** Conversions: `From` only when infallible; `TryFrom` with a typed
  error otherwise (`"512M".try_into()` → `Result<MemSize, ParseMemSizeError>`).
  Never a panicking `From`.
- **IR-13** Assoc type when exactly one impl per type (`Request::Response`);
  generic param when many. Typed RPC: each request type registers its response
  type once, in the crate that owns the wire types — mismatch is a compile
  error, not a decode error.
- **IR-14** Natural-input traits at API edges (rand's `SampleRange`): selectors
  accept `impl IntoSelector` so `restart("web")`, `restart(ProcessId(3))`,
  `restart(All)` all read naturally. Implement only where meaningful.
- **IR-15** Storable iterators/streams are NAMED public structs (honest
  `size_hint`, `FusedStream` where true); `-> impl Stream` only for one-off
  views. `PhantomData<fn() -> T>` for variance-neutral phantoms.
- **IR-16** Renames ship a `#[deprecated(since, note = "Renamed to `x`")]`
  delegating shim for one release. No silent breaks.
- **IR-17** `#[must_use]` only where discarding is a plausible bug; intentional
  discards written `let _ =`.

## D. Errors

- **IR-18** Small per-module error enums named for their construction site
  (`SpawnError` beside the spawn code, `ConnectError` in the client,
  `ProtocolError` in the crate that owns the wire types). No crate-wide
  mega-enum; no `anyhow` outside binary crates.
- **IR-19** Shape: derive `Debug, Clone, PartialEq, Eq` (+ `Copy` when
  fieldless); per-variant doc = the precise condition ("stale socket file"),
  not the name restated; manual `Display` via `f.write_str(match ...)`;
  `impl core::error::Error`. Variants wrapping `io::Error` implement `source()`
  and drop `Copy`/`Eq` for that enum only.
- **IR-20** `#[non_exhaustive]` only where growth is anticipated, with a
  comment citing why (`ProtocolError`: wire will grow). It taxes downstream
  matching — don't cargo-cult it. The default that settles the usual case: a
  `pub` error enum in a LIBRARY crate gets it, because an out-of-tree consumer
  can match exhaustively and a new variant would break them with no version
  bump to say so. A `pub` error enum in a binary crate does not. The same holds
  for a crate whose library target exposes only a few entry points and keeps
  every module private: no error enum it defines is externally reachable, so
  the attribute would guard a match no one outside the crate can write. The
  rule still holds; only the reason changed. Either way the comment is
  mandatory. Every wire enum gets it unconditionally, and so does a wire
  STRUCT that will grow.
- **IR-21** Constructors return `Result`, validation-first with early returns.
  Panicking conveniences exist only in binary crates, carry `#[track_caller]` +
  `# Panics` doc (the two travel together, one commit), and panic messages
  include the offending value.

## E. Unsafe

- **IR-22** All unsafe confined to one module per crate (`sys.rs` by
  convention); everything else calls its safe wrappers.
- **IR-23** Every block: `// SAFETY:` stating the exact invariant, repeated
  verbatim at each site (no "see above"). Pair with `debug_assert!` of the
  invariant when checkable.
- **IR-24** Choosing unsafe over a safe alternative requires a rationale essay
  next to the code: rejected alternative, its measured cost, the invariant, the
  failure scenarios considered and why each can't happen (rand's
  UnsafeCell-vs-RefCell essay is the model).

## F. Performance annotations

- **IR-25** `#[inline(always)]`: trivial forwarding on the per-frame/per-byte
  hot path only. `#[inline]`: small hot fns + cheap constructors crossing crate
  boundaries. `#[cold] #[inline(never)]`: rare paths reached from hot loops
  (protocol-error construction, reconnect, rotation trigger) — hot fn does one
  compare and calls the cold fn; panics/format machinery live in the cold fn.
- **IR-26** Every tuning threshold is a named const with a benchmark-backed
  comment including unit conversion (rand's `RESEED_BLOCK_THRESHOLD` model).
  No inline magic numbers.

## G. Docs

- **IR-27** Crate doc = summary + `# Quick start` with ONE example + links out.
  Module docs are decision guides ("which restart policy when"), not API dumps:
  noun-phrase title (no period), h2 sections, h5 taxonomy sub-groups,
  definition-bullets with honest caveats inline, ALL links in a bottom
  reference block.
- **IR-28** Item-doc section order: summary fragment (no period) → prose/
  See-also → `# Example` → `# Errors` (mandatory for Result fns) → `# Panics`
  (iff it can) → domain section (`# Cancellation safety`, `# Security`) → link
  block. Thin wrappers doc as "shorthand for <code>[X].[y]</code>" — no
  duplicated behavior text.
- **IR-29** ONE canonical `# Security` writeup (on the type that owns the
  boundary, such as the daemon or socket type), anchor-linked from everywhere
  else. Design-criteria bullets + explicit non-goals.
- **IR-30** Doctests: `no_run` default for anything daemon-touching (hidden
  `# #[tokio::main]` wrapper lines); `ignore` only when it can't compile
  in-crate, with prose explaining; edge cases as asserted doctests with
  verdict comments on pure logic (config parse, backoff math) — those run in
  CI. Show the better pattern proactively ("reuse one Client").
- **IR-31** Implementation rationale = `//` block comments above the item,
  never `///`. Rendered docs are for users; essays are for maintainers.
- **IR-32** `#[cfg(doc)] use` for link-only imports; `#[doc(inline)]` on
  curated re-exports; `#[doc(hidden)]` + `// used by <crate>` comment for
  workspace-internal surface. Third-party re-exports normalized under our
  namespace (`Error as SysError`).

- **IR-47** A comment says only what the code cannot: an invariant, a
  non-obvious why, a caller constraint, a platform caveat, a number's basis.
  Never history (dates, "used to", "until", phase numbers), never a rejected
  alternative, never a review argument, never a paraphrase of the next line.
  Git history holds all of that. Shape: `//` one or two lines, four at most;
  `///` one summary fragment plus at most six lines of body, twelve counting
  `# Errors`; `//!` three to ten lines. No em dashes, no capitals for
  emphasis, sentences at sixteen words or fewer. A test whose name is a
  sentence needs no doc line. Match the project's own rate: about one prose
  comment line per commit is the maintainer's measured habit, not ten.

## H. Testing

- **IR-33** One crate-root `#[cfg(test)] mod test` fixture module per crate
  with a WHY comment at each factory. Async tests default to a paused clock
  (`#[tokio::test(start_paused = true)]`); real time needs a justifying
  comment. Fakes are hand-rolled against the real traits, in tiers where that
  helps (a `const_proc(exit)` fake beside a `script_proc(vec![...])` one). No
  mocking frameworks.
- **IR-34** Unique scenario per test: own config literal, own tempdir, own
  seed. No shared mutable fixture state.
- **IR-35** Wire stability = our value-stability: insta snapshots of every
  request/response/event serialized form, PLUS committed byte-fixtures from
  the previous protocol version that must still deserialize. Breaking one is a
  protocol-version bump + CHANGELOG entry, never a silent snapshot re-accept.
- **IR-36** Deterministic-sequence tests: paused clock + scripted fake →
  assert the EXACT restart instants/backoff delays as a pinned array.
- **IR-37** Property tier: proptest on state machines (random event
  interleavings uphold invariants: never two live PIDs per unit, restart
  count monotonic, always reaches steady state). Explicit bounds; case count
  capped in CI via env.
- **IR-38** `tests/` dir = at most one compile-only file per crate proving an
  external crate can implement the public trait (`todo!()` bodies fine).
  Everything behavioral is co-located `#[cfg(test)]`.
- **IR-39** E2E tier (CLI crates): `assert_cmd` + a fresh temp home directory
  per test + serde asserts on JSON output + insta snapshots of normalized
  stdout. No sleeps — event-driven waits with timeouts. Errors derive
  `PartialEq` so tests assert exact variants.
- **IR-40** Boundary sweeps as a habit: wire framing tested at every partial-
  read length around the header size; state machines at 0/1/max entries;
  empty/defaulted configs.
- **IR-46** Every `await` in a test needs a FORCING MECHANISM — something that
  makes it resolve, or makes it fail, within a bound the test itself sets. Two
  failure shapes this catches, both found in five separate phases: an await
  nothing will ever resolve (the test hangs, and a hang reports as a timeout
  minutes later with no diagnostic), and an await that resolves on a state the
  test was not waiting for (`await_status(Online)` satisfied by the state
  BEFORE the crash under test — a vacuous pass, which is worse than a hang
  because it is green). Concretely: wrap the wait in `tokio::time::timeout`
  and assert on the result, or wait for a transition rather than a state, or
  drive a paused clock past the point the thing must have happened by. "The
  test passes locally" is not a forcing mechanism; neither is the harness's
  own process timeout, which fails the whole binary and names nothing.

## I. Security-sensitive types

- **IR-41** Any type carrying env vars, tokens, or secrets: manual redacting
  `Debug` (`AuthToken { .. }`, env values elided) with doc note "Debug does not
  leak X" + an exact-string unit test with the reason commented — a lazy
  `derive(Debug)` refactor must fail CI.
- **IR-42** SECURITY.md as an if/then premises contract: preconditions (runtime
  dir 0700, daemon unprivileged, unix-socket only) → guaranteed properties (no
  cross-user control, tokens never in logs/Debug/RPC), per-component sections,
  explicit non-goals ("root can always read daemon memory"), supported
  versions, private reporting window. It matters most where a socket or
  service is a privilege boundary.

## J. CI & release

- **IR-43** Jobs: clippy PINNED to a specific toolchain with `-D warnings`
  (bump the pin deliberately in a PR), fmt on stable, docs on nightly with
  `-Dwarnings --cfg docsrs`, typos, weekly cron for drift. `permissions:
  contents: read` on all workflows; `fail-fast: false` on the matrix.
- **IR-44** Matrix: each OS the repo ships on × {stable, MSRV} + one beta row;
  nightly `-Z minimal-versions` row keeps dep lower bounds honest; a musl
  target that ships as a deployment artifact RUNS tests (our "big-endian
  row"), aarch64-musl build-only. Feature-combo ladder per crate:
  `--no-default-features`, each feature singly, `--all-features`. miri only
  if a crate grows real unsafe — no cargo-cult.
- **IR-45** Release: tag-triggered crates.io Trusted Publishing (OIDC,
  `id-token: write`, no stored token). Keep-a-Changelog per publishable crate:
  permanent `[Unreleased]`, sections `Security and unsafe / Fixes / Changes /
  Additions / Removals / Deprecated`, imperative entries, renames spelled
  `old` -> `new`, every line ends `([#NN])`, wire-version bumps called out.

## K. Code layout

- **IR-48** File size. Count every line in a `.rs` file, tests and comments
  included. Generated files are exempt. Under 500 lines, nothing to do. From
  500 to 1000 lines a file is allowed, but a change that grows a file past 500
  lines weighs a split first, and the PR says which option it took and why.
  Over 1000 lines is not allowed, even when a single function is the cause: a
  function that long has a separation-of-concerns problem to solve. A split is
  a new module or several files within the current module; the author
  chooses. Moving a file's inline test module into a file of its own is not a
  split: tests sit beside the code they cover, and move with it when it moves.
  Try, in order:
  1. Reduce. Find duplication and remove it (the duplicate-detection skills,
     where installed).
  2. Separate concerns. Move logic into smaller units that can each be tested
     on their own.
  3. Split by type definitions, only when 1 and 2 are not enough, still
     grouped by concern, so no file ends up holding one trivial struct.
  Aim for files of roughly even size. Everything else is judgement.

  The reusable workflow in this repo (`.github/workflows/file-size.yml`)
  enforces the 1000-line limit mechanically. The rest is review.

## PR checklist (paste into reviews)

```
[ ] deps default-features=false, features commented + additive     (IR-2,3)
[ ] no new panicking constructor outside binary crates             (IR-21)
[ ] error enums: per-module, variant docs = conditions             (IR-18,19)
[ ] unsafe in one module per crate, SAFETY per block               (IR-22,23)
[ ] docs: # Errors on Result fns, # Panics ⇔ #[track_caller]       (IR-28,21)
[ ] secrets types: redacted Debug + exact-string test              (IR-41)
[ ] wire changes: stability fixtures updated + CHANGELOG           (IR-35,45)
[ ] tests: paused clock, no sleeps, unique fixtures                (IR-33,34)
[ ] tuning consts named + benchmark comment                        (IR-26)
[ ] new pub error enum: non_exhaustive per crate tier + why comment (IR-20)
[ ] every await in a test has a forcing mechanism, not just a hope  (IR-46)
[ ] comments say what the code cannot; no history, no argument         (IR-47)
[ ] no .rs file over 1000 lines; growing past 500 weighs a split    (IR-48)
```
