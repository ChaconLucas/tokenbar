# Contributing to TokenBar

Thanks for helping improve TokenBar! Contributions, bug reports, documentation improvements, and pull requests are welcome.

## Report a bug or suggest a feature

Open a [GitHub issue](https://github.com/ChaconLucas/tokenbar/issues) after checking for an existing report. Include your platform (macOS, Windows, Linux, iOS, Android, or watch), TokenBar version or commit, steps to reproduce, expected behavior, actual behavior, and relevant logs with secrets removed.

## Submit a change

1. Open an issue first for large or breaking changes so the approach can be discussed.
2. Fork the repository and create a focused branch.
3. Follow the conventions already used in the affected component and keep changes small and reviewable.
4. Update documentation when behavior, commands, configuration, API inputs/outputs, or supported platforms change.
5. Run the relevant build, lint, and test commands for the component you changed, where available. Describe exactly what you ran and any checks you could not run.
6. Open a pull request against the default branch. Explain the change, link related issues, include screenshots for UI changes, and call out compatibility or security implications.
7. Respond to review feedback; maintainers review contributions before merging.

## Quality and compatibility

- Do not commit credentials, access tokens, personal usage data, generated secrets, or private logs.
- Prefer existing patterns and dependencies; explain any new dependency and its license.
- Keep cross-platform behavior in mind and identify the platforms actually tested.
- Add or update tests when practical for bug fixes and new functionality.
- Use clear commit messages and communicate breaking changes.
- Contributions should be compatible with the project's [MIT license](LICENSE).

## Security issues

Please avoid publishing exploitable vulnerability details in a public issue. See [SECURITY.md](SECURITY.md) for the private reporting process.

## Helpful references

- [README](README.md)
- [Installation guide](INSTALL.md)
- [API and MCP documentation](docs/api.md)
- [Pull requests](https://github.com/ChaconLucas/tokenbar/pulls)
