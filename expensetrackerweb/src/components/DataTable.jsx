import { useState } from "react";

// The one table look used across the app: a title bar ("N records · Page x of y"), uppercase column headers,
// alternating light rows, and numbered page buttons underneath.

// Paging: either the page controls it (page / pages / onPage / pageSize / onPageSize / count), or pass `items` and
// a function as children — the card then pages the list itself and hands the current page's rows to the function.
export function TableCard({ title, meta, actions, children, items, page, pages, onPage, pageSize, onPageSize, count = 0, className = "" }) {
  const [ownPage, setOwnPage] = useState(1);
  const [ownSize, setOwnSize] = usePageSize();
  let body = children;
  if (Array.isArray(items)) {
    const paged = pageOf(items, ownPage, ownSize);
    body = typeof children === "function" ? children(paged.rows) : children;
    page = paged.page;
    pages = paged.pages;
    onPage = setOwnPage;
    count = items.length;
    pageSize = ownSize;
    onPageSize = (n) => { setOwnSize(n); setOwnPage(1); };
    if (meta && items.length) meta = `${meta} · Page ${paged.page} of ${paged.pages}`;
  }
  // the footer always shows on a paged table (rows per page + page buttons), however short the list
  const showSize = Boolean(onPageSize) && count > 0;
  const showPager = Boolean(onPage) && (pages > 1 || showSize);
  return (
    <div className={`dt-card ${className}`}>
      {(title || meta || actions) && (
        <div className="dt-title">
          {title && <h3>{title}</h3>}
          <span className="dt-title-right">
            {actions}
            {meta && <span className="dt-meta">{meta}</span>}
          </span>
        </div>
      )}
      <div className="dt-scroll">{body}</div>
      {(pages > 1 || showSize) && (
        <div className="dt-foot">
          {showSize ? (
            <label className="dt-size">
              Rows per page
              <select value={pageSize} onChange={(e) => onPageSize(Number(e.target.value))}>
                {PAGE_SIZES.map((n) => <option key={n} value={n}>{n}</option>)}
              </select>
            </label>
          ) : <span />}
          {showPager ? <Pager page={page} pages={Math.max(1, pages || 1)} onChange={onPage} /> : <span />}
          <span className="dt-foot-spacer" />
        </div>
      )}
    </div>
  );
}

export const PAGE_SIZES = [10, 25, 50, 100];
const SIZE_KEY = "et_page_size";

// rows per page, chosen by the viewer and remembered in this browser (same choice for every table)
export function usePageSize(fallback = 25) {
  const [size, setSize] = useState(() => {
    try {
      const saved = Number(localStorage.getItem(SIZE_KEY));
      return PAGE_SIZES.includes(saved) ? saved : fallback;
    } catch {
      return fallback;
    }
  });
  const change = (n) => {
    setSize(n);
    try {
      localStorage.setItem(SIZE_KEY, String(n));
    } catch {
      // private window / blocked storage: the choice just lasts for this visit
    }
  };
  return [size, change];
}

// ‹ Prev 1 2 3 … 17 Next ›  (shows every page up to 9, otherwise the first, last and the ones around the current)
export function Pager({ page, pages, onChange }) {
  const list = [];
  if (pages <= 9) {
    for (let i = 1; i <= pages; i += 1) list.push(i);
  } else {
    const from = Math.max(2, page - 2);
    const to = Math.min(pages - 1, page + 2);
    list.push(1);
    if (from > 2) list.push("…a");
    for (let i = from; i <= to; i += 1) list.push(i);
    if (to < pages - 1) list.push("…b");
    list.push(pages);
  }
  return (
    <nav className="dt-pager" aria-label="Pages">
      <button type="button" disabled={page <= 1} onClick={() => onChange(page - 1)}>‹ Prev</button>
      {list.map((p) =>
        typeof p === "number" ? (
          <button type="button" key={p} className={p === page ? "active" : ""} aria-current={p === page ? "page" : undefined} onClick={() => onChange(p)}>
            {p}
          </button>
        ) : (
          <span key={p} className="dt-gap">…</span>
        )
      )}
      <button type="button" disabled={page >= pages} onClick={() => onChange(page + 1)}>Next ›</button>
    </nav>
  );
}

// "169 records · Page 1 of 17"
export const tableMeta = (count, page, pages, noun = "records") =>
  `${count} ${count === 1 ? noun.replace(/s$/, "") : noun}${pages ? ` · Page ${page} of ${pages}` : ""}`;

// client-side paging for lists that arrive whole
export function pageOf(rows, page, size) {
  const pages = Math.max(1, Math.ceil(rows.length / size));
  const current = Math.min(Math.max(1, page), pages);
  return { rows: rows.slice((current - 1) * size, current * size), page: current, pages };
}
