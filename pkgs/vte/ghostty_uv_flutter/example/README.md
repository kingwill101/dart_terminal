# ghostty_uv_flutter example

The UV example is the separate-package prototype app for the higher-fidelity
renderer path.

It demonstrates:
- shared shell profile resolution from `ghostty_vte_flutter`
- controller-owned launch metadata through `activeShellLaunch`
- Session and Environment inspector cards
- `Copy Environment` from the effective shell launch
- UV canvas rendering, selection, and PTY-backed interaction

Run it with:

```sh
cd pkgs/vte/ghostty_uv_flutter/example
flutter run -d linux
```
