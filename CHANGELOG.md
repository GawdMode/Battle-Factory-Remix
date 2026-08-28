# Changelog

## v1.0.0

First public release of **Battle Factory Remix**.

### Unified package

- Supports Pokémon Red and Pokémon Crystal from one mod package.
- Uses isolated Red and Crystal codepaths behind a game dispatcher.
- Preserves the established `battle_factory_recomp` internal ID for Red save compatibility.
- Optional PokeSurvive compatibility.

### Pokémon Red

- Preserves the completed Red Battle Factory implementation.
- Dedicated Saffron City facility.
- Nine rental classes, seven-battle runs, rental swaps, Factory Heads, persistent BP, BP Exchange, and rotating Pokémon stock.
- Restores the normal Pokémon Red intro and bedroom start.
- Removes old development-start party/Factory intro scaffolding.

### Pokémon Crystal

- Nine class progression with seven battles per class.
- Class-balanced species and move-power progression.
- Smart randomized movesets with STAB preference, offensive floor, coverage, and strategy-package checks.
- Run-randomized single/dual Factory typings with matching temporary sprite palettes.
- Stable rental identities for the duration of a run.
- Factory Heads for Classes 3–9.
- Persistent BP rewards and unlockable BP Shop inventory.
- Daily BP Pokémon offers.
- Battle item restrictions, HP/status/PP restoration, retirement flow, and PAY DAY suppression.
- Fixes normal Battle Tower opponents so their level matches the selected room level.

### Release cleanup

- Removed TEST CLASS and development BP grants from Crystal.
- Removed development warps/party setup.
- Public branding finalized as **Battle Factory Remix**.
