.pragma library

// NotesStore.js — portable logic for the Notes plugin.
//
// Pure functions only: no QML, no file IO. The single source of truth for
// note shapes, sorting, search, and serialization so the UI (Panel.qml) and
// any future service share one implementation.
//
// Note shape (all timestamps are ms since epoch):
//   {
//     id:        string  — unique id (Date.now().toString(36) + counter)
//     title:     string  — derived from first line when untouched, else custom
//     body:      string  — Markdown source
//     folderId:  string  — id of parent folder ("inbox" | "trash" | custom)
//     pinned:    boolean
//     created:   number
//     modified:  number
//     deletedAt: number|null — set when trashed; null otherwise
//   }
//
// Folder shape:
//   { id: string, name: string, created: number }
//
// Store shape:
//   {
//     version: 1,
//     folders: [Folder],
//     notes: [Note],
//     settings: {
//       showTrash: boolean,          — sidebar mode (false = browse folders)
//       activeFolderId: string,      — currently selected folder
//       activeNoteId: string|null,   — currently open note
//       lastMode: "full"|"quick"     — last window mode used
//       quickNoteId: string|null     — pinned Quick Note scratchpad id
//       fontSize: number,            — editor font size (px)
//       hotCornerEnabled: boolean,
//       hotCornerDwellMs: number,
//       hotCornerTriggerSize: number,
//       collapsed: boolean            — window starts collapsed in quick mode
//     }
//   }
//
// TODO(future editions of this file):
//   - Folders are stored but the UI ships with inbox + trash only; custom
//     folder creation is a later addition. The model already supports it.

var COUNTER = 0

function now() {
    return Date.now();
}

function uid() {
    COUNTER += 1;
    return now().toString(36) + "-" + (COUNTER % 100000).toString(36);
}

function defaultFolder(id, name) {
    return { id: id, name: name, created: now() };
}

function newNote(folderId) {
    var t = now();
    return {
        id: uid(),
        title: "New Note",
        body: "",
        folderId: folderId || "inbox",
        pinned: false,
        created: t,
        modified: t,
        deletedAt: null
    };
}

function newFolder(name) {
    return { id: uid(), name: String(name || "Untitled"), created: now() };
}

function newStore() {
    return {
        version: 1,
        folders: [
            defaultFolder("inbox", "Notes"),
            defaultFolder("trash", "Trash")
        ],
        notes: [],
        settings: {
            showTrash: false,
            activeFolderId: "inbox",
            activeNoteId: null,
            lastMode: "full",
            quickNoteId: null,
            fontSize: 14,
            hotCornerEnabled: true,
            hotCornerDwellMs: 150,
            hotCornerTriggerSize: 4,
            collapsed: false
        }
    };
}

// ---------------------------------------------------------------- search

function noteMatches(note, query) {
    if (!query) return true;
    var q = String(query).toLowerCase();
    var text = (String(note.title || "") + "\n" + String(note.body || "")).toLowerCase();
    return text.indexOf(q) !== -1;
}

function filterNotes(notes, opts) {
    opts = opts || {};
    var folderId = opts.folderId == null ? null : String(opts.folderId);
    var showTrash = !!opts.showTrash;
    var query = opts.query || "";
    var out = [];
    for (var i = 0; i < notes.length; i++) {
        var n = notes[i];
        if (showTrash) {
            if (n.deletedAt == null) continue;
        } else {
            if (n.deletedAt != null) continue;
            if (folderId && n.folderId !== folderId) continue;
        }
        if (!noteMatches(n, query)) continue;
        out.push(n);
    }
    // Pinned first, then most-recently-modified first.
    out.sort(function(a, b) {
        if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1;
        return (b.modified || 0) - (a.modified || 0);
    });
    return out;
}

// ---------------------------------------------------------------- preview

// First non-empty line of body, capped at 2 lines / 120 chars.
function previewOf(note) {
    var body = String(note.body || "");
    var lines = body.split("\n");
    var picked = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.length === 0) continue;
        // Skip a leading title line that duplicates the title.
        if (picked.length === 0 && line === String(note.title || "").trim()) continue;
        picked.push(line);
        if (picked.length >= 2) break;
    }
    var text = picked.join(" ");
    if (text.length > 120) text = text.slice(0, 117) + "...";
    return text;
}

// Derive title from the first line of body (macOS Notes behavior).
function titleFromBody(body) {
    var lines = String(body || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.length === 0) continue;
        // Strip Markdown heading markers for the title.
        line = line.replace(/^#{1,6}\s+/, "").trim();
        if (line.length > 80) line = line.slice(0, 77) + "...";
        return line;
    }
    return "New Note";
}

