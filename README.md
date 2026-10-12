# LoCA for octowow (1.12)

Port of [LoCA - Loss of Control Alerter](https://github.com/a-vasilev/classic-loca) (MIT, by Rdmx) to the 1.12 client.

- **Retail mode** (default) uses `C_LossOfControl` from ClassicAPI.dll.
- **Custom mode** reads your debuffs (ClassicAPI's `C_UnitAuras`, or SuperWoW spell ids as a fallback) and alerts on the ones in the tracked list.
- Ace3 is gone: settings live in `LoCADB` and the options are a native panel.

Commands: `/loca` (options), `/loca test`, `/loca unlock`, `/loca lock`, `/loca reset`.

Changes from the original: profiles removed, spell list swapped to vanilla spells, retail LoC textures drawn with plain textures since they don't exist in 1.12.

## Install

Copy this folder into `Interface/AddOns/LoCA` (the folder must be named `LoCA`). Retail mode needs ClassicAPI.dll; custom mode works with ClassicAPI or SuperWoW.

## License

MIT. The original LoCA is Copyright (c) 2021 Angel Vasilev ([a-vasilev/classic-loca](https://github.com/a-vasilev/classic-loca)); this port keeps that copyright and permission notice in [LICENSE](LICENSE).
