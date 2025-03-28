# Errata

Mistakes, corrections and observations from the Pokédex data. Unless otherwise stated, the language variant is English `en`.

## Name

Data field: length 10, `[A-Z. ]`.

Transcription errors, due to the lack of extended characters in the font (female, male and apostrophe symbols), and/or how the data is stored internally:

- 029 Nidoran♀ is `NIDORANS`. Could have been `NIDORAN.F`.  
- 032 Nidoran♂ is `NIDORAN..`. Could have been `NIDORAN.M`.
- 083 Farfetch'd is `FARFETCHD`. 

Shown in the manual as `NidoranS`, `Nidoran..`, `Farfetchd` suggesting the text was prepared from the same data source. Other mistakes in the [manual](https://www.hasbro.com/common/instruct/89-203.PDF) are: `staryu`, `Mr. mime`, `scyther`. All other names are capitalized correctly as Title Case.

## Height 

## Weight

## Type

Data field: length 10, `[A-Z ]`.

All entries but one seem correct, possibly due to a typo:

- 052 Meowth is `SCRATCH CA`, truncated by one letter due to the extra space inserted, instead of the correct `SCRATCHCAT`.

## Strength

## Attack

Data field: 4× length 12, `[A-Z ]`.

Entries have a variable number of attacks from 1 to 4. When multiple attacks are listed, each field is separated by a comma and space `, `. For lists with 3 or 4 fields, the final entry terminated by a period `.`. Entries with a single attack have no punctuation, except for 063. Mistakes noted seem to be typos:

- 063 Abra has one attack : `TELEPORT.` terminated with a period.
- 083 Farfetch'd has attack 4: `FURY ATTACKS` with a plural 's', instead of `FURY ATTACK`.
- 135 Jolteon has attack 2: `THUNDERWAVE` missing the space of `THUNDER WAVE`.
- 137 Porygon has attack 3: `COVERSION` missing the 'n' for `CONVERSION`.

Due to these mistakes, I suspect each entry stores a single string rather than referencing a dictionary of attacks.

## Bio
