const PROGRESS_KEY = "dashcards-progress";
const SETTINGS_KEY = "dashcards-settings";
const CLEAR_STREAK = 2; //a card you missed clears after this many correct answers in a row
const TRAILING = 25;
const LETTERS = "ABCDEF";

const PRESET_GROUPS = [
    ["AP English Literature Vocab", [
        ["animus-voluptuous.txt", "List 1: Animus – Voluptuous"],
        ["abate-corroborate.txt", "List 2: Abate – Corroborate"],
        ["aberration-vicissitude.txt", "List 3: Aberration – Vicissitude"],
        ["affluent-wheedle.txt", "List 4: Affluent – Wheedle"],
        ["comeuppance-huffy.txt", "List 5: Comeuppance – Huffy"],
        ["ap-lit-cumulative.txt", "AP English Literature Cumulative"]
    ]],
    ["AP English Language Vocab", [
        ["abrade-vainglorious.txt", "List 1: Abrade – Vainglorious"],
        ["abrogate-zealous.txt", "List 2: Abrogate – Zealous"],
        ["abscond-wistful.txt", "List 3: Abscond – Wistful"],
        ["absolve-zenith.txt", "List 4: Absolve – Zenith"],
        ["aegis-vitriolic.txt", "List 5: Aegis – Vitriolic"],
        ["ad-nauseam-vindicate.txt", "List 6: Ad Nauseam – Vindicate"],
        ["camaraderie-torpid.txt", "List 7: Camaraderie – Torpid"],
        ["ap-lang-cumulative.txt", "AP English Language Cumulative"]
    ]],
    ["Miscellaneous", [
        ["international-morse-code.txt", "International Morse Code (A-Z)"],
        ["periodic_table_elements.txt", "Periodic Table Elements"],
        ["world-capitals.txt", "195 Country Capitals"]
    ]]
];

let decks = {};
let deckOrder = [];
let deck = null;
let session = null;
let current = null;
let settings = { inputMode: "multiple-choice", shuffleChoices: true, autoAdvance: false, lastDeck: null };
let autoAdvanceTimer = null;
let settingsOpen = false;

let writeValue = document.getElementById("write-answer");

function $(id) {
    return document.getElementById(id);
}

function show(id, visible) {
    if (visible) {
        $(id).style.removeProperty("display");
    } else {
        $(id).style.display = "none";
    }
}

function render(text) {
    return DashRender.render(text);
}

function shuffle(array) {
    //Fisher-Yates; sort() with a random comparator is biased
    for (let i = array.length - 1; i > 0; i--) {
        let j = Math.floor(Math.random() * (i + 1));
        [array[i], array[j]] = [array[j], array[i]];
    }
    return array;
}

function normalize(text) {
    return String(text).trim().toLowerCase().replace(/\s+/g, " ");
}

/* STORAGE */

function readStorage(key, fallback) {
    try {
        let value = localStorage.getItem(key);
        return value ? JSON.parse(value) : fallback;
    } catch (e) {
        return fallback;
    }
}

function writeStorage(key, value) {
    try {
        localStorage.setItem(key, JSON.stringify(value));
    } catch (e) {
        //storage blocked or full: progress just won't survive a reload
    }
}

function savedSessions() {
    return readStorage(PROGRESS_KEY, {});
}

function saveSession() {
    let all = savedSessions();
    all[session.deckId] = session;
    writeStorage(PROGRESS_KEY, all);
}

function clearAllProgress() {
    if (!confirm("Erase saved progress for every deck?")) {
        return;
    }
    try {
        localStorage.removeItem(PROGRESS_KEY);
    } catch (e) {
        //nothing saved to erase
    }
    session = null;
    toggleSettingsMenu();
    quitToHome();
}

/* DECKS */

function addDeck(newDeck) {
    newDeck.byId = {};
    for (let q of newDeck.questions) {
        newDeck.byId[q.id] = q;
    }
    if (!decks[newDeck.id]) {
        deckOrder.push(newDeck.id);
    }
    decks[newDeck.id] = newDeck;
}

