import { useCallback, useEffect, useState } from "react";
import { getExpenseAnalysis } from "../api.js";
import { formatDate, money } from "../utils.js";
import { TableCard } from "./DataTable.jsx";

const BAR = "var(--forest)";
const BAR_SOFT = "#9CC9B4";
const GRID = "var(--slate-border-2)";
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const monthLabel = (key, withYear) => `${MONTHS[Number(key.slice(5)) - 1]}${withYear ? ` ${key.slice(2, 4)}` : ""}`;

function Tile({ label, value, sub, subColor }) {
  return (
    <div className="stat-card">
      <div style={{ fontSize: 11, color: "var(--muted)", fontWeight: 700, letterSpacing: 0.6, marginBottom: 6 }}>{label}</div>
      <div style={{ fontSize: 20, fontWeight: 800, color: "var(--dark-text)" }}>{value}</div>
      {sub && <small style={{ color: subColor || "var(--muted)", fontWeight: 600 }}>{sub}</small>}
    </div>
  );
}

function Panel({ title, action, children }) {
  return (
    <div className="card" style={{ marginBottom: 16 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, marginBottom: 12 }}>
        <h3 style={{ fontSize: 16, margin: 0 }}>{title}</h3>
        {action}
      </div>
      {children}
    </div>
  );
}

// Vertical bars over time / weekday. Whole column is the hover target; tooltip names value and count.
function ColumnChart({ rows, label, height = 180, highlightLast = false }) {
  const [hover, setHover] = useState(null);
  const max = Math.max(...rows.map((r) => r.total), 0);
  const nice = max > 0 ? Math.pow(10, Math.floor(Math.log10(max))) * Math.ceil(max / Math.pow(10, Math.floor(Math.log10(max)))) : 1;
  return (
    <div style={{ position: "relative", paddingLeft: 56 }}>
      {[1, 0.5, 0].map((f) => (
        <div key={f} style={{ position: "absolute", left: 56, right: 0, top: (1 - f) * height, borderTop: `1px solid ${GRID}` }}>
          <span style={{ position: "absolute", left: -56, top: -8, width: 50, textAlign: "right", fontSize: 11, color: "var(--muted)" }}>
            {f === 0 ? "₹0" : `₹${Math.round(nice * f).toLocaleString("en-IN")}`}
          </span>
        </div>
      ))}
      <div style={{ display: "flex", alignItems: "flex-end", height, gap: 2, position: "relative" }}>
        {rows.map((r, i) => {
          const h = nice ? (r.total / nice) * height : 0;
          const active = hover === i;
          return (
            <div
              key={i}
              onMouseEnter={() => setHover(i)}
              onMouseLeave={() => setHover(null)}
              aria-label={`${label(r, true)}: ${money(r.total)} across ${r.count} expenses`}
              style={{ flex: 1, height: "100%", display: "flex", alignItems: "flex-end", justifyContent: "center", position: "relative", cursor: "default" }}
            >
              <div
                style={{
                  width: "min(70%, 36px)",
                  height: Math.max(r.total > 0 ? 2 : 0, h),
                  background: highlightLast && i === rows.length - 1 ? BAR : active ? BAR : BAR_SOFT,
                  borderRadius: "4px 4px 0 0",
                  transition: "background 0.12s",
                }}
              />
              {active && (
                <div style={{ position: "absolute", bottom: Math.min(h + 8, height - 10), left: "50%", transform: "translateX(-50%)", background: "var(--dark-text)", color: "#fff", borderRadius: 8, padding: "6px 9px", fontSize: 12, whiteSpace: "nowrap", zIndex: 2, pointerEvents: "none" }}>
                  <strong>{label(r, true)}</strong><br />{money(r.total)} · {r.count} expense{r.count === 1 ? "" : "s"}
                </div>
              )}
            </div>
          );
        })}
      </div>
      <div style={{ display: "flex", gap: 2, marginTop: 6 }}>
        {rows.map((r, i) => (
          <div key={i} style={{ flex: 1, textAlign: "center", fontSize: 11, color: "var(--muted)", whiteSpace: "nowrap", overflow: "hidden" }}>{label(r, false)}</div>
        ))}
      </div>
    </div>
  );
}

// Ranked horizontal bars with the value written at the end (direct labels; no legend needed).
function RankedBars({ rows, nameKey, extra }) {
  const max = Math.max(...rows.map((r) => r.total), 0) || 1;
  const sum = rows.reduce((s, r) => s + r.total, 0) || 1;
  if (!rows.length) return <div style={{ color: "var(--muted)", fontSize: 13 }}>No data in this period.</div>;
  return rows.map((r) => (
    <div key={r[nameKey] + (r.key || "")} title={`${r[nameKey]}: ${money(r.total)} (${r.count})`} style={{ display: "grid", gridTemplateColumns: "minmax(90px, 30%) 1fr auto", alignItems: "center", gap: 10, marginBottom: 8, fontSize: 13 }}>
      <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{r[nameKey]}</span>
      <div style={{ background: GRID, borderRadius: 4, height: 10 }}>
        <div style={{ width: `${(r.total / max) * 100}%`, minWidth: 2, height: "100%", background: BAR, borderRadius: 4 }} />
      </div>
      <span style={{ textAlign: "right", whiteSpace: "nowrap" }}>
        <strong>{money(r.total)}</strong>
        <small style={{ color: "var(--muted)" }}> · {Math.round((r.total / sum) * 100)}%{extra ? ` · ${extra(r)}` : ""}</small>
      </span>
    </div>
  ));
}

