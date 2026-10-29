/* Rich text renderer shared by the site and tools/validate.js.
 *
 * Markup understood in questions, choices and explanations:
 *   ```r            fenced code block (closing ``` on its own line)
 *   `code`          inline code; use ``double backticks`` when the code itself contains a backtick
 *   **bold**
 *   \( ... \)       inline math (LaTeX, rendered by KaTeX as HTML + MathML)
 *   \[ ... \]       display math
 *   newline         line break
 * Everything else is HTML-escaped, so a literal $ (as in $1,500) is just text.
 */
(function (root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory;
    } else {
        root.DashRender = factory(root.katex);
    }
})(typeof self !== "undefined" ? self : this, function (katex) {
    function escapeHtml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }

    function fail(message, text, at) {
        throw new Error(message + " near: «" + text.slice(Math.max(0, at - 15), at + 35) + "»");
    }

    function renderMath(tex, display, strict) {
        if (!katex) {
            return escapeHtml(display ? "\\[" + tex + "\\]" : "\\(" + tex + "\\)");
        }
        try {
            return katex.renderToString(tex, {
                displayMode: display,
                throwOnError: true,
                output: "htmlAndMathml",
                strict: strict ? "error" : "ignore"
            });
        } catch (e) {
            if (strict) {
                throw new Error("KaTeX: " + e.message + " in «" + tex + "»");
            }
            return '<span class="math-error" title="' + escapeHtml(e.message) + '">' + escapeHtml(tex) + "</span>";
        }
    }

    //plain text: escape, **bold**, newlines
    function formatText(s, strict) {
        if (strict) {
            let stray = s.search(/\\[)\]]/);
            if (stray !== -1) {
                fail("Closing math delimiter without an opening one", s, stray);
            }
            let dollar = s.search(/\$[^$\n]*(\\[a-zA-Z]|\^|_\{)[^$\n]*\$/);
            if (dollar !== -1) {
                fail("Looks like $...$ math; use \\( ... \\) instead", s, dollar);
            }
        }
        return escapeHtml(s)
            .replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>")
            .replace(/\n/g, "<br>");
    }

    //prose: \( inline \) and \[ display \] math, the rest is formatted text
    function renderProse(text, strict) {
        let out = "";
        let i = 0;

        while (i < text.length) {
            let open = text.slice(i).search(/\\[(\[]/);
            if (open === -1) {
                out += formatText(text.slice(i), strict);
                break;
            }

            let start = i + open;
            let display = text[start + 1] === "[";
            let close = text.indexOf(display ? "\\]" : "\\)", start + 2);
            if (close === -1) {
                if (strict) {
                    fail("Unclosed math delimiter " + text.slice(start, start + 2), text, start);
                }
                out += formatText(text.slice(i), strict);
                break;
            }

            out += formatText(text.slice(i, start), strict);
            out += renderMath(text.slice(start + 2, close), display, strict);
            i = close + 2;
        }
        return out;
    }

    //inline `code` spans; a run of N backticks is closed by the next run of exactly N
    function renderInline(text, strict) {
        let out = "";
        let last = 0;
        let i = 0;

        while (i < text.length) {
            if (text[i] !== "`") {
                i++;
                continue;
            }

            let n = 0;
            while (text[i + n] === "`") {
                n++;
            }

            let close = -1;
            let j = i + n;
            while (j < text.length) {
                j = text.indexOf("`", j);
                if (j === -1) {
                    break;
                }
                let m = 0;
                while (text[j + m] === "`") {
                    m++;
                }
                if (m === n) {
                    close = j;
                    break;
                }
                j += m;
            }

            if (close === -1) {
                if (strict) {
                    fail("Unclosed inline code backtick", text, i);
                }
                i += n;
                continue;
            }

            let code = text.slice(i + n, close);
            if (code.length > 2 && code[0] === " " && code[code.length - 1] === " ") {
                code = code.slice(1, -1);
            }
            out += renderProse(text.slice(last, i), strict);
            out += "<code>" + escapeHtml(code) + "</code>";
            i = last = close + n;
        }

        return out + renderProse(text.slice(last), strict);
    }

    function render(text, options) {
        let strict = Boolean(options && options.strict);
        if (text === undefined || text === null) {
            return "";
        }
        text = String(text);

        let out = "";
        let last = 0;
        let fence = /(^|\n)```([\w+-]*)[ \t]*\n([\s\S]*?)\n```[ \t]*(?=\n|$)/g;
        let match;

        while ((match = fence.exec(text)) !== null) {
            let before = text.slice(last, match.index);
            out += renderInline(before.replace(/^\n/, ""), strict);
            let lang = match[2] ? ' class="lang-' + escapeHtml(match[2]) + '"' : "";
            out += "<pre><code" + lang + ">" + escapeHtml(match[3]) + "</code></pre>";
            last = fence.lastIndex;
        }

        let rest = text.slice(last);
        if (strict && rest.indexOf("```") !== -1) {
            fail("Unterminated or inline ``` code fence (fences need their own lines)", rest, rest.indexOf("```"));
        }
        out += renderInline(last > 0 ? rest.replace(/^\n/, "") : rest, strict);
        return out;
    }

    return { render: render, escapeHtml: escapeHtml };
});