//Dashcards deck files are "term,definition,term,definition,..." with commas written as " \ " and backslashes as " \\ "
function parseTermDeck(id, title, group, deckString) {
    let parts = deckString.split(",").map(part => part.replace(/ \\ /g, ",").replace(/ \\\\ /g, "\\").trim());
    let questions = [];

    for (let i = 0; i + 1 < parts.length; i += 2) {
        if (parts[i] !== "" || parts[i + 1] !== "") {
            questions.push({ id: String(questions.length), term: parts[i], q: parts[i + 1] });
        }
    }
    return { id: id, title: title, group: group, kind: "terms", questions: questions };
}

function loadDecks() {
    let questionDecks = window.DASHCARDS_DECKS || {};
    for (let id in questionDecks) {
        let d = questionDecks[id];
        addDeck({
            id: id,
            title: d.title,
            group: "PSTAT 100",
            kind: "questions",
            questions: d.questions,
            sections: d.sections,
            chapters: d.chapters
        });
    }

    let presets = window.DASHCARDS_PRESETS || {};
    for (let [group, files] of PRESET_GROUPS) {
        for (let [file, title] of files) {
            if (presets[file]) {
                addDeck(parseTermDeck("preset:" + file, title, group, presets[file]));
            }
        }
    }
}

function fillDeckSelect() {
    let select = $("deck-select");
    let groups = {};
    select.innerHTML = "";

    for (let id of deckOrder) {
        let d = decks[id];
        if (!groups[d.group]) {
            groups[d.group] = document.createElement("optgroup");
            groups[d.group].label = d.group;
            select.appendChild(groups[d.group]);
        }
        let option = document.createElement("option");
        option.value = id;
        option.textContent = d.title + " (" + d.questions.length + ")";
        groups[d.group].appendChild(option);
    }
}

function getUserDeck() {
    const [file] = $("upload").files;
    if (!file) {
        return;
    }

    const reader = new FileReader();
    reader.addEventListener("load", () => {
        let userDeck = parseTermDeck("file:" + file.name, file.name.replace(/\.txt$/i, ""), "Loaded files", reader.result);
        if (userDeck.questions.length < 5) {
            $("startprompt").textContent = "Deck must contain at least 5 terms!";
            return;
        }
        addDeck(userDeck);
        fillDeckSelect();
        quitToHome();
        selectDeck(userDeck.id);
        $("upload").value = "";
    });
    reader.readAsText(file, "utf-8");
}

/* HOME SCREEN */

function selectDeck(id) {
    deck = decks[id] || decks[deckOrder[0]];
    $("deck-select").value = deck.id;
    $("startprompt").textContent = "";
    settings.lastDeck = deck.id;
    writeStorage(SETTINGS_KEY, settings);

    buildSectionPicker();
    buildLimitSelect();
    updateResumeBox();
    updateStartSummary();
}

function buildSectionPicker() {
    let list = $("section-list");
    list.innerHTML = "";
    show("section-picker", deck.kind === "questions");
    if (deck.kind !== "questions") {
        return;
    }

    let counts = {};
    for (let q of deck.questions) {
        counts[q.section] = (counts[q.section] || 0) + 1;
    }

    for (let chapter in deck.chapters) {
        let keys = Object.keys(deck.sections).filter(key => key.split(".")[0] === chapter && counts[key]);
        if (keys.length === 0) {
            continue;
        }

        let total = keys.reduce((sum, key) => sum + counts[key], 0);
        let block = document.createElement("div");
        block.className = "chapter";

        let head = document.createElement("label");
        head.className = "check-label chapter-label";
        head.innerHTML = '<input type="checkbox" checked data-chapter="' + chapter + '"> '
            + chapter + "&ensp;" + DashRender.escapeHtml(deck.chapters[chapter])
            + ' <span class="count">' + total + "</span>";
        block.appendChild(head);

        //a chapter that is a single section (3 Missing data, 7 Kernel smoothing) needs no sub-list
        if (keys.length > 1 || keys[0] !== chapter) {
            let sub = document.createElement("div");
            sub.className = "section-checks";
            for (let key of keys) {
                let label = document.createElement("label");
                label.className = "check-label";
                label.innerHTML = '<input type="checkbox" checked data-section="' + key + '"> '
                    + key + "&ensp;" + DashRender.escapeHtml(deck.sections[key])
                    + ' <span class="count">' + counts[key] + "</span>";
                sub.appendChild(label);
            }
            block.appendChild(sub);
        } else {
            head.querySelector("input").dataset.section = keys[0];
        }
        list.appendChild(block);
    }
}

