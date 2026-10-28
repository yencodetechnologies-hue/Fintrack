// The one table look used across the app: a title bar ("N records · Page x of y"), uppercase column headers,
// alternating light rows, and numbered page buttons underneath.

export function TableCard({ title, meta, actions, children, page, pages, onPage, className = "" }) {
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
      <div className="dt-scroll">{children}</div>
      {pages > 1 && <Pager page={page} pages={pages} onChange={onPage} />}
    </div>
  );
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
  `${count} ${count === 1 ? noun.replace(/s$/, "") : noun}${pages > 1 ? ` · Page ${page} of ${pages}` : ""}`;

// client-side paging for lists that arrive whole
export function pageOf(rows, page, size) {
  const pages = Math.max(1, Math.ceil(rows.length / size));
  const current = Math.min(Math.max(1, page), pages);
  return { rows: rows.slice((current - 1) * size, current * size), page: current, pages };
}
