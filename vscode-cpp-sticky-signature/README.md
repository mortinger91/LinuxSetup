# C++ Sticky Signature

Local VSCode extension: sticky scroll shows every line of a multi-line C++
function signature, also in diffs.

Setting: `cppStickySignature.maxLines` (default 5) — maximum signature lines
shown; the first ones are kept. Also capped by `editor.stickyScroll.maxLineCount`.

## Install

```bash
code --install-extension cpp-sticky-signature-0.0.3.vsix
```

Also offered by `install-deps.sh`.

## Rebuild

Bump `version` in `package.json`, then:

```bash
npx @vscode/vsce package
```

Update the `.vsix` filename in `install-deps.sh` and above.