$("section-list").addEventListener("change", event => {
    let box = event.target;
    let block = box.closest(".chapter");
    let sectionBoxes = block.querySelectorAll(".section-checks input");
    let chapterBox = block.querySelector("input[data-chapter]");

    if (box === chapterBox) {
        sectionBoxes.forEach(b => b.checked = box.checked);
    } else {
        let checked = Array.from(sectionBoxes).filter(b => b.checked).length;
        chapterBox.checked = checked === sectionBoxes.length;
        chapterBox.indeterminate = checked > 0 && checked < sectionBoxes.length;
    }
    updateStartSummary();
});

function setAllSections(checked) {
    $("section-list").querySelectorAll("input").forEach(box => {
        box.checked = checked;
        box.indeterminate = false;
    });
    updateStartSummary();
}

function buildLimitSelect() {
    let select = $("limit-select");
    select.innerHTML = '<option value="all">All selected</option>';
    for (let n of [10, 25, 50, 100, 200]) {
        if (n < deck.questions.length) {
            select.innerHTML += '<option value="' + n + '">' + n + " at random</option>";
        }
    }
}

function selectedIds() {
    let questions = deck.questions;

    if (deck.kind === "questions") {
        let chosen = new Set();
        $("section-list").querySelectorAll("input[data-section]").forEach(box => {
            if (box.checked) {
                chosen.add(box.dataset.section);
            }
        });
        questions = questions.filter(q => chosen.has(q.section));
    }

    let ids = shuffle(questions.map(q => q.id));
    let limit = $("limit-select").value;
    if (limit !== "all") {
        ids = ids.slice(0, Number(limit));
    }
    return ids;
}

function countSelected() {
    let limit = $("limit-select").value;
    let n = deck.questions.length;
    if (deck.kind === "questions") {
        let chosen = new Set();
        $("section-list").querySelectorAll("input[data-section]").forEach(box => box.checked && chosen.add(box.dataset.section));
        n = deck.questions.filter(q => chosen.has(q.section)).length;
    }
    return limit === "all" ? n : Math.min(n, Number(limit));
}

function updateStartSummary() {
    let n = countSelected();
    $("start-summary").textContent = n + (n === 1 ? " question" : " questions") + " in this session.";
    $("startbutton").disabled = n === 0;
}

function unfinishedSession(deckId) {
    let saved = savedSessions()[deckId];
    return saved && saved.queue && saved.queue.length > 0 ? saved : null;
}

function updateResumeBox() {
    let saved = unfinishedSession(deck.id);
    show("resume-box", Boolean(saved));
    $("startbutton").textContent = saved ? "Start a new session" : "Start";
    if (saved) {
        let cleared = Object.values(saved.cards).filter(c => c.status === "cleared").length;
        $("resume-text").textContent = "Session in progress: " + cleared + " of " + saved.total + " cleared, "
            + saved.queue.length + " left in the queue.";
    }
}

/* QUIZ */

function newSession(ids) {
    let cards = {};
    for (let id of ids) {
        cards[id] = { status: "new", streak: 0, misses: 0, seen: 0 };
    }
    return {
        deckId: deck.id,
        total: ids.length,
        queue: shuffle(ids.slice()),
        cards: cards,
        answered: 0,
        correct: 0,
        incorrect: 0,
        recent: [],
        startedAt: Date.now()
    };
}

