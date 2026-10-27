import { useEffect, useMemo, useState } from "react";
import { getAccountsDays } from "../api.js";
import { money } from "../utils.js";
import PeriodFilter from "./PeriodFilter.jsx";

const pad = (n) => String(n).padStart(2, "0");
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

// "Today · 26 Oct", "Yesterday · 25 Oct", or "Fri · 24 Oct 2026"
function dayLabel(day) {
  const [y, m, d] = day.split("-").map(Number);
  const date = new Date(y, m - 1, d);
  const today = new Date();
  const yesterday = new Date();
  yesterday.setDate(today.getDate() - 1);
  const short = date.toLocaleDateString("en-IN", { day: "2-digit", month: "short" });
  if (ymd(date) === ymd(today)) return `Today · ${short}`;
  if (ymd(date) === ymd(yesterday)) return `Yesterday · ${short}`;
  return date.toLocaleDateString("en-IN", { weekday: "short", day: "2-digit", month: "short", year: "numeric" });
}

const STATUS = {
  submitted: "Waiting for approval",
  approved: "Approved · unpaid",
  paid_by_company: "Paid by company",
  paid_by_admin: "Paid by manager",
  paid_by_person: "Paid by a person",
  awaiting_confirmation: "Awaiting lender",
  reimbursed: "Reimbursed",
};

