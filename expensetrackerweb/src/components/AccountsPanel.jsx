import { useEffect, useState } from "react";
import { getAccountsEntries } from "../api.js";
import { money } from "../utils.js";
import PeriodFilter from "./PeriodFilter.jsx";

const pad = (n) => String(n).padStart(2, "0");
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const PAGE_SIZE = 25;

const when = (at) => {
  const d = new Date(at);
  return {
    date: d.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" }),
    time: d.toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit" }),
  };
};

// Accounts: a statement of every money movement — each payment out of Cash/Bank, each income in, each transfer —
// newest first, with the Cash + Bank balance after it. Searched and paged on the server.
export default function AccountsPanel({ companyId, user, refreshKey }) {
  // the Period dropdown (same as the Expenses page); starts on this month
  const [from, setFrom] = useState(() => `${ymd(new Date()).slice(0, 8)}01`);
  const [to, setTo] = useState(() => ymd(new Date()));
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState(""); // search sent to the server, a moment after typing stops
  const [page, setPage] = useState(1);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    const t = setTimeout(() => setQuery(search.trim()), 350);
    return () => clearTimeout(t);
  }, [search]);

  // a new period or search starts again at page 1
  useEffect(() => setPage(1), [from, to, query]);

  // All time (empty range) = from the very start up to today
  const range = { from: from || "2000-01-01", to: to || ymd(new Date()) };
  useEffect(() => {
    let alive = true;
    setLoading(true);
    setError("");
    getAccountsEntries(companyId, user.id, { from: range.from, to: range.to, q: query, page, limit: PAGE_SIZE }).then((res) => {
      if (!alive) return;
      setLoading(false);
      if (res.success) setData(res);
      else setError(res.message || "Could not load accounts");
    });
    return () => { alive = false; };
  }, [companyId, user.id, range.from, range.to, query, page, refreshKey]);

  const first = data ? (data.page - 1) * data.limit + 1 : 0;
  const last = data ? Math.min(data.total, data.page * data.limit) : 0;

  return (
    <div>
      <h1 style={{ fontSize: 22, margin: "0 0 6px" }}>Accounts</h1>
      <p style={{ color: "var(--muted)", fontSize: 14, margin: "0 0 18px" }}>
        Every money in and out of your Cash and bank accounts, with the balance after each one.
      </p>

      <div className="card accounts-filters">
        <input className="field-input" placeholder="Search details, account, person, reference, amount…" value={search} onChange={(e) => setSearch(e.target.value)} />
        <PeriodFilter from={from} to={to} initialMode="month" onChange={(f, t) => { setFrom(f); setTo(t); }} />
      </div>

      {error ? (
        <div className="card" style={{ color: "var(--terracotta)" }}>{error}</div>
      ) : !data ? (
        <div style={{ display: "flex", justifyContent: "center", padding: 50 }}><div className="spinner dark" /></div>
      ) : (
        <>
          <div className="accounts-summary">
            <div className="stat-card"><small>Opening balance</small><strong>{money(data.summary.opening)}</strong></div>
            <div className="stat-card"><small>Money in</small><strong className="in">+{money(data.summary.moneyIn)}</strong></div>
            <div className="stat-card"><small>Money out</small><strong className="out">−{money(data.summary.moneyOut)}</strong></div>
            <div className="stat-card"><small>Closing balance</small><strong>{money(data.summary.closing)}</strong></div>
            <div className="stat-card"><small>Transactions</small><strong>{data.summary.count}</strong></div>
          </div>

          {data.total === 0 ? (
            <div className="card" style={{ textAlign: "center", color: "var(--muted)", padding: 28 }}>
              {query ? "Nothing matches your search in this period." : "No money in or out in this period."}
            </div>
          ) : (
            <div className={`card accounts-statement ${loading ? "loading" : ""}`}>
              <div className="statement-row statement-head" aria-hidden="true">
                <span>Date</span>
                <span>Details</span>
                <span className="num">Money in</span>
                <span className="num">Money out</span>
                <span className="num">Balance</span>
              </div>
              {data.entries.map((r) => {
                const w = when(r.at);
                const transfer = r.kind === "transfer";
                return (
                  <div key={r._id} className="statement-row">
                    <span className="statement-date">
                      <strong>{w.date}</strong>
                      <small>{w.time}</small>
                    </span>
                    <span className="statement-details">
                      <strong>{r.details || r.label}</strong>
                      <small>
                        {[r.details ? r.label : "", r.account, r.category, r.method, r.reference ? `Ref ${r.reference}` : "", r.by ? `by ${r.by}` : ""]
                          .filter(Boolean)
                          .join(" · ")}
                      </small>
                    </span>
                    {transfer ? (
                      <span className="num statement-transfer" data-label="Moved">{money(r.transferAmount)}</span>
                    ) : (
                      <>
                        <span className="num in" data-label="In">{r.amount > 0 ? `+${money(r.amount)}` : "—"}</span>
                        <span className="num out" data-label="Out">{r.amount < 0 ? `−${money(-r.amount)}` : "—"}</span>
                      </>
                    )}
                    <span className="num statement-balance" data-label="Balance">{money(r.balance)}</span>
                  </div>
                );
              })}
            </div>
          )}

          {data.total > 0 && (
            <div className="statement-pager">
              <span>{first}–{last} of {data.total}</span>
              <div>
                <button type="button" className="btn btn-outline btn-sm" disabled={loading || data.page <= 1} onClick={() => setPage(1)}>« First</button>
                <button type="button" className="btn btn-outline btn-sm" disabled={loading || data.page <= 1} onClick={() => setPage(data.page - 1)}>‹ Prev</button>
                <strong>Page {data.page} of {data.pages}</strong>
                <button type="button" className="btn btn-outline btn-sm" disabled={loading || data.page >= data.pages} onClick={() => setPage(data.page + 1)}>Next ›</button>
                <button type="button" className="btn btn-outline btn-sm" disabled={loading || data.page >= data.pages} onClick={() => setPage(data.pages)}>Last »</button>
              </div>
            </div>
          )}
          <p style={{ color: "var(--muted)", fontSize: 12, marginTop: 10 }}>
            Balance is Cash + all bank accounts after each entry. A transfer between your own accounts doesn't change it.
            Expenses a person paid themselves don't appear here until the company pays them back.
          </p>
        </>
      )}
    </div>
  );
}