function startQuiz(ids) {
    if (!Array.isArray(ids)) {
        if (unfinishedSession(deck.id) && $("home").style.display !== "none"
            && !confirm("Start over? This replaces your saved progress on this deck.")) {
            return;
        }
        ids = selectedIds();
    }
    if (ids.length === 0) {
        $("startprompt").textContent = "Pick at least one topic first.";
        return;
    }
    if (deck.kind === "terms" && deck.questions.length < 5) {
        $("startprompt").textContent = "Deck must contain at least 5 terms!";
        return;
    }

    session = newSession(ids);
    saveSession();
    showQuiz();
}

function resumeSession() {
    session = unfinishedSession(deck.id);
    if (!session) {
        return;
    }
    //drop anything the deck no longer has (a re-loaded file deck can change)
    session.queue = session.queue.filter(id => deck.byId[id]);
    showQuiz();
}

function startMissedSession() {
    let missed = Object.keys(session.cards).filter(id => session.cards[id].firstTry === false && deck.byId[id]);
    startQuiz(missed);
}

function writeMode() {
    return deck.kind === "terms" && settings.inputMode === "write-in";
}

function showQuiz() {
    show("home", false);
    show("done", false);
    show("quiz", true);
    showQuestion();
}

function quitToHome() {
    clearTimeout(autoAdvanceTimer);
    current = null;
    show("quiz", false);
    show("done", false);
    show("home", true);
    selectDeck(deck ? deck.id : settings.lastDeck);
}

function termChoices(q) {
    let picked = [q.term];
    for (let other of shuffle(deck.questions.slice())) {
        if (picked.length === 4) {
            break;
        }
        if (!picked.some(term => normalize(term) === normalize(other.term))) {
            picked.push(other.term);
        }
    }
    return shuffle(picked.map(text => ({ text: text, correct: text === q.term })));
}

function answerText(q) {
    return deck.kind === "terms" ? q.term : q.choices[q.answer];
}

function showQuestion() {
    clearTimeout(autoAdvanceTimer);
    updateProgress();

    if (session.queue.length === 0) {
        showDone();
        return;
    }

    let qid = session.queue[0];
    let q = deck.byId[qid];
    let card = session.cards[qid];
    let choices;

    if (deck.kind === "terms") {
        choices = termChoices(q);
    } else {
        choices = q.choices.map((text, i) => ({ text: text, correct: i === q.answer }));
        if (settings.shuffleChoices && !q.fixed) {
            shuffle(choices);
        }
    }
    current = { qid: qid, q: q, card: card, choices: choices, answered: false };

    $("meta-section").textContent = deck.kind === "questions" ? q.section + " " + deck.sections[q.section] : deck.title;
    let badge = $("meta-badge");
    if (card.status === "review") {
        badge.textContent = "Review · " + card.streak + " of " + CLEAR_STREAK + " in a row";
        badge.className = "badge review";
    } else {
        badge.textContent = "New";
        badge.className = "badge";
    }

    $("question").innerHTML = render(q.q);

    let buttonDiv = $("buttons");
    buttonDiv.innerHTML = "";
    show("buttons", !writeMode());
    show("write-input", writeMode());
    show("feedback", false);

    choices.forEach((choice, i) => {
        let button = document.createElement("button");
        button.className = "choice";
        button.innerHTML = '<span class="letter">' + LETTERS[i] + '</span><span class="choice-text">' + render(choice.text) + "</span>";
        button.addEventListener("click", () => clickButton(i));
        buttonDiv.appendChild(button);
    });

    window.scrollTo(0, 0);
    if (writeMode()) {
        writeValue.value = "";
        writeValue.disabled = false;
        writeValue.focus();
    } else if (document.activeElement) {
        document.activeElement.blur();
    }
}

function clickButton(index) {
    if (!current || current.answered || !current.choices[index]) {
        return;
    }
    finishAnswer(current.choices[index].correct, index);
}

function writeSubmit() {
    if (!current || current.answered || normalize(writeValue.value) === "") {
        return;
    }
    finishAnswer(normalize(writeValue.value) === normalize(current.q.term), -1);
}

