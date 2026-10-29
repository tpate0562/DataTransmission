# Writing PSTAT 100 practice questions

Each file in this folder is a JSON array of multiple-choice questions. `node tools/build.js`
validates every file and bundles them into `decks/pstat100-midterm.js`, which `index.html` loads.
Run `node tools/validate.js questions/<file>.json` while writing.

## Question format

```json
{
  "id": "tidy-001",
  "section": "1.4",
  "q": "Question text",
  "choices": ["first", "second", "third", "fourth"],
  "answer": 2,
  "explain": "Why the answer is right, and why the most tempting wrong choice is wrong."
}
```

- `id`: lowercase kebab-case, unique across all files. Use the file's prefix plus a number (`tidy-001`).
- `section`: one of the keys in `tools/sections.js` (`"1.1"` … `"6.3"`, `"3"`, `"7"`).
- `choices`: normally 4. They are **shuffled** every time the question appears, so a choice must
  never mention another by letter or position, and never use "all of the above", "none of the
  above", or "both A and B". For a true/false question use `["True", "False"]` and add
  `"fixed": true` to keep the order.
- `answer`: the 0-based index of the correct choice in `choices` as written.
- `explain`: 1–3 sentences shown after answering. It's what the student learns from a mistake, so
  say *why*.

## Markup (applies to `q`, every choice, and `explain`)

| Write | Renders as |
| --- | --- |
| `\\( \\hat{\\mu} \\)` | inline math (KaTeX) |
| `\\[ \\operatorname{MSE} = \\operatorname{Bias}^2 + \\operatorname{Var} \\]` | display math |
| `` `pivot_longer()` `` | inline code |
| ``` `` select(`my var`) `` ``` | inline code that itself contains backticks |
| `"```r\ncode\n```"` | code block (fences on their own lines) |
| `**bold**` | bold |
| `\n` | line break |

- This is JSON, so every LaTeX backslash is doubled: `"\\(\\hat{\\mu}\\)"`.
- **All math goes in `\\( \\)` or `\\[ \\]`, never `$...$`.** A literal `$` (as in `$1,500`) is fine.
- **All R code goes in backticks or a code block.** This matters: R's lambda `\(x) x + 3` outside a
  code span would be read as the start of a math formula.
- Show data frames the way R prints a tibble, inside a code block.

## What makes a good question here

The midterm is closed book and in class, with the emphasis on conceptual understanding,
decision-making, and data-science principles, plus reading, completing, and predicting the output
of short tidyverse/ggplot2 code. There is no extended calculation. Aim for this mix in each file:

- ~40% conceptual: definitions applied to a situation, contrasts between similar ideas.
- ~30% code: what does this pipeline return (rows, columns, values), fill in the blank, which
  aesthetic is mapped to which variable, spot the bug.
- ~20% scenario/judgment: given a study or a dataset, what's the right decision or the flaw.
- ~10% light computation: a few numbers you could do in your head.

Rules:

- Every answer must be unambiguously correct and every distractor unambiguously wrong.
  Check any code-output question by running the equivalent in pandas (no R in this environment)
  or by working the tiny example by hand, twice.
- Distractors should be plausible: common misconceptions, off-by-one dimensions, swapped
  arguments, the other join type. Not jokes.
- Keep choices similar in length and style. The validator reports how often the correct answer is
  the single longest choice; keep that under 35%.
- Vary the wording and stems. Don't write five questions that differ by one number.
- Stay inside your assigned sections, and use the course's own examples where the topics list
  names them (Billboard, BRFSS/ACE, SEDA, hawks, diamonds, Swain, wavy turban, and so on).
