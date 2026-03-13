# Claude Code Guidelines

## About

zig-cli is a type-safe, compile-time validated CLI framework for Zig 0.16+. Define CLI options as structs and get auto-generated flags, compile-time field validation, and full IDE autocomplete with zero runtime overhead. The library includes interactive prompts (text, select, multi-select, password, number, path, confirm, spinner, progress bars), ANSI color/style chaining, table and box rendering, a middleware system for command hooks, and configuration file loading from TOML, JSONC, and JSON5 with type-safe schema validation.

## Linting

- Use **pickier** for linting — never use eslint directly
- Run `bunx --bun pickier .` to lint, `bunx --bun pickier . --fix` to auto-fix
- When fixing unused variable warnings, prefer `// eslint-disable-next-line` comments over prefixing with `_`

## Frontend

- Use **stx** for templating — never write vanilla JS (`var`, `document.*`, `window.*`) in stx templates
- Use **crosswind** as the default CSS framework which enables standard Tailwind-like utility classes
- stx `<script>` tags should only contain stx-compatible code (signals, composables, directives)

## Dependencies

- **buddy-bot** handles dependency updates — not renovatebot
- **better-dx** provides shared dev tooling as peer dependencies — do not install its peers (e.g., `typescript`, `pickier`, `bun-plugin-dtsx`) separately if `better-dx` is already in `package.json`
- If `better-dx` is in `package.json`, ensure `bunfig.toml` includes `linker = "hoisted"`

## Commits

- Use conventional commit messages (e.g., `fix:`, `feat:`, `chore:`)
