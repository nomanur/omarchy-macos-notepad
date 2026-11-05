.pragma library

// Markdown.js — formatting operations on Markdown source.
//
// All functions operate on (text, selectionStart, selectionEnd) and return
// { text, start, end } so callers can restore the caret in one step.
// Text is plain Markdown; the editor is a TextArea in Markdown mode.

function wrapSelection(text, start, end, before, after) {
    return {
        text: text.slice(0, start) + before + text.slice(start, end) + after + text.slice(end),
        start: start + before.length,
        end: end + before.length
    };
}

function toggleLinePrefix(text, start, end, prefix) {
    var lineStart = lastNewlineBefore(text, start);
    var lineEnd = text.indexOf("\n", end);
    if (lineEnd === -1) lineEnd = text.length;
    var block = text.slice(lineStart, lineEnd);
    var lines = block.split("\n");
    var allPrefixed = true;
    for (var i = 0; i < lines.length; i++) {
        if (!lines[i].startsWith(prefix)) { allPrefixed = false; break; }
    }
    var newLines = [];
    for (var j = 0; j < lines.length; j++) {
        if (allPrefixed) newLines.push(lines[j].slice(prefix.length));
        else newLines.push(lines[j].length === 0 ? lines[j] : prefix + lines[j]);
    }
    var newBlock = newLines.join("\n");
    var delta = newBlock.length - block.length;
    return {
        text: text.slice(0, lineStart) + newBlock + text.slice(lineEnd),
        start: Math.max(lineStart, start + (allPrefixed ? -prefix.length : prefix.length)),
        end: end + delta
    };
}

function insertAtCursor(text, start, end, insertion, afterNewline) {
    var insert = String(insertion || "");
    if (afterNewline && start > 0 && text[start - 1] !== "\n") insert = "\n" + insert;
    return {
        text: text.slice(0, start) + insert + text.slice(end),
        start: start + insert.length,
        end: start + insert.length
    };
}

function lastNewlineBefore(text, pos) {
    var idx = text.lastIndexOf("\n", pos - 1);
    return idx === -1 ? 0 : idx + 1;
}

function orderLines(text, start, end, descending) {
    var lineStart = lastNewlineBefore(text, start);
    var lineEnd = text.indexOf("\n", end);
    if (lineEnd === -1) lineEnd = text.length;
    var block = text.slice(lineStart, lineEnd);
    var lines = block.split("\n").filter(function(l) { return l.length > 0; });
    lines.sort(function(a, b) { return descending ? b.localeCompare(a) : a.localeCompare(b); });
    var newBlock = lines.join("\n");
    return {
        text: text.slice(0, lineStart) + newBlock + text.slice(lineEnd),
        start: lineStart,
        end: lineStart + newBlock.length
    };
}

function numberLines(text, start, end) {
    var lineStart = lastNewlineBefore(text, start);
    var lineEnd = text.indexOf("\n", end);
    if (lineEnd === -1) lineEnd = text.length;
    var block = text.slice(lineStart, lineEnd);
    var lines = block.split("\n");
    var newLines = [];
    for (var i = 0; i < lines.length; i++) {
        var stripped = lines[i].replace(/^\s*\d+\.\s*/, "");
        newLines.push((i + 1) + ". " + stripped);
    }
    var newBlock = newLines.join("\n");
    return {
        text: text.slice(0, lineStart) + newBlock + text.slice(lineEnd),
        start: lineStart,
        end: lineStart + newBlock.length
    };
}

function toggleChecklist(text, start, end) {
    var lineStart = lastNewlineBefore(text, start);
    var lineEnd = text.indexOf("\n", end);
    if (lineEnd === -1) lineEnd = text.length;
    var block = text.slice(lineStart, lineEnd);
    var lines = block.split("\n");
    var newLines = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var m = line.match(/^(\s*)-\s*\[([ x])\]\s?(.*)$/);
        if (m) {
            newLines.push(m[1] + "- [" + (m[2] === "x" ? " " : "x") + "] " + m[3]);
        } else if (/^\s*-\s/.test(line)) {
            newLines.push(line.replace(/^(\s*)-\s/, "$1- [ ] "));
        } else if (line.trim().length === 0) {
            newLines.push("- [ ] ");
        } else {
            // Non-empty text without a marker: turn into a checklist item,
            // preserving indentation.
            newLines.push(line.replace(/^(\s*)(.*)$/, "$1- [ ] $2"));
        }
    }
    var newBlock = newLines.join("\n");
    return {
        text: text.slice(0, lineStart) + newBlock + text.slice(lineEnd),
        start: lineStart,
        end: lineStart + newBlock.length
    };
}

function table(rows, cols) {
    rows = Math.max(1, Math.min(10, rows || 2));
    cols = Math.max(1, Math.min(6, cols || 2));
    var header = [];
    for (var j = 0; j < cols; j++) header.push("Column " + (j + 1));
    var sep = [];
    for (var k = 0; k < cols; k++) sep.push("---");
    var lines = [];
    lines.push("| " + header.join(" | ") + " |");
    lines.push("| " + sep.join(" | ") + " |");
    for (var r = 0; r < rows; r++) {
        var cells = [];
        for (var c = 0; c < cols; c++) cells.push("");
        lines.push("| " + cells.join(" | ") + " |");
    }
    return lines.join("\n") + "\n\n";
}

function timestampLine() {
    var d = new Date();
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    var h = d.getHours();
    var ampm = h >= 12 ? "PM" : "AM";
    var h12 = h % 12; if (h12 === 0) h12 = 12;
    var m = ("0" + d.getMinutes()).slice(-2);
    return "--- " + months[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
        + " at " + h12 + ":" + m + " " + ampm + " ---\n\n";
}