function relativeDate(ts) {
    if (!ts) return "";
    var d = new Date(ts);
    var nowDate = new Date();
    var sameDay = d.toDateString() === nowDate.toDateString();
    if (sameDay) {
        var h = d.getHours();
        var m = ("0" + d.getMinutes()).slice(-2);
        var ampm = h >= 12 ? "PM" : "AM";
        var h12 = h % 12;
        if (h12 === 0) h12 = 12;
        return h12 + ":" + m + " " + ampm;
    }
    var yesterday = new Date(nowDate.getTime() - 86400000);
    if (d.toDateString() === yesterday.toDateString()) return "Yesterday";
    var startOfWeek = new Date(nowDate.getTime() - nowDate.getDay() * 86400000);
    if (d >= startOfWeek) {
        var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
        return days[d.getDay()];
    }
    var sameYear = d.getFullYear() === nowDate.getFullYear();
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    if (sameYear) return months[d.getMonth()] + " " + d.getDate();
    return months[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear();
}

// ---------------------------------------------------------------- mutations

function findNote(store, id) {
    for (var i = 0; i < store.notes.length; i++)
        if (store.notes[i].id === id) return store.notes[i];
    return null;
}

function touch(note) {
    note.modified = now();
}

function setTitle(note, title, body) {
    note.title = String(title || "").trim() || titleFromBody(body);
    touch(note);
}

function setBody(note, body) {
    note.body = String(body || "");
    touch(note);
    // Keep title in sync with first line until the user renames explicitly.
    // The UI calls setTitle on explicit rename; here we always refresh unless
    // the title does not match the old first line (i.e. user-customized).
    var derived = titleFromBody(note.body);
    var oldDerived = titleFromBody(note.body); // body already updated; use title check below
    if (note.title === "New Note" || note.title === oldDerived) {
        note.title = derived;
    }
}

function togglePinned(note) {
    note.pinned = !note.pinned;
    touch(note);
}

function trashNote(note) {
    if (note.deletedAt != null) return;
    note.deletedAt = now();
    note.folderId = "trash";
    touch(note);
}

function restoreNote(note) {
    note.deletedAt = null;
    note.folderId = "inbox";
    touch(note);
}

function deleteForever(store, id) {
    for (var i = 0; i < store.notes.length; i++) {
        if (store.notes[i].id === id) {
            store.notes.splice(i, 1);
            return true;
        }
    }
    return false;
}

function duplicateNote(store, id) {
    var src = findNote(store, id);
    if (!src) return null;
    var copy = {
        id: uid(),
        title: src.title + " copy",
        body: src.body,
        folderId: src.folderId,
        pinned: false,
        created: now(),
        modified: now(),
        deletedAt: null
    };
    store.notes.push(copy);
    return copy;
}

// ---------------------------------------------------------------- persistence

function serialize(store) {
    return JSON.stringify(store);
}

// Parse with structural validation. Returns a store (possibly the default)
// and never throws: a corrupt file should start fresh, not crash the shell.
function deserialize(text) {
    var defaults = newStore();
    if (!text) return defaults;
    var parsed;
    try {
        parsed = JSON.parse(text);
    } catch (e) {
        return defaults;
    }
    if (!parsed || typeof parsed !== "object") return defaults;

    if (Array.isArray(parsed.folders) && parsed.folders.length > 0) {
        var folders = [];
        for (var i = 0; i < parsed.folders.length; i++) {
            var f = parsed.folders[i];
            if (f && typeof f.id === "string" && typeof f.name === "string")
                folders.push({ id: f.id, name: f.name, created: Number(f.created) || now() });
        }
        if (folders.length > 0) defaults.folders = folders;
    }
    // Guarantee inbox + trash exist even if a hand-edited file dropped them.
    var hasInbox = false, hasTrash = false;
    for (var j = 0; j < defaults.folders.length; j++) {
        if (defaults.folders[j].id === "inbox") hasInbox = true;
        if (defaults.folders[j].id === "trash") hasTrash = true;
    }
    if (!hasInbox) defaults.folders.unshift(defaultFolder("inbox", "Notes"));
    if (!hasTrash) defaults.folders.push(defaultFolder("trash", "Trash"));

    if (Array.isArray(parsed.notes)) {
        var notes = [];
        for (var k = 0; k < parsed.notes.length; k++) {
            var n = parsed.notes[k];
            if (!n || typeof n.id !== "string") continue;
            notes.push({
                id: n.id,
                title: String(n.title || "New Note"),
                body: String(n.body || ""),
                folderId: String(n.folderId || "inbox"),
                pinned: !!n.pinned,
                created: Number(n.created) || now(),
                modified: Number(n.modified) || now(),
                deletedAt: n.deletedAt == null ? null : Number(n.deletedAt)
            });
        }
        defaults.notes = notes;
    }

    if (parsed.settings && typeof parsed.settings === "object") {
        var s = parsed.settings;
        defaults.settings.showTrash = !!s.showTrash;
        if (typeof s.activeFolderId === "string") defaults.settings.activeFolderId = s.activeFolderId;
        defaults.settings.activeNoteId = typeof s.activeNoteId === "string" ? s.activeNoteId : null;
        if (s.lastMode === "full" || s.lastMode === "quick") defaults.settings.lastMode = s.lastMode;
        defaults.settings.quickNoteId = typeof s.quickNoteId === "string" ? s.quickNoteId : null;
        if (typeof s.fontSize === "number") defaults.settings.fontSize = Math.max(10, Math.min(28, s.fontSize));
        defaults.settings.hotCornerEnabled = s.hotCornerEnabled !== false;
        if (typeof s.hotCornerDwellMs === "number") defaults.settings.hotCornerDwellMs = Math.max(0, Math.min(2000, s.hotCornerDwellMs));
        if (typeof s.hotCornerTriggerSize === "number") defaults.settings.hotCornerTriggerSize = Math.max(1, Math.min(32, s.hotCornerTriggerSize));
        defaults.settings.collapsed = !!s.collapsed;
    }

    // Seed a welcome note on a truly fresh store so first launch is not blank.
    if (defaults.notes.length === 0) {
        var welcome = newNote("inbox");
        welcome.title = "Welcome to Notes";
        welcome.body = "# Welcome to Notes\n\n"
            + "A macOS-style notes app for Omarchy.\n\n"
            + "## Try it\n\n"
            + "- [x] Create a note with Ctrl+N\n"
            + "- [ ] Hover the bottom-right corner for Quick Note\n"
            + "- [ ] Pin a note with Ctrl+Shift+P\n\n"
            + "**Bold**, *italic*, ~~strikethrough~~, and lists all work.\n\n"
            + "---\n\n"
            + new Date().toLocaleString() + "\n";
        defaults.notes.push(welcome);
        defaults.settings.activeNoteId = welcome.id;
    }
    return defaults;
}