// Accounts: every day's money in / out, its expenses, and the Cash + Bank balance at the end of the day.
// Click a day to see what happened that day.
export default function AccountsPanel({ companyId, user, refreshKey }) {
  // the Period dropdown (same as the Expenses page); starts on this month
  const [from, setFrom] = useState(() => `${ymd(new Date()).slice(0, 8)}01`);
  const [to, setTo] = useState(() => ymd(new Date()));
  const [search, setSearch] = useState("");
  const [data, setData] = useState(null);
  const [error, setError] = useState("");
  const [open, setOpen] = useState(() => new Set());

  // All time (empty range) = from the very start up to today
  const range = { from: from || "2000-01-01", to: to || ymd(new Date()) };
  useEffect(() => {
    let alive = true;
    setData(null);
    setError("");
    getAccountsDays(companyId, user.id, range.from, range.to).then((res) => {
      if (!alive) return;
      if (res.success) setData(res);
      else setError(res.message || "Could not load accounts");
    });
    return () => { alive = false; };
  }, [companyId, user.id, range.from, range.to, refreshKey]);

  // search narrows each day to matching items; days with no match are hidden
  const q = search.trim().toLowerCase();
  const days = useMemo(() => {
    if (!data) return [];
    if (!q) return data.days;
    const hit = (...parts) => parts.join(" ").toLowerCase().includes(q);
    return data.days
      .map((d) => ({
        ...d,
        expenses: d.expenses.filter((x) => hit(x.description, x.category, x.by, String(x.amount))),
        income: d.income.filter((x) => hit(x.description, x.to, x.from, x.by, String(x.amount))),
        movements: d.movements.filter((x) => hit(x.label, x.memo, x.note, x.account, x.by, x.reference, String(Math.abs(x.amount)))),
      }))
      .filter((d) => d.expenses.length || d.income.length || d.movements.length);
  }, [data, q]);

  const toggle = (key) => setOpen((prev) => {
    const next = new Set(prev);
    if (next.has(key)) next.delete(key);
    else next.add(key);
    return next;
  });

  return (
    <div>
      <h1 style={{ fontSize: 26, margin: "0 0 6px" }}>Accounts</h1>
      <p style={{ color: "var(--muted)", fontSize: 13.5, margin: "0 0 18px" }}>
        Each day's money in and out, its expenses, and the Cash + Bank balance at the end of the day. Click a day for the details.
      </p>

      <div className="card accounts-filters">
        <input className="field-input" placeholder="Search expenses, income, payments…" value={search} onChange={(e) => setSearch(e.target.value)} />
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
            <div className="stat-card"><small>Expenses · {data.summary.expenseCount}</small><strong>{money(data.summary.expensesTotal)}</strong></div>
          </div>

          {days.length === 0 ? (
            <div className="card" style={{ textAlign: "center", color: "var(--muted)", padding: 28 }}>
              {q ? "Nothing matches your search in this period." : "No money in, money out or expenses in this period."}
            </div>
          ) : (
            <div className="card accounts-days">
              {days.map((d) => {
                const isOpen = open.has(d.date) || Boolean(q);
                return (
                  <div key={d.date} className={`accounts-day ${isOpen ? "open" : ""}`}>
                    <button type="button" className="accounts-day-head" onClick={() => toggle(d.date)} aria-expanded={isOpen}>
                      <span className="accounts-day-date">
                        <strong>{dayLabel(d.date)}</strong>
                        <small>
                          {d.moneyIn ? <span className="in">+{money(d.moneyIn)} in</span> : null}
                          {d.moneyOut ? <span className="out">−{money(d.moneyOut)} out</span> : null}
                          {d.expenseCount ? <span>{d.expenseCount} expense{d.expenseCount === 1 ? "" : "s"} · {money(d.expensesTotal)}</span> : null}
                          {!d.moneyIn && !d.moneyOut && !d.expenseCount ? <span>Transfers only</span> : null}
                        </small>
                      </span>
                      <span className="accounts-day-balance">
                        <small>Closing</small>
                        <strong>{money(d.closing)}</strong>
                      </span>
                      <span className="accounts-day-chevron" aria-hidden="true">{isOpen ? "▴" : "▾"}</span>
                    </button>

                    {isOpen && (
                      <div className="accounts-day-body">
                        <div className="accounts-day-line"><span>Opening balance</span><strong>{money(d.opening)}</strong></div>

                        {d.income.length > 0 && (
                          <section>
                            <h4>Income & transfers</h4>
                            {d.income.map((i) => (
                              <div key={i._id} className="accounts-item">
                                <span>
                                  <strong>{i.description || (i.kind === "transfer" ? `Transfer to ${i.to}` : `Added to ${i.to}`)}</strong>
                                  <small>{i.to} ← {i.from}{i.by ? ` · by ${i.by}` : ""}{i.kind === "transfer" ? " · between your accounts" : ""}</small>
                                </span>
                                <b className={i.kind === "transfer" ? "" : "in"}>{i.kind === "transfer" ? "" : "+"}{money(i.amount)}</b>
                              </div>
                            ))}
                          </section>
                        )}

                        {d.movements.length > 0 && (
                          <section>
                            <h4>Money moved</h4>
                            {d.movements.map((m) => (
                              <div key={m._id} className="accounts-item">
                                <span>
                                  <strong>{m.note || m.memo || m.label}</strong>
                                  <small>{m.label} · {m.account}{m.method ? ` · ${m.method}` : ""}{m.reference ? ` · Ref ${m.reference}` : ""}{m.by ? ` · by ${m.by}` : ""}</small>
                                </span>
                                <b className={m.amount > 0 ? "in" : "out"}>{m.amount > 0 ? "+" : "−"}{money(Math.abs(m.amount))}</b>
                              </div>
                            ))}
                          </section>
                        )}

                        {d.expenses.length > 0 && (
                          <section>
                            <h4>Expenses · {money(d.expenses.reduce((s, x) => s + x.amount, 0))}</h4>
                            {d.expenses.map((x) => (
                              <div key={x._id} className="accounts-item">
                                <span>
                                  <strong>{x.description}</strong>
                                  <small>{x.category} · {x.by} · {STATUS[x.lifecycle] || x.lifecycle}</small>
                                </span>
                                <b>{money(x.amount)}</b>
                              </div>
                            ))}
                          </section>
                        )}

                        <div className="accounts-day-line"><span>Closing balance</span><strong>{money(d.closing)}</strong></div>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
          <p style={{ color: "var(--muted)", fontSize: 12, marginTop: 10 }}>
            Balances are Cash + all bank accounts. Expenses are listed on their own date; only those paid from Cash/Bank change the balance.
          </p>
        </>
      )}
    </div>
  );
}
