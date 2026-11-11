# Routing rules for agents

Edit this file to add routing rules:

```text
~/Library/Application Support/Chrome Profile Router/routing-rules.json
```

Rules use standard regular expressions (`NSRegularExpression`, ICU syntax) against the complete incoming HTTP/HTTPS URL. There are no service-specific parsers, inferred scopes, or model calls.

## Format

```json
{
  "version": 1,
  "rules": [
    {
      "id": "project-to-work",
      "pattern": "^https://example\\.com/team/project(?:[/?#]|$)",
      "profile": "Profile 10"
    },
    {
      "id": "ask-for-other-example-links",
      "pattern": "^https://example\\.com(?:[/?#]|$)",
      "ask": true
    }
  ]
}
```

Replace the example domain, path, and profile with the user's choices. Profile directory IDs vary between computers. Discover them; don't guess from the display name.

Each rule has:

| Field | Meaning |
| --- | --- |
| `id` | Required, unique, nonempty label. Shown by the dry-run command and picker. |
| `pattern` | Required, nonempty regular expression. |
| `profile` | Chrome directory ID, such as `Default` or `Profile 10`. |
| `ask` | Set to `true` to show the picker instead of choosing a profile. |
| `enabled` | Optional boolean; defaults to `true`. Set to `false` to disable a rule. |

Specify exactly one destination: `profile` or `ask: true`. Unknown fields, duplicate IDs, unsupported versions, and invalid expressions are rejected.

## Matching and precedence

Rules run from top to bottom. **The first enabled match wins**, regardless of how specific later rules are. Put exceptions before broader rules.

If nothing matches, the existing website choice in `rules.json` applies. If there is no website choice, the picker appears. An `ask` rule stops this fallback. A matching rule whose profile no longer exists also shows the picker instead of falling through.

Use `^` and `$` when you need anchoring: regex matching otherwise searches anywhere in the URL. Matching is case-sensitive by default; standard inline options such as `(?i)` are supported. JSON requires backslashes to be escaped. In the example above, `(?:[/?#]|$)` prevents `/team/project-fork` from matching `/team/project`.

Patterns see the URL as received, including percent encoding, query parameters, and fragments. The app does not decode or restructure the URL for regex matching, and it passes the original link to Chrome unchanged. Avoid putting transient login tokens into rules.

Option-click, the extension, and the paste field can still force the picker. When a custom rule applies, that manual choice is for one opening; the website checkbox is disabled so it cannot appear to override the custom rule. Edit the JSON to change the rule permanently.

## Agent workflow

The installed executable provides read-only commands:

```sh
router="$HOME/Applications/Chrome Profile Router.app/Contents/MacOS/ChromeProfileRouter"
"$router" --profiles
"$router" --validate-rules
"$router" --explain 'https://example.com/team/project/issues/12'
```

`--profiles` returns directory IDs and display names. `--validate-rules` checks syntax and reports any rules pointing at unavailable profiles. Invalid configuration exits with code 1. `--explain` returns `action`, `source`, `rule`, `profile`, and `profileName`. It neither opens a browser nor echoes the input URL.

To prepare a change without affecting live routing:

1. Read the existing file and preserve unrelated rules. Discover current profile IDs with `--profiles`.
2. Write the proposed complete document to a temporary file.
3. Validate it with `--validate-rules --rules-file /absolute/path/candidate.json`.
4. Run `--explain URL --rules-file /absolute/path/candidate.json` for intended matches, similar nonmatches, and relevant exceptions. Check which rule wins, not just which profile it returns.
5. Back up the current file, then atomically replace it with the validated candidate. Keep the file readable/writable only by its owner (`0600`).

The app rereads `routing-rules.json` for every incoming link. No restart is needed. The installer creates an empty file on first installation and preserves it on upgrades. The picker writes website choices to the separate `rules.json` file, so it won't overwrite an agent's custom rules.

If the rules file becomes unreadable or invalid, automatic routing stops and the picker displays an error. Fixing the file restores routing on the next link. Removing the file or setting `rules` to an empty array restores ordinary website routing.
