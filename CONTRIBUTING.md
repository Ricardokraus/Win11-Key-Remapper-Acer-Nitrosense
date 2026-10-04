# Contributing

Thanks for helping! There are several ways to contribute:

- **Report a bug, suggest an idea or ask a question**:
  [open an issue](https://github.com/Ricardokraus/Win11-Key-Remapper/issues/new/choose)
  and pick the matching form.
- **Tell us about your laptop**: the
  [Works on my laptop](https://github.com/Ricardokraus/Win11-Key-Remapper/issues/new?template=works_on_my_laptop.yml)
  form grows the tested models list in the README.
- **Improve the code or the docs** with a pull request (below).

## Pull requests

1. Fork the repository and create a branch for your change.
2. Install [AutoHotkey v2](https://www.autohotkey.com/) and read
   [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): it explains how the keyboard hook
   works and lists the traps this project already fell into.
3. Keep the style: AutoHotkey v2, English names and comments, short comments
   that explain *why*.
4. Before opening the PR, run (from PowerShell, not Git Bash):

   ```powershell
   AutoHotkey64.exe /ErrorStdOut /Validate src\Win11KeyRemapper.ahk
   powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
   ```

   and try your change with real keys (see the manual checklist in
   DEVELOPMENT.md).
5. Add a line to `CHANGELOG.md` under the upcoming version, and update the
   README if the change is visible to users.

GitHub Actions checks the syntax, runs the tests and compiles the exe for every
pull request.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
