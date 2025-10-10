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

- Always think carefully when discussing programming/technical content
- Write clean, elegant code with concise comments
- Always go with correct solution over quick work-around. Code robustness is the top priority and I would rather take longer to achieve a technically superior solution
- Run the language analyzer/checker on code to ensure it's free of errors and warnings
- Follow best-practices. Don't take shortcuts, take pride in the code you create and work on
- Prioritize code clarity over extensive documentation
- Defensive programming: validate inputs, handle edge cases
- If you spot minor issues in the codebase (lacking documentation, minor code edits) then you are free to fix them as you spot them
- If you spot bigger issues in the codebase then please suggest that these be rectified

## Testing

- Add important unit tests (we don't want tests for the sake of tests)
- Add mocked integration tests using appropriate frameworks
- Focus on meaningful test coverage, not metrics

## Security

- Never commit secrets; validate and sanitize all inputs

## Workflow

- If there is ever something that you are unsure about, do not continue, stop and ask the question. I would rather we resolve questions and take a little longer than making assumptions that could be incorrect
- When I share a URL with you, make sure you read it.
- My sysems are entirely managed by Nix, can you find my system configuration in `~/nixfiles/` if you are working in a `~/Project/...` then you are working on a specific project that enviroment is managed by a devshell configured by the flake in the project folder.

## Dart & Flutter

- Use package:mockito for mocked integration tests
- [Flutter API reference](https://api.flutter.dev/)
- [Dart API reference](https://api.dart.dev/)
