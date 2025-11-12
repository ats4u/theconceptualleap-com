
// Minimal TOC → console (Markdown + YAML), ruby-aware slugging
// Usage in HTML: <script type="module" src="/assets/toc-console.mjs"></script>

export function buildTOC({ rootSelector = null, minLevel = 2, maxLevel = 6 } = {}) {
  const scope = rootSelector ? document.querySelector(rootSelector) : document;
  if (!scope) return;

  const selector = Array.from({ length: maxLevel - minLevel + 1 }, (_, i) => `h${i + minLevel}`).join(', ');
  const headers = Array.from(scope.querySelectorAll(selector));
  if (!headers.length) return;

  // Ensure IDs; prefer existing ids, else ruby-aware title → slug
  for (const h of headers) {
    if (!h.id) {
      const baseTitle = getRubyBaseText(h); // title string fallback
      h.id = slugify(baseTitle);
    }
  }

  // Build nodes with ruby-base display text
  const nodes = headers.map(h => ({
    level: Number(h.tagName.slice(1)),
    text: getRubyBaseText(h).trim(), // display text without <rt>
    id: h.id,
    children: []
  }));

  const tree = toTree(nodes);

  const md  = renderMarkdown(tree);
  const yml = renderYAML(tree);

  console.log('--- TOC (Markdown) ---\n' + md);
  console.log('--- TOC (YAML for _quarto.yml) ---\n' + yml);
}

// Auto-run after load so dynamic blocks have rendered
window.addEventListener('load', () => buildTOC());

// -------- helpers --------

// Extract visible base text of a heading, ignoring <rt> inside <ruby>
function getRubyBaseText(el) {
  const clone = el.cloneNode(true);
  // Remove ruby annotations
  clone.querySelectorAll('rt').forEach(rt => rt.remove());
  // Optional: drop <rp> parentheses if present
  clone.querySelectorAll('rp').forEach(rp => rp.remove());
  // The remaining textContent is the base (e.g., 漢字 for <ruby>漢字<rt>かんじ</rt></ruby>)
  return clone.textContent.replace(/\s+/g, ' ').trim();
}

// Unicode-friendly slugify that preserves CJK letters and numbers, collapses spaces (incl. full-width) to '-'
function slugify(s) {
  return s
    .normalize('NFKC')
    .toLowerCase()
    // remove combining marks
    .replace(/[\u0300-\u036f]/g, '')
    // strip punctuation (keep letters/numbers, dash, space). Supports Unicode properties.
    .replace(/[^\p{Letter}\p{Number}\-\s\u3000]/gu, '')
    // collapse spaces (ASCII + full-width) to single hyphen
    .replace(/[\s\u3000]+/g, '-')
    // trim hyphens
    .replace(/^-+|-+$/g, '');
}

function toTree(nodes) {
  const root = { level: 1, children: [] };
  const stack = [root];
  for (const n of nodes) {
    while (stack.length && n.level <= stack[stack.length - 1].level) stack.pop();
    stack[stack.length - 1].children.push(n);
    stack.push(n);
  }
  return root.children; // top-level = h2
}

function renderMarkdown(tree) {
  const out = [];
  (function walk(list, depth) {
    for (const n of list) {
      out.push(`${'  '.repeat(depth)}- [${escapeMD(n.text)}](#${n.id})`);
      if (n.children.length) walk(n.children, depth + 1);
    }
  })(tree, 0);
  return out.join('\n');
}

function renderYAML(tree) {
  const lines = ['sidebar:', '  contents:'];
  (function dump(list, indent) {
    for (const n of list) {
      lines.push(`${' '.repeat(indent)}- text: "${escapeYAML(n.text)}"`);
      lines.push(`${' '.repeat(indent)}  href: "#${n.id}"`);
      if (n.children.length) {
        lines.push(`${' '.repeat(indent)}  contents:`);
        dump(n.children, indent + 4);
      }
    }
  })(tree, 4);
  return lines.join('\n');
}

function escapeMD(s) { return s.replace(/([\[\]\(\)\\`*_])/g, '\\$1'); }
function escapeYAML(s) { return s.replace(/"/g, '\\"'); }

