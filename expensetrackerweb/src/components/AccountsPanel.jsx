import { useEffect, useState } from "react";
import { deleteAccountsEntry, editAccountsEntry, getAccountsEntries, getAccountsExportUrl } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import Modal from "./Modal.jsx";
import { money, PAYMENT_METHODS } from "../utils.js";
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
// fund: one account's statement ("cash" or a bank account id), shown inside Company Funds (embedded: no page heading)
export default function AccountsPanel({ companyId, user, canEdit = false, onChanged, onOpenExpense, onOpenLoan, refreshKey, fund = "", fundName = "", embedded = false, movesOnly = false }) {
  const { showToast } = useToast();
  // the row shown in the details popup, and its amount while being edited: { row, value }
  const [editing, setEditing] = useState(null);
  const [viewing, setViewing] = useState(null);
  const [saving, setSaving] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [reload, setReload] = useState(0);
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
  useEffect(() => setPage(1), [from, to, query, fund]);

  // All time (empty range) = from the very start up to today
  const range = { from: from || "2000-01-01", to: to || ymd(new Date()) };
  useEffect(() => {
    let alive = true;
    setLoading(true);
    setError("");
    getAccountsEntries(companyId, user.id, { from: range.from, to: range.to, q: query, page, limit: PAGE_SIZE, fund, movesOnly }).then((res) => {
      if (!alive) return;
      setLoading(false);
      if (res.success) setData(res);
      else setError(res.message || "Could not load accounts");
    });
    return () => { alive = false; };
  }, [companyId, user.id, range.from, range.to, query, page, PAGE_SIZE, refreshKey, reload, fund, movesOnly]);

  // editing = { id, amount, details, method, reference, date } (the form in the details popup)
  async function saveAmount() {
    const row = viewing;
    const changes = {};
    if (row.amountEditable) {
      const value = Number(editing.amount);
      if (!(value > 0)) return showToast("Enter an amount greater than zero", "error");
      changes.amount = value;
    }
    changes.details = editing.details;
    if (!String(row.editId).startsWith("income:")) {
      changes.method = editing.method;
      changes.reference = editing.reference;
    }
    if (editing.date) changes.date = editing.date;
    setSaving(true);
    const res = await editAccountsEntry(companyId, user.id, editing.id, changes);
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not save the changes", "error");
    showToast("Saved · balances adjusted");
    setEditing(null);
    setViewing(null);
    setReload((n) => n + 1);
    onChanged?.();
  }

  // money added / a transfer: the Admin can remove it (the money comes back out of that account)
  async function deleteEntry(row) {
    if (!window.confirm(`Delete this entry? ${money(row.kind === "transfer" ? row.transferAmount : Math.abs(row.amount))} will be taken back out of ${row.account}.`)) return;
    setSaving(true);
    const res = await deleteAccountsEntry(companyId, user.id, row.editId);
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not delete it", "error");
    showToast("Deleted · balances adjusted");
    setViewing(null);
    setEditing(null);
    setReload((n) => n + 1);
    onChanged?.();
  }

  // a row click: its expense (full details + Edit), or this entry's details
  function openRow(r) {
    if (r.kind === "company_paid" && r.expenseId && onOpenExpense?.(r.expenseId)) return;
    setEditing(null);
    setViewing(r);
  }

  async function handleExport() {
    if (exporting) return;
    setExporting(true);
    try {
      const exportUrl = getAccountsExportUrl(companyId, user.id, {
        from: range.from,
        to: range.to,
        q: query,
        fund,
        movesOnly,
      });

      let downloaded = false;
      try {
        const res = await fetch(exportUrl);
        if (res.ok) {
          const blob = await res.blob();
          const url = window.URL.createObjectURL(blob);
          const a = document.createElement("a");
          a.href = url;
          a.download = `${fundName ? fundName.replace(/\s+/g, "-") : "accounts"}-statement.csv`;
          document.body.appendChild(a);
          a.click();
          a.remove();
          window.URL.revokeObjectURL(url);
          downloaded = true;
        }
      } catch {
        // Fall back to client-side assembly
      }

      if (!downloaded) {
        let allEntries = [];
        const firstPage = await getAccountsEntries(companyId, user.id, {
          from: range.from,
          to: range.to,
          q: query,
          page: 1,
          limit: 100,
          fund,
          movesOnly,
        });
        if (firstPage?.success && Array.isArray(firstPage.entries)) {
          allEntries = [...firstPage.entries];
          if (firstPage.pages > 1) {
            const rest = await Promise.all(
              Array.from({ length: firstPage.pages - 1 }, (_, i) =>
                getAccountsEntries(companyId, user.id, {
                  from: range.from,
                  to: range.to,
                  q: query,
                  page: i + 2,
                  limit: 100,
                  fund,
                  movesOnly,
                })
              )
            );
            for (const p of rest) {
              if (p?.success && Array.isArray(p.entries)) allEntries.push(...p.entries);
            }
          }
        } else if (data?.entries) {
          allEntries = data.entries;
        }

        const escapeCsv = (v) => {
          const s = v == null ? "" : String(v);
          return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
        };

        const rows = [["Date", "Time", "Details", "Account", "Method", "Reference", "Debit (Out)", "Credit (In)", "Balance", "By"]];
        for (const r of allEntries) {
          const t = when(r.at);
          rows.push([
            t.date,
            t.time,
            r.details || r.label || "",
            r.account || "",
            r.method || "",
            r.reference || "",
            r.amount < 0 ? String(-r.amount) : "",
            r.amount > 0 ? String(r.amount) : (r.transferAmount ? String(r.transferAmount) : ""),
            String(r.balance != null ? r.balance : ""),
            r.by || "",
          ]);
        }
        const csvContent = "\uFEFF" + rows.map((r) => r.map(escapeCsv).join(",")).join("\r\n");
        const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = `${fundName ? fundName.replace(/\s+/g, "-") : "accounts"}-statement.csv`;
        document.body.appendChild(a);
        a.click();
        a.remove();
        window.URL.revokeObjectURL(url);
      }
    } catch (err) {
      console.error("Export error:", err);
      showToast("Could not export CSV", "error");
    } finally {
      setExporting(false);
    }
  }

  return (
    <>
      {!embedded && (
        <div className="page-sticky-header">
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
            <h1 style={{ fontSize: 22, margin: 0 }}>Accounts</h1>
            <button
              type="button"
              className="btn btn-primary"
              onClick={handleExport}
              disabled={exporting}
            >
              {exporting ? "Exporting…" : "Export CSV"}
            </button>
          </div>
          <p style={{ color: "var(--muted)", margin: "0 0 14px" }}>
            Every money in and out of your Cash and bank accounts, with the balance after each one.
          </p>

          {data?.summary && (
            <div className="accounts-summary" style={{ marginBottom: 12 }}>
              {/* nothing to carry in (e.g. All time from the start): no opening balance tile */}
              {Number(data.summary.opening) !== 0 && <div className="stat-card"><small>Opening balance</small><strong>{money(data.summary.opening)}</strong></div>}
              <div className="stat-card"><small>Debit (out)</small><strong className="out">{money(data.summary.moneyOut)}</strong></div>
              <div className="stat-card"><small>Credit (in)</small><strong className="in">{money(data.summary.moneyIn)}</strong></div>
              <div className="stat-card"><small>Closing balance</small><strong>{money(data.summary.closing)}</strong></div>
            </div>
          )}

          {/* search and period under the totals */}
          <div className="card accounts-filters" style={{ marginBottom: 0 }}>
            <input className="field-input" placeholder="Search details, account, person, reference, amount…" value={search} onChange={(e) => setSearch(e.target.value)} />
            <PeriodFilter from={from} to={to} initialMode="month" onChange={(f, t) => { setFrom(f); setTo(t); }} />
          </div>
        </div>
      )}

      {error ? (
        <div className="card" style={{ color: "var(--terracotta)" }}>{error}</div>
      ) : !data ? (
        <div style={{ display: "flex", justifyContent: "center", padding: 50 }}><div className="spinner dark" /></div>
      ) : (
        <>
          {embedded && (
            <>
              <div className="accounts-summary">
                {/* nothing to carry in (e.g. All time from the start): no opening balance tile */}
                {Number(data.summary.opening) !== 0 && <div className="stat-card"><small>Opening balance</small><strong>{money(data.summary.opening)}</strong></div>}
                <div className="stat-card"><small>Debit (out)</small><strong className="out">{money(data.summary.moneyOut)}</strong></div>
                <div className="stat-card"><small>Credit (in)</small><strong className="in">{money(data.summary.moneyIn)}</strong></div>
                <div className="stat-card"><small>Closing balance</small><strong>{money(data.summary.closing)}</strong></div>
              </div>

              {/* search and period under the totals */}
              <div className="card accounts-filters">
                <input className="field-input" placeholder="Search details, account, person, reference, amount…" value={search} onChange={(e) => setSearch(e.target.value)} />
                <PeriodFilter from={from} to={to} initialMode="month" onChange={(f, t) => { setFrom(f); setTo(t); }} />
              </div>
            </>
          )}

          <TableCard
            title={fundName ? `${fundName} statement` : "Statement"}
            meta={tableMeta(data.total, data.page, data.pages, "entries")}
            actions={
              embedded && (
                <button
                  type="button"
                  className="btn btn-outline btn-sm"
                  onClick={handleExport}
                  disabled={exporting}
                >
                  {exporting ? "Exporting…" : "Export CSV"}
                </button>
              )
            }
            page={data.page}
            pages={data.pages}
            onPage={setPage}
            count={data.total}
            pageSize={PAGE_SIZE}
            onPageSize={(n) => { setPageSize(n); setPage(1); }}
            className={`${loading ? "dt-loading" : ""}${embedded ? " dt-left" : ""}`}
          >
            {data.total === 0 ? (
              <div className="dt-empty">{query ? "Nothing matches your search in this period." : movesOnly ? "No money added or moved between accounts in this period." : "No money in or out in this period."}</div>
            ) : (
              <table className="dt">
                <thead>
                  <tr>
                    <th>Time</th>
                    <th>Details</th>
                    <th>Account</th>
                    {/* money added and transfers have no method or reference */}
                    {!movesOnly && <th>Method / Ref</th>}
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
                          <td colSpan={movesOnly ? 6 : 7} className="dt-day">
                            {w.date}
                            <span className="dt-group-total">
                              {dayRows.length} {dayRows.length === 1 ? "entry" : "entries"}
                              {dayOut > 0 ? ` · out ${money(dayOut)}` : ""}
                              {dayIn > 0 ? ` · in ${money(dayIn)}` : ""}
                            </span>
                          </td>
                        </tr>
                      ),
                      <tr key={r._id} className="dt-click" tabIndex={0} title="View details" onClick={() => openRow(r)} onKeyDown={(e) => { if (e.key === "Enter") openRow(r); }}>
                        <td className="nowrap"><span className="dt-time">{w.time}</span></td>
                        <td className="dt-wrap-text">
                          <span className="dt-strong">{r.details || r.label}</span>
                          <span className="dt-sub">{[r.details ? r.label : "", r.category, r.by ? `by ${r.by}` : ""].filter(Boolean).join(" · ")}</span>
                        </td>
                        <td>{r.account || "—"}</td>
                        {!movesOnly && <td>{r.method || "—"}{r.reference && <span className="dt-sub dt-mono">{r.reference}</span>}</td>}
                        {transfer ? (
                          <td className="num muted" colSpan={2} style={{ textAlign: "center" }}>⇄ moved {money(r.transferAmount)}</td>
                        ) : (
                          <>
                            <td className="num out">{r.amount < 0 ? money(-r.amount) : "—"}</td>
                            <td className="num in">{r.amount > 0 ? money(r.amount) : "—"}</td>
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
            {fund
              ? `Balance is what ${fundName || "this account"} holds after each entry. Payments and expenses from it are on the Accounts page.`
              : "Balance is Cash + all bank accounts after each entry. A transfer between your own accounts doesn't change it. Expenses a person paid themselves don't appear here until the company pays them back."}
          </p>
        </>
      )}
      {viewing && (
        <EntryModal
          row={viewing}
          canEdit={canEdit}
          editing={editing}
          setEditing={setEditing}
          saving={saving}
          onSave={saveAmount}
          onOpenLoan={onOpenLoan}
          onDelete={deleteEntry}
          onClose={() => { setViewing(null); setEditing(null); }}
        />
      )}
    </>
  );
}

// One Accounts entry in full; where allowed its amount can be changed here (in place, same date).
function EntryModal({ row, canEdit, editing, setEditing, saving, onSave, onOpenLoan, onDelete, onClose }) {
  const transfer = row.kind === "transfer";
  const amount = transfer ? row.transferAmount : Math.abs(row.amount);
  const w = when(row.at);
  const lines = [
    ["Date", `${w.date} · ${w.time}`],
    ["Type", row.label],
    row.category && ["Category", row.category],
    ["Account", row.account || "—"],
    row.method && ["Method", row.method],
    row.reference && ["Reference", row.reference],
    row.by && ["Recorded by", row.by],
    ["Balance after", money(row.balance)],
  ].filter(Boolean);
  const editable = canEdit && row.editId;
  return (
    <Modal onClose={onClose} maxWidth={460}>
      <h2 style={{ margin: "0 0 4px", fontSize: 20, paddingRight: 40 }}>{row.details || row.label}</h2>
      <div style={{ fontSize: 26, fontWeight: 800, margin: "6px 0 14px", color: transfer ? "var(--muted)" : row.amount > 0 ? "var(--forest)" : "var(--terracotta)" }}>
        {transfer ? `⇄ ${money(amount)}` : money(amount)}
      </div>
      <div className="entry-lines">
        {lines.map(([k, v]) => (
          <div key={k}><span>{k}</span><strong>{v}</strong></div>
        ))}
      </div>

      {editable && editing && (
        <div style={{ marginTop: 16, display: "grid", gap: 10 }}>
          {row.amountEditable && (
            <div>
              <label className="field-label">Amount (₹)</label>
              <input className="field-input" type="number" min="0.01" step="0.01" autoFocus value={editing.amount} onChange={(e) => setEditing({ ...editing, amount: e.target.value })} />
            </div>
          )}
          <div>
            <label className="field-label">Description</label>
            <input className="field-input" value={editing.details} onChange={(e) => setEditing({ ...editing, details: e.target.value })} placeholder={row.label} />
          </div>
          {!String(row.editId).startsWith("income:") && (
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
              <div>
                <label className="field-label">Method</label>
                <select className="field-select" value={editing.method} onChange={(e) => setEditing({ ...editing, method: e.target.value })}>
                  <option value="">—</option>
                  {[...new Set([...PAYMENT_METHODS, editing.method].filter(Boolean))].map((m) => <option key={m} value={m}>{m}</option>)}
                </select>
              </div>
              <div>
                <label className="field-label">Reference</label>
                <input className="field-input" value={editing.reference} onChange={(e) => setEditing({ ...editing, reference: e.target.value })} />
              </div>
            </div>
          )}
          <div>
            <label className="field-label">Date & time</label>
            <input className="field-input" type="datetime-local" value={editing.date} onChange={(e) => setEditing({ ...editing, date: e.target.value })} />
          </div>
          {row.amountEditable ? (
            <p style={{ color: "var(--muted)", fontSize: 12, margin: 0 }}>A new amount is changed in place; the balances after it move by the difference.</p>
          ) : (
            <p style={{ color: "var(--muted)", fontSize: 12, margin: 0 }}>This kind of entry keeps its amount; the other details can be changed.</p>
          )}
          <div style={{ display: "flex", gap: 10, marginTop: 4 }}>
            <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setEditing(null)} disabled={saving}>Cancel</button>
            <button type="button" className="btn btn-primary" style={{ flex: 1 }} onClick={onSave} disabled={saving}>{saving ? "Saving…" : "Save"}</button>
          </div>
        </div>
      )}

      {!editing && (
        <div style={{ display: "flex", gap: 10, marginTop: 18 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Close</button>
          {editable && String(row.editId).startsWith("income:") && <button type="button" className="btn btn-outline-danger" style={{ flex: 1 }} disabled={saving} onClick={() => onDelete(row)}>Delete</button>}
          {row.loanId && onOpenLoan && <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => { if (onOpenLoan(row.loanId)) onClose(); }}>View loan</button>}
          {editable && (
            <button
              type="button"
              className="btn btn-primary"
              style={{ flex: 1 }}
              onClick={() => setEditing({ id: row.editId, amount: String(amount), details: row.details || "", method: row.method || "", reference: row.reference || "", date: istInput(row.at) })}
            >
              Edit
            </button>
          )}
        </div>
      )}
    </Modal>
  );
}

// a date as "YYYY-MM-DDTHH:mm" in India time, for the date & time input
function istInput(at) {
  const d = new Date(new Date(at).getTime() + 330 * 60000);
  return d.toISOString().slice(0, 16);
}