writeValue.addEventListener("keydown", event => {
    if (event.key === "Enter") {
        event.preventDefault();
        writeSubmit();
    }
});

//moves the card to the back of the queue unless it's cleared; returns what happened, for the feedback line
function recordAnswer(qid, correct) {
    let card = session.cards[qid];
    session.queue.shift();
    card.seen++;
    session.answered++;
    session.recent.push(correct ? 1 : 0);
    if (session.recent.length > TRAILING) {
        session.recent.shift();
    }

    if (correct) {
        session.correct++;
        if (card.status === "new") {
            card.status = "cleared";
            card.firstTry = true;
            return "Cleared on the first try.";
        }
        card.streak++;
        if (card.streak >= CLEAR_STREAK) {
            card.status = "cleared";
            return CLEAR_STREAK + " in a row. Cleared!";
        }
        session.queue.push(qid);
        return card.streak + " of " + CLEAR_STREAK + " in a row. It goes to the back of the queue for one more try.";
    }

    session.incorrect++;
    if (card.status === "new") {
        card.firstTry = false;
    }
    card.status = "review";
    card.streak = 0;
    card.misses++;
    session.queue.push(qid);
    return "Sent to the back of the queue. Get it right " + CLEAR_STREAK + " times in a row to clear it.";
}

function finishAnswer(correct, chosenIndex) {
    current.answered = true;
    let status = recordAnswer(current.qid, correct);
    saveSession();

    $("buttons").querySelectorAll(".choice").forEach((button, i) => {
        button.disabled = true;
        if (current.choices[i].correct) {
            button.classList.add("right");
        } else if (i === chosenIndex) {
            button.classList.add("wrong");
        }
    });
    writeValue.disabled = true;

    let rsp = $("rsp");
    if (correct) {
        rsp.textContent = "Correct";
        rsp.className = "right";
    } else if (chosenIndex === -1) {
        rsp.innerHTML = "Incorrect. The answer was " + render(current.q.term);
        rsp.className = "wrong";
    } else {
        rsp.textContent = "Incorrect";
        rsp.className = "wrong";
    }
    $("rsp-status").textContent = status;
    $("explain").innerHTML = current.q.explain ? render(current.q.explain) : "";
    show("explain", Boolean(current.q.explain));
    show("feedback", true);
    updateProgress();

    $("nextbutton").focus({ preventScroll: true });
    if (correct && settings.autoAdvance) {
        autoAdvanceTimer = setTimeout(nextQuestion, 900);
    }
}

function nextQuestion() {
    if (!current || !current.answered) {
        return;
    }
    showQuestion();
}

function updateProgress() {
    let cards = Object.values(session.cards);
    let cleared = cards.filter(c => c.status === "cleared").length;

    $("count-cleared").textContent = cleared;
    $("count-total").textContent = session.total;
    $("count-queue").textContent = session.queue.length;
    $("count-review").textContent = cards.filter(c => c.status === "review").length;
    $("progress-fill").style.width = (session.total ? 100 * cleared / session.total : 0) + "%";

    $("rsp-correct").textContent = session.correct;
    $("rsp-incorrect").textContent = session.incorrect;
    let accuracy = session.answered ? 100 * session.correct / session.answered : 100;
    $("answeraccuracy").textContent = "Score " + Math.round(accuracy) + "%";
    let last = session.recent.reduce((a, b) => a + b, 0);
    $("ttf").textContent = session.recent.length ? last + " of the last " + session.recent.length + " correct" : "";
}

