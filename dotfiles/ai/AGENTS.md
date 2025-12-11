# Code Assistant Guidelines

## Context

- Name: Jimmy
- Software Engineer & small-business owner building apps for mobile, web, and desktop
- Solo developer & architect
- Primary stack: Dart/Flutter, Nix, Rust, Nushell, SQLite, PostgreSQL, GCP, Firebase
- Point out learning opportunities when relevant

## Tone

- Simple, succinct, objective, and efficient (especially in documentation, markdown, notes, comments)

## Coding

- Think carefully on technical content
- Clean, elegant code with concise comments
- Separation of concerns, DRY principle
- Correct solutions over quick workarounds - robustness is top priority. Take longer for technically superior solutions
- Run language analyzer to ensure error/warning-free code
- Take pride in the code; follow best-practices, no shortcuts
- Descriptive names for semantic clarity
- Prioritize code clarity over extensive documentation
- Defensive programming: validate inputs, handle edge cases
- Fix minor issues as you spot them; flag bigger issues
- No silent errors
- Prefer required parameters, defaults can make bugs hard to find

## Testing

- Add meaningful unit tests (not tests for the sake of tests)
- Add mocked integration tests using appropriate frameworks
- When fixing complex issues, add regression tests
- Always verify tests pass before claiming completion

## Documentation

- Keep Readme/Agent/Claude files up-to-date; flag if not (do not update without consent)
- Files: ideally <100 lines, max 200
- Code should be self-documenting; Readmes provide quick orientation (purpose, structure, components) not comprehensive documentation
- Agent files: high-level overview, key patterns; reference package READMEs for specifics

## Security

- Never commit secrets; validate and sanitize all inputs

## Workflow

- If unsure, stop and ask - I'd rather take longer than make incorrect assumptions
- I value your input - proactively share ideas on architecture and better approaches. Let's collaborate to find the best solutions
- Read URLs when shared
- My systems are entirely managed by Nix, system configuration is in `~/nixfiles/`. If working in `~/Project/...` you are in a project with its own devshell configured by the project flake.

## Dart & Flutter

- Use package:mockito for mocked integration tests
- Use timeouts: `timeout 30 flutter test ...` (60/90s for complex projects)
- [Flutter API](https://api.flutter.dev/) | [Dart API](https://api.dart.dev/)
