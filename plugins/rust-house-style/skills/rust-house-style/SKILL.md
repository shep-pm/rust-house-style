---
name: rust-house-style
description: Use when writing, reviewing, or refactoring ANY Rust in a shep-pm repo: new modules, types, traits, error enums, tests, docs, Cargo.toml edits, or CI config.
---

# Rust house style

**REQUIRED READING before writing code: `${CLAUDE_PLUGIN_ROOT}/docs/rules.md`**: 48 numbered rules (IR-1..IR-48), the maintainer's own style rather than a claim about idiomatic Rust. Cite rules by number in reviews. Evidence: `${CLAUDE_PLUGIN_ROOT}/docs/lenses/`.

**Then read the repo's addendum, if it has one: `docs/rust-house-style-addendum.md`** at the repository root. It holds the repo's own specifics and exceptions, and it wins where it disagrees with the rules.

## Baseline-failure checklist

These are the rules agents violate when writing "good" Rust from instinct. Check every one before returning code:

| Check | Rule |
|---|---|
| NO panicking constructors outside binary crates: return `Result`, even in `const fn` (drop constness or take pre-validated input) | IR-21 |
| `impl core::error::Error`, never `std::error::Error` | IR-19 |
| Every `Result`-returning pub fn has an `# Errors` doc section | IR-28 |
| `# Panics` doc and `#[track_caller]` travel together, never one without the other | IR-21 |
| Error enums: per-module, variant docs state the precise *condition* | IR-18, IR-19 |
| unsafe confined to one module per crate, `// SAFETY:` per block | IR-22, IR-23 |
| Secret/env-carrying types: manual redacted `Debug` + exact-string test | IR-41 |
| Tests: paused tokio clock default, no sleeps, hand-rolled fakes, unique fixtures per test | IR-33, IR-34 |
| Wire-facing type changed → stability fixtures + CHANGELOG | IR-35, IR-45 |
| New dep: `default-features = false`; new feature: additive + `# Option:` comment | IR-2, IR-3 |
| `#[must_use]` only where discarding is a plausible bug | IR-17 |
| Don't widen accepted input formats beyond the spec (no bonus unit spellings, no lenient whitespace) without a spec basis | spec fidelity |
| Comments say only what the code cannot: no history, no rejected alternatives, no paraphrase; `//` under four lines, `///` under twelve | IR-47 |
| No `.rs` file over 1000 lines; a change that grows one past 500 weighs a split first and the PR says which option it took | IR-48 |