function showDone() {
    current = null;
    if (!session.finishedAt) {
        session.finishedAt = Date.now();
        saveSession();
    }
    show("quiz", false);
    show("done", true);
    window.scrollTo(0, 0);

    let ids = Object.keys(session.cards).filter(id => deck.byId[id]);
    let firstTry = ids.filter(id => session.cards[id].firstTry === true).length;
    let missed = ids.filter(id => session.cards[id].firstTry === false)
        .sort((a, b) => session.cards[b].misses - session.cards[a].misses);
    let minutes = Math.max(1, Math.round((session.finishedAt - session.startedAt) / 60000));
    let pct = ids.length ? Math.round(100 * firstTry / ids.length) : 0;

    $("done-summary").innerHTML =
        '<div class="summary-grid">'
        + "<div><strong>" + ids.length + "</strong>cleared</div>"
        + "<div><strong>" + pct + "%</strong>right on the first try</div>"
        + "<div><strong>" + missed.length + "</strong>missed at least once</div>"
        + "<div><strong>" + session.answered + "</strong>answers in " + minutes + " min</div>"
        + "</div>";

    show("retry-missed", missed.length > 0);
    $("missed-heading").textContent = missed.length
        ? "Questions you missed, most misses first"
        : "You got every question right on the first try.";

    let list = $("missed-list");
    list.innerHTML = "";
    for (let id of missed) {
        let q = deck.byId[id];
        let misses = session.cards[id].misses;
        let item = document.createElement("li");
        item.innerHTML =
            '<div class="missed-meta">' + (deck.kind === "questions" ? q.section + " " + DashRender.escapeHtml(deck.sections[q.section]) + " · " : "")
            + "missed " + misses + (misses === 1 ? " time" : " times") + "</div>"
            + '<div class="missed-q">' + render(q.q) + "</div>"
            + '<div class="missed-a"><span class="label">Answer</span> ' + render(answerText(q)) + "</div>"
            + (q.explain ? '<div class="missed-explain">' + render(q.explain) + "</div>" : "");
        list.appendChild(item);
    }
}

document.addEventListener("keydown", event => {
    if (event.ctrlKey || event.metaKey || event.altKey || settingsOpen || !current) {
        return;
    }
    if (event.target === writeValue) {
        return; //the input handles its own Enter
    }

    if (current.answered) {
        if (event.key === "Enter" || event.key === " " || event.key === "ArrowRight") {
            event.preventDefault();
            nextQuestion();
        }
        return;
    }

    if (writeMode()) {
        return;
    }
    let index = "123456".indexOf(event.key);
    if (index === -1 && event.key.length === 1) {
        index = "abcdef".indexOf(event.key.toLowerCase());
    }
    if (index !== -1 && index < current.choices.length) {
        event.preventDefault();
        clickButton(index);
    }
});

/* SETTINGS */

function toggleSettingsMenu() {
    settingsOpen = !settingsOpen;

    if (settingsOpen) {
        $("content").style.filter = "blur(5px)";
        show("settings-menu", true);
        show("settings-open", false);
    } else {
        $("content").style.removeProperty("filter");
        show("settings-menu", false);
        show("settings-open", true);
    }
}

document.addEventListener("keydown", event => {
    if (event.key === "Escape" && settingsOpen) {
        toggleSettingsMenu();
    }
});

function applySettingsToForm() {
    $("multiple-choice").checked = settings.inputMode !== "write-in";
    $("write-in").checked = settings.inputMode === "write-in";
    $("shuffle-choices").checked = settings.shuffleChoices;
    $("auto-advance").checked = settings.autoAdvance;
}

function saveSettingsFromForm() {
    let previousMode = settings.inputMode;
    settings.inputMode = $("write-in").checked ? "write-in" : "multiple-choice";
    settings.shuffleChoices = $("shuffle-choices").checked;
    settings.autoAdvance = $("auto-advance").checked;
    writeStorage(SETTINGS_KEY, settings);

    //redraw an unanswered term card in the new input mode
    if (current && !current.answered && previousMode !== settings.inputMode && deck.kind === "terms") {
        showQuestion();
    }
}

/* STARTUP */

settings = Object.assign(settings, readStorage(SETTINGS_KEY, {}));
applySettingsToForm();
loadDecks();
fillDeckSelect();

if (deckOrder.length === 0) {
    $("startprompt").textContent = "No decks found. Run node tools/build.js to generate them.";
    show("startbutton", false);
} else {
    selectDeck(settings.lastDeck);
}
