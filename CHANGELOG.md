# Changelog

## v0.1.8 - 2026-11-23

- feat(parser): bool options take yes/no, on/off and 1/0 as well as true/false (e54381a)
- feat: pass application state and diagnostics through command dispatch (9da0217)

## v0.1.7 - 2026-11-18

- fix(config): own loaded keys and values (246ef59)

## v0.1.6 - 2026-11-18

- fix(config): reject malformed TOML without panics or leaks (61263df)

## v0.1.5 - 2026-11-17

- feat: print the version for --version and -V in cli.run (f17b7da)

## v0.1.4 - 2026-11-17

- fix: keep Parser.parse and setAction compatible with zig-cli 0.1 (7e302d2)
- feat!: nested subcommands, repeatable options, exit codes and --json (19f33f5)

## v0.1.3 - 2026-07-28

- fix: support latest Zig 0.17 dev (0c2e1b1)
- docs: update Discord community links (2dd7d58)
- docs: add Community section to README (b330852)
- chore(deps): declare bun ^1.3.14 in deps.yaml (4629d10)
- ci: install zig via pantry action instead of mlugg/setup-zig (da2da47)
- chore: ignore pantry directory (1660639)
- docs: re-indent comment in example.jsonc (407abd2)
- chore(ci): bump actions/checkout to v6, actions/cache to v5 (5299c8f)
- chore: refresh bun.lock and apply pickier --fix (1cde902)
- ci: switch to mlugg/setup-zig, pin to 0.17.0-dev.56+a8226cd53 (9ec8a47)
- refactor: migrate to zig 0.17-dev APIs (50eebc9)
- chore: minor updates (b44ab9c)
- chore: update vscode config (a2f7e6b)
- chore: update vscode config (92550bf)

