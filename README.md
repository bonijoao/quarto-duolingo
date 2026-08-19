# quarto-duolingo

**Put your Duolingo streak on your Quarto site — with one line, no JavaScript,
and no API keys.**

```
{{< duolingo >}}
```

<!-- Substitua pela captura do card assim que a demo estiver no ar:
     ![](docs/card.png) -->

If you build your portfolio, CV or personal site with Quarto, this drops a card
with your streak, your XP and the languages you are learning right into the
page — next to your R packages, your publications and your GitHub link, where a
"Languages: English — intermediate" bullet used to sit doing nothing.

## Why you might want this

A CV line that says *"English: intermediate"* is a claim. A card that says
**1,213 days without missing a lesson** is evidence — and it is the kind of
evidence that says something about you that a certificate cannot: that you show
up every single day. If you already keep a `pacotes.qmd` and a `cv.qmd`, this is
one more line of YAML.

It was built for the crowd that lives in Quarto: data scientists, statisticians
and researchers who write their site the same way they write their analyses.

## How it works

This is the part worth understanding, because it explains why the setup is so
short.

Duolingo has a public profile endpoint. The obvious approach — fetch it from the
visitor's browser — **does not work**: the response carries no
`Access-Control-Allow-Origin` header, so the browser blocks it. Every
JavaScript-based attempt at this ends up needing a CORS proxy, or a scheduled
job that stores the data in a JSON file next to your site.

So this extension does not use the browser at all. A Lua filter fetches your
profile **while the document renders**, on your machine or in your CI, and emits
finished HTML:

```
quarto render  ──►  Lua filter  ──►  Duolingo API  ──►  static HTML in your page
```

There is no CORS problem, because the request is not made by a browser. What
your readers download is plain markup — no JavaScript, no network requests, no
tracking, and one less thing that can break on someone's phone. Your avatar is
embedded in the page as a data URI, so the card works with
`embed-resources: true` and keeps working if Duolingo's CDN goes down.

The same design is why it degrades gracefully: in PDF, DOCX or Markdown output
you get a plain sentence instead of raw HTML.

## Installing

```bash
quarto add bonijoao/quarto-duolingo
```

## Using it

Set your username once — in `_quarto.yml` for the whole site, or in a single
document's front matter:

```yaml
duolingo:
  user: your-username
```

Then put the shortcode wherever the card belongs:

```
{{< duolingo >}}
```

Any option can also be passed inline, overriding the YAML:

```
{{< duolingo lang="pt" theme="dark" layout="compact" >}}
```

If you study one language seriously and dabble in others, this is probably the
shape you want — the streak, the XP, and just your main course:

```yaml
duolingo:
  user: your-username
  courses: 1
  bars: false
```

## Options

| Option | Default | What it does |
|---|---|---|
| `user` | — | **Required.** Your Duolingo username (the one in your profile URL, not your e-mail). |
| `lang` | `en` | Labels and number formatting: `en`, `pt`, `es`, `fr`, `de`. |
| `theme` | `auto` | `auto` follows the reader's system setting *and* the Quarto dark toggle. `light` / `dark` pin it. |
| `accent` | `#58cc02` | Accent colour: the wordmark, the avatar ring, the Super badge and the course bars. |
| `layout` | `card` | `card` is the full widget; `compact` is a slim one-liner for sidebars and footers. |
| `avatar` | `true` | Show your Duolingo avatar, embedded in the page rather than hotlinked. |
| `stats` | `[streak, xp, since]` | Which tiles to show, in order. |
| `courses` | `4` | How many courses to list, biggest first. `0` hides the list. |
| `bars` | `true` | Draw each course's XP as a bar relative to your biggest one. Worth turning off when you only list one course — the bar would always be full. |
| `link` | `true` | Make the card link to your Duolingo profile. |
| `on-error` | `warn` | `warn` logs a warning and omits the card; `fail` aborts the render. |

Because everything lives in YAML, a bilingual site can render the same card
twice with different labels — `{{< duolingo lang="en" >}}` in one tab and
`{{< duolingo lang="pt" >}}` in the other.

## Keeping it up to date

**Read this one.** The numbers come from the moment the site was *built*, not
from the moment somebody *reads* it. Nothing in the page updates on its own.

| How you publish | How often the card updates |
|---|---|
| `quarto publish gh-pages` from your machine | Only when you run it |
| A GitHub Action that renders on push | Only when you push |
| A GitHub Action with a `schedule` | As often as the schedule says |

If you want the card to keep up with your streak, give your publishing workflow
a schedule. Add the `schedule` block to the workflow you already use:

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
repository inactivity — `workflow_dispatch` lets you turn them back on.

If rebuilding a large site every day feels wasteful, a weekly cron still keeps
the card reasonably honest. And if your site commits its rendered output rather
than publishing to `gh-pages`, render just the page that holds the card and
commit that — it keeps the job fast and the diff small.

## What the card can show

Everything below comes from Duolingo's public profile endpoint:

| | |
|---|---|
| Name, username, avatar | |
| Super status | shown as a badge |
| Current streak | with the date it started |
| Total XP | |
| Courses | with each course's XP, optionally drawn as bars |
| Member since | year the account was created |

### What it cannot show

None of this is a limitation of the extension — the data is simply not in the
public API. Verified by probing the endpoint's `fields` parameter, which returns
a field when it exists and silently drops it when it does not:

- **Duolingo Score and CEFR level.** `score`, `cefrLevel`, `proficiency` and
  every neighbouring name come back empty. The Score lives behind
  `score-api.duolingo.com`, which redirects away without a session. It is
  session data, not profile data.
- **Level, section or unit.** The `crowns` field is pinned at `9999` for
  everybody — a placeholder, not your progress.
- **Longest streak.** Only the current one is exposed.
- **XP history, league and division.** All require authentication (`401`).

## Notes

This uses an **unofficial** endpoint. It has been stable for years, but Duolingo
does not promise anything and could change it without notice. That is why the
default `on-error: warn` never breaks your build: if the API goes away, you get
a warning in the log and the card is simply left out of the page.

Each page that uses the shortcode makes one request per username, however many
cards are on it.

Not affiliated with or endorsed by Duolingo, Inc. The Duolingo name and
logotype belong to them.

## License

MIT — see [LICENSE](LICENSE).
