# Translating Tales of the Tumbling Dice

There are two parts to translate: the interface (buttons, labels, tooltips, the tavern's lines)
and the tales themselves.

## The interface

1. Make the template from the scripts (it is already in the repository, kept up to date by the
   tests):

       godot --headless -s res://tools/extract_strings.gd

   This writes `locale/tumbling_dice.pot`.
2. Copy it to `locale/<code>.po`, for example `locale/de.po`, and fill in each `msgstr`. Any
   gettext editor (Poedit, Weblate, Lokalize) works. Keep the `%d` and `%s` codes, in the same
   order.
3. Run the game. Every `.po` file in `locale/` is read at start-up, with no import step, and the
   language can be picked under Options. "System" follows the computer's language when there is a
   translation for it.

Untranslated lines fall back to English, so a partial translation is fine to try.

For programmers: a `Label` or `Button` translates its text by itself. Text with values in it must
go through `tr()` before the values are filled in: `tr("Round %d of %d") % [a, b]`, never
`tr("Round %d of %d" % [a, b])`. `tools/extract_strings.gd -- --check` fails when the template is
out of date, and the `access` test suite runs it.

## The tales

A tale is translated as a whole file, because its sentences, choices and outcomes read best when
they are written together rather than line by line.

1. Copy `tales/<name>.tale` to `tales/locale/<code>/<name>.tale`.
2. Translate the text: titles, narration, option text, outcomes and endings.
3. Leave every id, key and effect as it is: `## id:`, `* id:`, `+ id:`, `> tier:`, `? cond ::`,
   header keys, dice, foes, flags and marks. The game keeps your progress by these ids, so a save
   made in one language carries on in another.

The linter (`lint` test suite) checks that a translated tale has the same scenes, options and
endings as the original, and the same lint rules as any other tale. When the game runs in that
language, the translated file is used in place of the original; tales without a translation stay
in English.
