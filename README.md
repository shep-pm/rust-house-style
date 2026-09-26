# rust-house-style

The maintainer's Rust house style for shep-pm repos: one person's rules, not a claim about what idiomatic Rust is.

## What's here

- `plugins/rust-house-style/docs/rules.md`: the rules, IR-1 to IR-48. Numbers stay stable because commit and review history cite them.
- `plugins/rust-house-style/docs/lenses/`: the evidence behind them, from a read of `rand` 0.10.2.
- `plugins/rust-house-style/skills/rust-house-style/`: the Claude Code skill that applies the rules.
- `.claude-plugin/marketplace.json`: a plugin marketplace with that one plugin.
- `.github/workflows/file-size.yml`: a reusable workflow that enforces the 1000-line limit from IR-48.

## Adopting the rules in a repo

1. Enable the plugin in the repo's committed `.claude/settings.json`:

   ```json
   {
     "extraKnownMarketplaces": {
       "rust-house-style": {
         "source": { "source": "github", "repo": "shep-pm/rust-house-style" }
       }
     },
     "enabledPlugins": {
       "rust-house-style@rust-house-style": true
     }
   }
   ```

   Claude Code asks each collaborator to trust the folder once, then loads the skill. Add a line to the repo's CLAUDE.md telling agents to invoke `rust-house-style` before writing or reviewing Rust.

2. Keep repo-specific rules in `docs/rust-house-style-addendum.md`. The skill reads it when it exists, and it wins where it disagrees with the rules. Use it for crate names, where unsafe is allowed, fixture names, and any rule the repo bends. Cite the rule number so a reader can find what is being changed.

3. Call the file-size workflow from CI, pinned by tag:

   ```yaml
   jobs:
     file-size:
       uses: shep-pm/rust-house-style/.github/workflows/file-size.yml@v0.1.0
       with:
         baseline: .github/rust-file-size-baseline.txt
         exclude: |
           **/generated/*.rs
   ```

   The caller needs `permissions: contents: read`.

## The file-size workflow

It counts every line of each tracked `.rs` file, including tests and comments, and fails a file over 1000 lines.

- `exclude`: generated files to skip, one git glob per line (matched with `:(exclude,glob)`). Default: none.
- `baseline`: known offenders, one `<lines> <path>` per line, `#` for comments. Default: `.github/rust-file-size-baseline.txt`. A missing file is an empty baseline.
- `ratchet`: default `false`.

A listed file may shrink but never grow: past its entry, it fails. An unlisted file fails past 1000. A listed file that shrinks passes with a notice to lower its entry, or remove it once it is at 1000 or under. Until the entry comes down, the file could grow back to the old number. Set `ratchet: true` to fail instead, which forces the entry down in the same change.

Baseline entries need a reason to exist. Put the tracking issue in a comment above them:

```
# https://github.com/shep-pm/example/issues/1
1201 crates/example/src/big.rs
```

`tests/file-size/run.sh` runs the workflow's own check step against scratch repos. `tests/rules-numbering.sh` checks that IR-1 to IR-48 each appear once.

## Releases

Tags are `vMAJOR.MINOR.PATCH`. Pin the workflow by tag, and the plugin version in `plugin.json` matches the tag.

## Licence

MIT OR Apache-2.0, at your option.
