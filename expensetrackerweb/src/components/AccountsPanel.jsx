import { useEffect, useState } from "react";
import { getAccountsEntries } from "../api.js";
import { money } from "../utils.js";
import { TableCard, tableMeta, usePageSize } from "./DataTable.jsx";
import PeriodFilter from "./PeriodFilter.jsx";

const pad = (n) => String(n).padStart(2, "0");
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

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
  const [PAGE_SIZE, setPageSize] = usePageSize();
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
  }, [companyId, user.id, range.from, range.to, query, page, PAGE_SIZE, refreshKey]);


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
            <div className="stat-card"><small>Debit (out)</small><strong className="out">−{money(data.summary.moneyOut)}</strong></div>
            <div className="stat-card"><small>Credit (in)</small><strong className="in">+{money(data.summary.moneyIn)}</strong></div>
            <div className="stat-card"><small>Closing balance</small><strong>{money(data.summary.closing)}</strong></div>
            <div className="stat-card"><small>Transactions</small><strong>{data.summary.count}</strong></div>
          </div>

          <TableCard title="Statement" meta={tableMeta(data.total, data.page, data.pages, "entries")} page={data.page} pages={data.pages} onPage={setPage} count={data.total} pageSize={PAGE_SIZE} onPageSize={(n) => { setPageSize(n); setPage(1); }} className={loading ? "dt-loading" : ""}>
            {data.total === 0 ? (
              <div className="dt-empty">{query ? "Nothing matches your search in this period." : "No money in or out in this period."}</div>
            ) : (
              <table className="dt">
                <thead>
                  <tr>
                    <th>Time</th>
                    <th>Details</th>
                    <th>Account</th>
                    <th>Method / Ref</th>
                    <th className="num">Debit (out)</th>
                    <th className="num">Credit (in)</th>
                    <th className="num">Balance</th>
                  </tr>
                </thead>
                <tbody>
                  {data.entries.flatMap((r, i) => {
                    const w = when(r.at);
                    const transfer = r.kind === "transfer";
                    // a black day row before the first entry of each day; the entries show just their time
                    const newDay = i === 0 || when(data.entries[i - 1].at).date !== w.date;
                    const dayRows = newDay ? data.entries.filter((e) => when(e.at).date === w.date) : [];
                    const dayIn = dayRows.reduce((t, e) => t + (e.kind !== "transfer" && e.amount > 0 ? e.amount : 0), 0);
                    const dayOut = dayRows.reduce((t, e) => t + (e.kind !== "transfer" && e.amount < 0 ? -e.amount : 0), 0);
                    return [
                      newDay && (
                        <tr key={`day-${w.date}`} className="dt-group">
                          <td colSpan={7} className="dt-day">
                            {w.date}
                            <span className="dt-group-total">
                              {dayRows.length} {dayRows.length === 1 ? "entry" : "entries"}
                              {dayOut > 0 ? ` · out ${money(dayOut)}` : ""}
                              {dayIn > 0 ? ` · in ${money(dayIn)}` : ""}
                            </span>
                          </td>
                        </tr>
                      ),
                      <tr key={r._id}>
                        <td className="nowrap"><span className="dt-time">{w.time}</span></td>
                        <td className="dt-wrap-text">
                          <span className="dt-strong">{r.details || r.label}</span>
                          <span className="dt-sub">{[r.details ? r.label : "", r.category, r.by ? `by ${r.by}` : ""].filter(Boolean).join(" · ")}</span>
                        </td>
                        <td>{r.account || "—"}</td>
                        <td>{r.method || "—"}{r.reference && <span className="dt-sub dt-mono">{r.reference}</span>}</td>
                        {transfer ? (
                          <td className="num muted" colSpan={2} style={{ textAlign: "center" }}>⇄ moved {money(r.transferAmount)}</td>
                        ) : (
                          <>
                            <td className="num out">{r.amount < 0 ? `−${money(-r.amount)}` : "—"}</td>
                            <td className="num in">{r.amount > 0 ? `+${money(r.amount)}` : "—"}</td>
                          </>
                        )}
                        <td className="num">{money(r.balance)}</td>
                      </tr>,
                    ];
                  })}
                </tbody>
              </table>
            )}
          </TableCard>

          <p style={{ color: "var(--muted)", fontSize: 12, marginTop: 10 }}>
            Balance is Cash + all bank accounts after each entry. A transfer between your own accounts doesn't change it.
            Expenses a person paid themselves don't appear here until the company pays them back.
          </p>
        </>
      )}
    </div>
  );
}