// Manager-only view of spending patterns: trend, categories, people, weekdays, outliers, repeats.
export default function ExpenseAnalysis({ companyId, userId, refreshKey }) {
  const [months, setMonths] = useState(12);
  const [data, setData] = useState(null);
  const [error, setError] = useState("");
  const [showTable, setShowTable] = useState(false);

  const load = useCallback(async () => {
    setData(null);
    const res = await getExpenseAnalysis(companyId, userId, months);
    if (res.success) {
      setData(res);
      setError("");
    } else setError(res.message || "Could not load analysis");
  }, [companyId, userId, months]);

  useEffect(() => {
    load();
  }, [load, refreshKey]);

  const s = data?.summary;
  const change = s?.changePct;

  return (
    <>
      <div className="page-sticky-header">
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
          <h1 style={{ fontSize: 22, margin: 0 }}>Analytics</h1>
          <div style={{ display: "flex", gap: 6 }}>
            {[3, 6, 12].map((m) => (
              <button key={m} className={`btn ${months === m ? "btn-dark" : "btn-outline"}`} onClick={() => setMonths(m)}>{m} months</button>
            ))}
          </div>
        </div>
        <p style={{ color: "var(--muted)", margin: "0 0 14px" }}>Spending patterns and monthly trends. Rejected and group expenses are excluded.</p>

        {s && (
          <div className="m-tiles-2" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(170px, 1fr))", gap: 12, marginBottom: 0 }}>
            <Tile
              label="THIS MONTH"
              value={money(s.thisMonth)}
              sub={change === null ? "No spend last month" : `${change > 0 ? "▲" : change < 0 ? "▼" : "■"} ${Math.abs(change)}% vs last month (${money(s.lastMonth)})`}
              subColor={change > 0 ? "var(--terracotta)" : change < 0 ? "var(--forest)" : undefined}
            />
            <Tile label={`TOTAL · ${data.months} MONTHS`} value={money(s.total)} sub={`${s.count} expenses`} />
            <Tile label="MONTHLY AVERAGE" value={money(s.monthlyAverage)} sub={`Avg expense ${money(s.average)}`} />
            <Tile label="LARGEST EXPENSE" value={s.largest ? money(s.largest.amount) : "—"} sub={s.largest ? `${s.largest.description} · ${formatDate(s.largest.date)}` : ""} />
          </div>
        )}
      </div>

      {error ? (
        <div className="card" style={{ color: "var(--terracotta)" }}>{error}</div>
      ) : !data ? (
        <div style={{ display: "flex", justifyContent: "center", padding: 48 }}><div className="spinner" /></div>
      ) : (
        <>
          <Panel
            title="Monthly spend"
            action={<button className="btn btn-outline" style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setShowTable((v) => !v)}>{showTable ? "Chart" : "Table"}</button>}
          >
            {showTable ? (
              <div className="dt-card" style={{ marginBottom: 0 }}>
                <div className="dt-scroll">
                  <table className="dt">
                    <thead><tr><th>Month</th><th className="num">Expenses</th><th className="num">Total</th></tr></thead>
                    <tbody>
                      {data.monthly.map((m) => (
                        <tr key={m.month}>
                          <td>{monthLabel(m.month, true)}</td>
                          <td className="num" style={{ fontWeight: 400 }}>{m.count}</td>
                          <td className="num">{money(m.total)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            ) : (
              <ColumnChart rows={data.monthly} label={(r, full) => monthLabel(r.month, full || data.months > 12)} highlightLast />
            )}
          </Panel>

          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))", gap: 16 }}>
            <Panel title="By category">
              <RankedBars rows={data.categories} nameKey="category" extra={(r) => `avg ${money(r.avg)}`} />
            </Panel>
            <Panel title="Top spenders">
              <RankedBars rows={data.people} nameKey="name" extra={(r) => `${r.count} exp`} />
            </Panel>
          </div>

          <Panel title="Spend by day of week">
            <ColumnChart rows={data.weekday} label={(r) => WEEKDAYS[r.day]} height={120} />
          </Panel>

          <TableCard title="Unusual expenses" meta="At least 2× the average for their category" items={data.unusual}>
            {(rows) => (
              <>
            {data.unusual.length === 0 ? (
              <div className="dt-empty">Nothing unusual in this period.</div>
            ) : (
              <table className="dt">
                <thead>
                  <tr><th>Date</th><th>Description</th><th>Category</th><th>Posted by</th><th className="num">Category avg</th><th className="num">Times avg</th><th className="num">Amount</th></tr>
                </thead>
                <tbody>
                  {rows.map((u) => (
                    <tr key={u._id}>
                      <td className="nowrap">{formatDate(u.date)}</td>
                      <td className="dt-wrap-text dt-strong">{u.description}</td>
                      <td>{u.category}</td>
                      <td>{u.by || "—"}</td>
                      <td className="num" style={{ fontWeight: 400 }}>{money(u.categoryAvg)}</td>
                      <td className="num out">⚠ {u.ratio}×</td>
                      <td className="num">{money(u.amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          
              </>
            )}
          </TableCard>

          <TableCard title="Recurring expenses" meta="Same description in 3 or more different months" items={data.recurring}>
            {(rows) => (
              <>
            {data.recurring.length === 0 ? (
              <div className="dt-empty">No recurring expenses found yet.</div>
            ) : (
              <table className="dt">
                <thead>
                  <tr><th>Description</th><th className="center">Months</th><th className="center">Times</th><th>Last</th><th className="num">Average</th><th className="num">Total</th></tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.description}>
                      <td className="dt-wrap-text dt-strong">{r.description}</td>
                      <td className="center">{r.months}</td>
                      <td className="center">{r.count}</td>
                      <td className="nowrap">{formatDate(r.lastDate)}</td>
                      <td className="num">{money(r.avgAmount)}</td>
                      <td className="num" style={{ fontWeight: 400 }}>{money(r.total)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          
              </>
            )}
          </TableCard>
        </>
      )}
    </>
  );
}
