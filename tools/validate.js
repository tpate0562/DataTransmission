// Validates question bank files in questions/*.json.
//
//   node tools/validate.js                    check every file
//   node tools/validate.js questions/x.json   check one file (ids are still checked against all files)
//
// Exits non-zero when any error is found. Warnings are printed but do not fail.

const fs = require("fs");
const path = require("path");
const katex = require("../vendor/katex/katex.min.js");
const { render } = require("../render.js")(katex);
const { sections } = require("./sections.js");

const ROOT = path.join(__dirname, "..");
const QUESTION_DIR = path.join(ROOT, "questions");
const ALLOWED_KEYS = new Set(["id", "section", "q", "choices", "answer", "explain", "fixed"]);
const POSITIONAL = /\b(all|none|both|neither) of (the )?(above|these|those)\b|\b(both|either|neither) [a-d] (and|or|nor) [a-d]\b|\b(option|choice|answer) [a-d]\b|^\(?[a-d][).]\s/i;

function listFiles() {
    if (!fs.existsSync(QUESTION_DIR)) {
        return [];
    }
    return fs.readdirSync(QUESTION_DIR)
        .filter(f => f.endsWith(".json"))
        .sort()
        .map(f => path.join(QUESTION_DIR, f));
}

function load(file) {
    let questions = JSON.parse(fs.readFileSync(file, "utf8"));
    if (!Array.isArray(questions)) {
        throw new Error("top level must be a JSON array of question objects");
    }
    return questions;
}

function checkQuestion(q, where, errors, warnings) {
    let err = msg => errors.push(where + ": " + msg);
    let warn = msg => warnings.push(where + ": " + msg);

    if (typeof q !== "object" || q === null || Array.isArray(q)) {
        err("question must be an object");
        return;
    }
    for (let key of Object.keys(q)) {
        if (!ALLOWED_KEYS.has(key)) {
            err("unknown key \"" + key + "\"");
        }
    }
    if (typeof q.id !== "string" || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(q.id)) {
        err("id must be a lowercase kebab-case string");
    }
    if (!(q.section in sections)) {
        err("section \"" + q.section + "\" is not one of " + Object.keys(sections).join(", "));
    }
    for (let field of ["q", "explain"]) {
        if (typeof q[field] !== "string" || q[field].trim().length < 10) {
            err(field + " must be a non-trivial string");
        }
    }
    if (!Array.isArray(q.choices) || q.choices.length < 2 || q.choices.length > 6) {
        err("choices must be an array of 2 to 6 strings");
        return;
    }
    if (q.choices.some(c => typeof c !== "string" || c.trim() === "")) {
        err("every choice must be a non-empty string");
        return;
    }
    if (!Number.isInteger(q.answer) || q.answer < 0 || q.answer >= q.choices.length) {
        err("answer must be the 0-based index of the correct choice");
    }
    if (q.fixed !== undefined && typeof q.fixed !== "boolean") {
        err("fixed must be true or false when present");
    }

    let normalized = q.choices.map(c => c.trim().toLowerCase().replace(/\s+/g, " "));
    if (new Set(normalized).size !== normalized.length) {
        err("choices contain duplicates");
    }
    if (!q.fixed) {
        q.choices.forEach((c, i) => {
            if (POSITIONAL.test(c)) {
                err("choice " + i + " refers to other choices by position or uses all/none of the above; choices are shuffled");
            }
        });
    }
    if (q.choices.length !== 4 && !q.fixed) {
        warn("has " + q.choices.length + " choices (4 is the norm)");
    }

    let fields = [["q", q.q], ["explain", q.explain]].concat(q.choices.map((c, i) => ["choice " + i, c]));
    for (let [name, text] of fields) {
        if (typeof text !== "string") {
            continue;
        }
        try {
            render(text, { strict: true });
        } catch (e) {
            err(name + ": " + e.message);
        }
    }
}

function lengthBias(questions) {
    let longest = 0;
    let counted = 0;
    for (let q of questions) {
        if (!Array.isArray(q.choices) || q.choices.length < 3 || !Number.isInteger(q.answer)) {
            continue;
        }
        counted++;
        let lengths = q.choices.map(c => String(c).length);
        let max = Math.max(...lengths);
        if (lengths[q.answer] === max && lengths.filter(l => l === max).length === 1) {
            longest++;
        }
    }
    return { longest, counted };
}

function main() {
    let all = listFiles();
    let targets = process.argv.slice(2).map(f => path.resolve(f));
    if (targets.length === 0) {
        targets = all;
    }

    let errors = [];
    let warnings = [];
    let idOwners = new Map();
    let loaded = new Map();

    for (let file of new Set(all.concat(targets))) {
        try {
            loaded.set(file, load(file));
        } catch (e) {
            errors.push(path.relative(ROOT, file) + ": " + e.message);
        }
    }

    for (let [file, questions] of loaded) {
        for (let q of questions) {
            if (q && typeof q.id === "string") {
                let owners = idOwners.get(q.id) || [];
                owners.push(path.relative(ROOT, file));
                idOwners.set(q.id, owners);
            }
        }
    }

    let total = 0;
    for (let file of targets) {
        let questions = loaded.get(file);
        if (!questions) {
            continue;
        }
        let rel = path.relative(ROOT, file);
        questions.forEach((q, i) => {
            let where = rel + " #" + i + (q && q.id ? " (" + q.id + ")" : "");
            checkQuestion(q, where, errors, warnings);
            if (q && idOwners.get(q.id) && idOwners.get(q.id).length > 1) {
                errors.push(where + ": duplicate id, also in " + idOwners.get(q.id).join(", "));
            }
        });
        total += questions.length;

        let bias = lengthBias(questions);
        let share = bias.counted ? bias.longest / bias.counted : 0;
        let note = rel + ": " + questions.length + " questions; correct answer is the single longest choice in "
            + bias.longest + "/" + bias.counted + " (" + Math.round(share * 100) + "%)";
        if (share > 0.4) {
            warnings.push(note + ". Too predictable: lengthen distractors or trim correct answers (aim for under 35%).");
        } else {
            console.log(note);
        }

        let bySection = {};
        for (let q of questions) {
            bySection[q.section] = (bySection[q.section] || 0) + 1;
        }
        console.log("  by section: " + Object.entries(bySection).map(([s, n]) => s + "=" + n).join(", "));
    }

    for (let w of warnings) {
        console.log("WARNING " + w);
    }
    for (let e of errors) {
        console.log("ERROR " + e);
    }
    console.log(total + " questions checked, " + errors.length + " errors, " + warnings.length + " warnings");
    process.exit(errors.length ? 1 : 0);
}

main();
