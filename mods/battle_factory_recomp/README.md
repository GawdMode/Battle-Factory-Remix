# Battle Factory Remix v1.0.0

**Battle Factory Remix** brings standalone Battle Factory-style rental challenges to **Pokémon Red** and expands the Battle Tower into a full nine-class Factory experience in **Pokémon Crystal**, all from one unified Pokémon Recomp mod.

The Red and Crystal implementations are intentionally separate behind one dispatcher. Each game keeps the version of the Factory designed and tested for it rather than forcing both games to share generation-specific systems.

## Supported games

- Pokémon Red
- Pokémon Crystal

Requires a compatible Pokémon Recomp build (`>=0.2.24 <1.0.0`).

## Pokémon Red

- Dedicated Battle Factory facility in Saffron City.
- Nine rental classes with increasingly strong Pokémon and movesets.
- Choose three rentals from a six-Pokémon draft.
- Seven-battle class runs with rental swapping after victories.
- Factory Heads at the end of Classes 3–9.
- Persistent BP rewards and class progression.
- BP Exchange with rare TMs and rotating Pokémon stock.
- Factory rentals are restored between battles and safely separated from the player's normal adventure party.
- Normal Pokémon Red intro and starting flow are preserved.

## Pokémon Crystal

- Nine escalating Factory classes with seven 3v3 rental battles per class.
- Class-balanced rental species pools.
- Fresh run-randomized single/dual typings with matching sprite palettes.
- Type-aware randomized movesets with STAB preference, useful offensive coverage, and strategy-package sanity.
- Swap one rental for a defeated opponent after battles 1–6.
- Factory Heads at the end of Classes 3–9.
- Persistent BP progression, class-clear bonuses, and unlockable BP Shop stock.
- BP Shop includes held/evolution/battle items, vitamins, finite TMs, and daily Pokémon offers.
- HP, status, and PP are restored between Factory battles.
- PACK and trainer consumable items are disabled during Factory battles; PAY DAY does not generate money.
- RUN provides a retirement confirmation and safely restores the adventure party.
- Fixes normal Battle Tower opponent levels so they match the room level selected before entering.

## BP rewards

Crystal uses the following core payout structure:

- 1 BP per victory
- +5 BP for clearing a class
- +5 BP the first time each class is cleared
- +15 BP for clearing Class 9

Red retains its established Battle Factory BP economy and shop implementation.

## PokeSurvive compatibility

PokeSurvive is optional. For best compatibility, use **PokeSurvive v1.1.1 or newer**.

Factory rentals and opponents are treated as temporary Factory Pokémon rather than normal adventure-party Pokémon. This prevents PokeSurvive systems such as permadeath, survival battle costs, morale/mood consequences, and trainer randomization from interfering with the Factory challenge. Crystal's temporary Factory typings and palettes are restored when the Factory run ends.

## Installation

1. Extract the release ZIP.
2. Place the included `battle_factory_recomp` folder in your Pokémon Recomp `mods` directory.
3. Enable **Battle Factory Remix** in the launcher for Pokémon Red or Pokémon Crystal.

The internal mod ID intentionally remains `battle_factory_recomp` for compatibility with existing Red Factory save data.

## Notes

Battle Factory Remix does not include ROMs or copyrighted game data. You must provide the supported game through the normal Pokémon Recomp setup.
