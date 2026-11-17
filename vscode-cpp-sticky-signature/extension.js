// Folding provider for C++ that gives each function signature line its own range, all ending at
// the body's closing brace. Sticky scroll shows one line per range, so the whole signature sticks.
const vscode = require('vscode');

const NOT_FUNCTION = /^(if|else|for|while|switch|do|try|catch|case|default|namespace|class|struct|union|enum|extern)\b/;

const MAX_HEADER_LINES = 40;

// Closing minus opening brackets, ignoring strings, char literals and '//' comments.
function netClosers(text) {
    const code = text.replace(/"(\\.|[^"\\])*"|'(\\.|[^'\\])*'/g, '').replace(/\/\/.*$/, '');
    return (code.match(/[)}\]]/g) || []).length - (code.match(/[({[]/g) || []).length;
}

// Whether a line ends the walk back from '{'. Lines inside an unclosed bracket, init-list lines
// (', _a{x}') and wrapped arguments (`Mode::Inline)}`) belong to the signature even if they end
// in a brace; a block end ('}'), statement (';'), comment, '#' line or label does not.
function endsHeader(text, depth) {
    if (depth > 0 || /^[:,]/.test(text)) {
        return false;
    }
    if (netClosers(text) > 0 && !text.startsWith('}') && !/[;{]$/.test(text)) {
        return false;
    }
    return !text || text.startsWith('#') || text.startsWith('//') || text.endsWith('*/')
        || /[;{}\\]$/.test(text) || (text.endsWith(':') && !text.endsWith('::'));
}

// Lambdas are checked on the first line only: init lists may hold lambda arguments.
function isFunctionHeader(header, firstLine) {
    const count = (char) => header.split(char).length - 1;
    const isLambda = /\]\s*\(|\]$/.test(firstLine.replace(/operator\s*\[\s*\]/g, ''));
    return header.includes('(') && count('(') === count(')') && !NOT_FUNCTION.test(header)
        && !isLambda && !/[=,(]$/.test(header);
}

// Returns [{start, end}] (0-based lines). Only handles '{' on its own line, closed by '}' or '};'
// at the same indentation, which is how clang-format lays out functions and constructors here.
// maxLines caps how many signature lines stick; the first ones are kept.
function signatureRanges(lines, maxLines = 5) {
    const ranges = [];
    for (let open = 0; open < lines.length; open++) {
        if (lines[open].trim() !== '{') {
            continue;
        }
        let start = open;
        let depth = 0;
        let inInitList = false;
        while (start > 0 && open - start < MAX_HEADER_LINES) {
            const above = lines[start - 1].trim();
            inInitList = inInitList || /^[:,]/.test(lines[start].trim());
            const isComment = above.startsWith('//');
            if (!(isComment && inInitList) && endsHeader(above, depth)) {
                break;
            }
            start--;
            depth += isComment ? 0 : netClosers(above);
        }
        const header = lines.slice(start, open).map((line) => line.trim()).join(' ');
        if (start === open || depth !== 0 || !isFunctionHeader(header, lines[start].trim())) {
            continue;
        }
        const indent = lines[open].slice(0, lines[open].indexOf('{'));
        const isClose = (line) => line.trimEnd() === indent + '}' || line.trimEnd() === indent + '};';
        let close = open + 1;
        while (close < lines.length && !isClose(lines[close])
            && lines[close].trimEnd() !== indent + '{') {
            close++;
        }
        if (close >= lines.length || !isClose(lines[close])) {
            continue;
        }
        // Only name and arguments stick: a constructor's init list (': _a{a}') ends the header.
        let added = 0;
        for (let line = start; line < open && added < maxLines; line++) {
            if (/^:(?!:)/.test(lines[line].trim())) {
                break;
            }
            if (!lines[line].trim().startsWith('//')) {
                ranges.push({ start: line, end: close - 1 });
                added++;
            }
        }
        open = close; // Blocks inside a function body are never functions we stick.
    }
    return ranges;
}

function activate(context) {
    const changed = new vscode.EventEmitter();
    const provider = {
        onDidChangeFoldingRanges: changed.event,
        provideFoldingRanges(document) {
            const lines = document.getText().split(/\r?\n/);
            const maxLines = vscode.workspace.getConfiguration('cppStickySignature', document)
                .get('maxLines', 5);
            return signatureRanges(lines, Math.max(1, maxLines))
                .map((range) => new vscode.FoldingRange(range.start, range.end));
        },
    };
    context.subscriptions.push(changed, vscode.workspace.onDidChangeConfiguration((event) => {
        if (event.affectsConfiguration('cppStickySignature')) {
            changed.fire();
        }
    }));
    // No scheme filter: diffs show git:/gitlens: documents, which clangd and cpptools skip.
    context.subscriptions.push(vscode.languages.registerFoldingRangeProvider({ language: 'cpp' }, provider));
}

module.exports = { activate, signatureRanges };
