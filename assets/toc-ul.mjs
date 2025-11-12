// Build a nested <ul> TOC from h2–h6, ruby-aware, Unicode slug-safe.
// Usage in HTML: <script type="module" src="/assets/toc-ul.mjs"></script>

export function buildTOCUL({
  rootSelector = null,      // limit scan to a container (e.g., '.quarto-article')
  targetSelector = '#toc',  // where to inject the <ul>; if missing, just console.log
  minLevel = 2,
  maxLevel = 6
} = {}) {
  const scope = rootSelector ? document.querySelector(rootSelector) : document;
  if (!scope) return;

  const selector = Array.from({ length: maxLevel - minLevel + 1 }, (_, i) => `h${i + minLevel}`).join(', ');
  const headers = Array.from(scope.querySelectorAll(selector));
  if (!headers.length) return;

  // Ensure unique IDs (prefer existing). Ruby-aware title fallback.
  const seen = new Map();
  for (const h of headers) {
    if (!h.id || !h.id.trim()) {
      const base = getRubyBaseText(h) || h.textContent || '';
      h.id = uniquify(slugify(base), seen);
    } else {
      h.id = uniquify(h.id, seen);
    }
  }

  // Flatten → tree
  const nodes = headers.map(h => ({
    level: Number(h.tagName.slice(1)),
    text: getRubyBaseText(h).trim(), // display title without <rt>/<rp>
    id: h.id,
    children: []
  }));
  const tree = toTree(nodes);

  // Render DOM <ul>
  const ul = renderUL(tree);

  // Inject if target exists
  const target = document.querySelector(targetSelector);
  if (target) {
    target.innerHTML = '';
    target.appendChild(ul.cloneNode(true));
  }

  // Also output the HTML string to console
  const tmp = document.createElement('div');
  tmp.appendChild(ul);
  console.log('--- TOC (<ul>) ---\n' + tmp.innerHTML);
}

// Auto-run after load so dynamic blocks have rendered
window.addEventListener('load', () => buildTOCUL({minLevel:3}));

// ---------- helpers ----------

// Extract visible base text of a heading, ignoring <rt> inside <ruby>
function getRubyBaseText(el) {
  const clone = el.cloneNode(true);
  clone.querySelectorAll('rt, rp').forEach(n => n.remove());
  return (clone.textContent || '').replace(/\s+/g, ' ').trim();
}

// Unicode-friendly slug: keep letters/numbers (incl. CJK), dashes, spaces; collapse spaces to hyphen
function slugify(s) {
  return s
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[\u0300-\u036f]/g, '')              // strip combining marks
    .replace(/[^\p{Letter}\p{Number}\-\s\u3000]/gu, '') // drop punctuation except dash/space
    .replace(/[\s\u3000]+/g, '-')                 // spaces (ASCII & full-width) → hyphen
    .replace(/^-+|-+$/g, '');                     // trim hyphens
}

// Ensure uniqueness (adds -2, -3, …)
function uniquify(id, seen) {
  let base = id || 'section';
  let n = (seen.get(base) || 0) + 1;
  seen.set(base, n);
  return n === 1 ? base : `${base}-${n}`;
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

function renderUL(list) {
  const ul = document.createElement('ul');
  for (const node of list) {
    const li = document.createElement('li');
    const a = document.createElement('a');
    a.textContent = node.text;
    a.setAttribute('href', `#${node.id}`);
    li.appendChild(a);
    if (node.children.length) li.appendChild(renderUL(node.children));
    ul.appendChild(li);
  }
  return ul;
}

