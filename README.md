# ![Dashcards Favicon](favicon-32x32.png) Dashcards: PSTAT 100 Midterm Practice

A fork of [Dashcards](https://github.com/tpate0562/Dashcards), the flashcard site by Tejas Patel and Miguel Diaz,
set up as a practice test for the PSTAT 100 midterm. The questions follow the midterm topics review, section by
section: tidy data, data frame transformations, missing data, sampling and study design, visualization, density
estimation, and kernel smoothing. Math is typeset with KaTeX (HTML plus MathML) and everything is set in Computer
Modern on a black background.

## Running it

```sh
git clone https://github.com/tpate0562/DataTransmission.git
cd DataTransmission
open index.html        # macOS; on Windows use `start index.html`, on Linux `xdg-open index.html`
```

You don't need a server or an internet connection: the questions, KaTeX, and the fonts all ship in the repo.

## How the queue works

- Every session shuffles its questions into a queue.
- Get a question right on the first try and it's cleared.
- Get it wrong and it goes to the back of the queue. From then on it only clears once you answer it correctly
  **two times in a row**. Another miss sends it back again with the count reset.
- The session ends when the queue is empty. The summary lists every question you missed, most misses first,
  with the answer and explanation, and you can drill only those again.
- Progress is saved in the browser after every answer, so you can close the tab and resume later.

Answer choices are reshuffled each time a question comes back. Keys: `1`–`4` or `A`–`D` to answer, `Enter` for the
next question. On the home page you can limit a session to some topics or to a random 10–200 questions.

## Editing the questions

The questions live in `questions/*.json`, one file per group of topics. See
[questions/AUTHORING.md](questions/AUTHORING.md) for the format and the markup (LaTeX in `\( \)` and `\[ \]`, R code in
backticks or fenced blocks). After editing, run

```sh
node tools/build.js
```

to validate every question (bad LaTeX, malformed choices, duplicate ids) and regenerate
`decks/pstat100-midterm.js`, the file the page actually loads.

## The original Dashcards decks

The AP English vocab lists and the other presets are still in the deck menu, and Create Deck and Load File work as
before. Term decks get the same queue, and Write-in mode (in settings) works for them.

## Credits

- Dashcards: Tejas Patel and Miguel Diaz.
- [KaTeX](https://katex.org) 0.16.11, MIT license (`vendor/katex/LICENSE`).
- Computer Modern Unicode fonts by Donald Knuth and Andrey Panov, SIL Open Font License (`fonts/OFL.txt`), from the
  [computer-modern](https://www.npmjs.com/package/computer-modern) package.
