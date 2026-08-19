# quarto-duolingo

A Duolingo widget for Quarto documents. Put your streak, XP and courses on your
website with one line.

```
{{< duolingo >}}
```

The profile is fetched **while the document renders**, so the published page is
plain static HTML — no JavaScript, no API calls from your visitors' browsers, no
CORS proxy, no scheduled job to keep a JSON file around. It works in HTML output
and degrades to a plain sentence in PDF, DOCX and Markdown.

## Installing

```bash
quarto add bonijoao/quarto-duolingo
```

## Using it

Set your username once, in `_quarto.yml` (whole project) or in a document's
front matter:

```yaml
duolingo:
  user: joohbonny
```

Then drop the shortcode wherever the card should appear:

```
{{< duolingo >}}
```

Any option can also be given inline, which overrides the YAML:

```
{{< duolingo lang="pt" theme="dark" layout="compact" >}}
```

If you really only study one language, this is probably the shape you want —
the streak and the XP, and just that course:

```yaml
duolingo:
  user: joohbonny
  courses: 1
  bars: false
```

## Options

| Option | Default | What it does |
|---|---|---|
| `user` | — | **Required.** Your Duolingo username (the one in your profile URL, not your e-mail). |
| `lang` | `en` | Labels and number formatting: `en`, `pt`, `es`, `fr`, `de`. |
| `theme` | `auto` | `auto` follows the reader's system setting *and* the Quarto dark toggle. `light` / `dark` pin it. |
| `accent` | `#58cc02` | Accent colour: the avatar ring, the Super badge and the course bars. |
| `layout` | `card` | `card` is the full widget; `compact` is a slim one-liner for sidebars and footers. |
| `avatar` | `true` | Show your Duolingo avatar (embedded in the page, not hotlinked). |
| `stats` | `[streak, xp, since]` | Which tiles to show, in order. |
| `courses` | `4` | How many courses to list, biggest first. `0` hides the list. |
| `bars` | `true` | Draw each course's XP as a bar relative to your biggest one. Worth turning off when you only list one course — the bar would always be full. |
| `link` | `true` | Make the card link to your Duolingo profile. |
| `on-error` | `warn` | `warn` logs a warning and omits the card; `fail` aborts the render. |

## Keeping it up to date

**Read this one.** The numbers come from the moment the site was *built*, not
from the moment somebody *reads* it. Nothing in the page updates on its own.

So how fresh your card is depends entirely on how often you build:

| How you publish | How often the card updates |
|---|---|
| `quarto publish gh-pages` from your machine | Only when you run it |
| A GitHub Action that renders on push | Only when you push |
| A GitHub Action with a `schedule` | As often as the schedule says |

If you want it to keep up with your streak, give your publishing workflow a
daily schedule. Add the `schedule` block to the workflow you already use:

```yaml
name: Publish

on:
  push:
    branches: [main]
  schedule:
    # every day at 09:00 UTC — keeps the Duolingo card current
    - cron: "0 9 * * *"
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: quarto-dev/quarto-actions/setup@v2
      - uses: quarto-dev/quarto-actions/publish@v2
        with:
          target: gh-pages
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Two things worth knowing about GitHub's scheduler: cron runs can be delayed by
a fair few minutes, and schedules are disabled automatically after ~60 days of
repository inactivity — `workflow_dispatch` lets you kick it back on.

If your site is big and rebuilding it daily feels wasteful, a weekly cron still
keeps the card reasonably honest.

## What the card can show

Everything below comes from Duolingo's public profile endpoint:

| | |
|---|---|
| Name, username, avatar | |
| Super status | shown as a badge |
| Current streak | with the date it started |
| Total XP | |
| Courses | with each course's XP, drawn as bars relative to your main course |
| Member since | year the account was created |

### What it cannot show

Not a limitation of this extension — the data simply is not in the public API:

- **Level, section, unit or CEFR label.** The `crowns` field is pinned at `9999`
  for everybody; it is a placeholder, not your progress. The endpoints that know
  your real position in the tree require you to be logged in.
- **Longest streak.** Only the current one is exposed.
- **XP history / daily gains.** Requires authentication.
- **League and division.** Requires authentication.

## Notes

This uses an **unofficial** endpoint. It has been stable for years, but Duolingo
does not promise anything and could change it without notice. That is why the
default `on-error: warn` never breaks your build: if the API goes away, you get
a warning in the log and the card is simply left out of the page.

Each page that uses the shortcode makes one request per username, no matter how
many cards are on it.

## License

MIT
