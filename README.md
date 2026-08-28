# Battle Factory Remix

A unified **Pokémon Recomp** Battle Factory mod for **Pokémon Red** and **Pokémon Crystal**.

Battle Factory Remix uses separate, game-specific implementations behind a single mod package. Red keeps its established standalone Saffron City Factory, while Crystal uses the newer nine-class Battle Factory Remix built around the Battle Tower.

## Highlights

### Pokémon Red

- Standalone Saffron City Battle Factory
- Nine rental classes
- Six-Pokémon draft / choose three
- Seven-battle class runs and post-win swaps
- Factory Heads for Classes 3–9
- Persistent BP progression
- BP Exchange with rare TMs and rotating Pokémon stock

### Pokémon Crystal

- Nine escalating Factory classes
- Class-balanced rental pools
- Run-randomized single/dual typings
- Matching type-based sprite palettes
- Type-aware smart randomized movesets
- Post-win rental swaps
- Factory Heads for Classes 3–9
- Persistent BP Shop progression and daily Pokémon offers
- Normal Battle Tower room-level opponent fix

## Compatibility

- Pokémon Red
- Pokémon Crystal
- Pokémon Recomp `>=0.2.24 <1.0.0`
- Optional PokeSurvive integration; use **PokeSurvive v1.1.1+**

The internal mod ID remains `battle_factory_recomp` to preserve compatibility with existing Red Factory save data.

## Installation

Download the latest ZIP from **Releases**, extract it, and place `battle_factory_recomp` in your Pokémon Recomp `mods` directory. Enable **Battle Factory Remix** in the launcher for Red or Crystal.

## Source layout

```text
mods/
└── battle_factory_recomp/
    ├── main.lua
    ├── manifest.json
    ├── README.md
    └── variants/
        ├── red/main.lua
        └── crystal/main.lua
```

`main.lua` dispatches to the appropriate implementation at runtime so generation-specific code remains isolated.

## Release

Current release: **v1.0.0**

See [CHANGELOG.md](CHANGELOG.md) for release history.

Battle Factory Remix does not include ROMs or copyrighted game data.
