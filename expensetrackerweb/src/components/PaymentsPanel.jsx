import { useCallback, useEffect, useMemo, useState } from "react";
import { editAccountsEntry, getLedgerBalances, getLedgerTransactions, getPayableBills, reimburseAdmin } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { formatDate, money, PAYMENT_METHODS, roleNames, methodForFund } from "../utils.js";
import Modal from "./Modal.jsx";
import PayableBillsPreview from "./PayableBillsPreview.jsx";
import PeriodFilter from "./PeriodFilter.jsx";
import { TableCard, pageOf, tableMeta, usePageSize } from "./DataTable.jsx";
import { useFundTopUp } from "./FundTopUp.jsx";
import OwnOutstanding from "./OwnOutstanding.jsx";

const round = (n) => Math.round(n * 100) / 100;
const initial = (name) => String(name || "?").trim().charAt(0).toUpperCase();

// Managers: pay off everything the company owes any staff member or manager, by company funds or out of
// their own pocket ("by self": the company then owes the paying manager instead). One person or many at once.
export default function PaymentsPanel({ companyId, company, user, members, funds, onChanged, refreshKey, focusOwn = false, homeKey, canEditPayments = false }) {
  const { showToast } = useToast();
  const [balances, setBalances] = useState(null);
  const [txs, setTxs] = useState([]);
  const [search, setSearch] = useState("");
  // people filter: all | me | managers | staff — "me" shows my own outstanding (pay it here) instead of the list;
  // opened from the Home "My outstanding" tile it starts on "me"
  // starts on my own bills; the filter shows everyone else's
  const [role, setRole] = useState("me");
  // the Admin editing a payment from the history: { row, amount, fundId, method, reference, date, note }
  const [editingPayment, setEditingPayment] = useState(null);
  const [savingPayment, setSavingPayment] = useState(false);
  // opened again from the menu: back to my own bills
  const [seenHome, setSeenHome] = useState(homeKey);
  if (homeKey !== seenHome) {
    setSeenHome(homeKey);
    setRole("me");
  }
  useEffect(() => {
    if (focusOwn) setRole("me");
  }, [focusOwn]);
  const [show, setShow] = useState("owed");
  const [sort, setSort] = useState("owed");
  const [selected, setSelected] = useState(() => new Set());
  const [paying, setPaying] = useState(null); // people being paid
  const [viewing, setViewing] = useState(null); // person whose bills are open
  const [historyPerson, setHistoryPerson] = useState("all");
  const [historySearch, setHistorySearch] = useState("");
  const [historyPage, setHistoryPage] = useState(1);
  const [peoplePage, setPeoplePage] = useState(1);
  const [pageSize, setPageSize] = usePageSize();
  const changePageSize = (n) => { setPageSize(n); setHistoryPage(1); setPeoplePage(1); };
  const [historyFrom, setHistoryFrom] = useState("");
  const [historyTo, setHistoryTo] = useState("");

  const load = useCallback(async () => {
    const [b, t] = await Promise.all([getLedgerBalances(companyId, user.id), getLedgerTransactions(companyId, user.id)]);
    if (b.success) setBalances(b);
    else showToast(b.message || "Could not load balances", "error");
    if (t.success) setTxs(t.transactions || []);
  }, [companyId, user.id, showToast]);

  async function savePaymentEdit() {
    const e = editingPayment;
    const value = Number(e.amount);
    if (!(value > 0)) return showToast("Enter an amount greater than zero", "error");
    const changes = { amount: value, method: e.method, reference: e.reference.trim(), details: e.note.trim() };
    if (e.date) changes.date = e.date;
    if (e.row.company && e.fundId && e.fundChanged) changes.fundId = e.fundId;
    setSavingPayment(true);
    const res = await editAccountsEntry(companyId, user.id, String(e.row.id), changes);
    setSavingPayment(false);
    if (!res.success) return showToast(res.message || "Could not save the payment", "error");
    showToast("Payment updated");
    setEditingPayment(null);
    load();
    onChanged?.();
  }

  useEffect(() => {
    load();
  }, [load, refreshKey]);

  // everyone in the company (plus anyone still owed who has left), with what they're owed
  const people = useMemo(() => {
    const owedRows = new Map((balances?.admins || []).map((a) => [String(a.userId), a]));
    const list = members.map((m) => {
      const id = String(m.userId);
      const row = owedRows.get(id);
      owedRows.delete(id);
      return {
        userId: id,
        name: m.name,
        email: m.email,
        role: m.role === "admin" ? "manager" : "staff",
        group: String(company.createdBy?._id || company.createdBy) === id || m.isAdmin ? "admin" : m.customRoleId ? `role:${m.customRoleId}` : m.role === "admin" ? "manager" : "staff",
        groupLabel: String(company.createdBy?._id || company.createdBy) === id || m.isAdmin ? roleNames(company).admin : m.customRoleId ? m.customRoleName || "Custom role" : m.role === "admin" ? roleNames(company).manager : roleNames(company).staff,
        owed: Number(row?.owed || 0),
        claims: Number(row?.claims || 0),
        advance: Math.max(0, Number(row?.advance || 0)),
      };
    });
    for (const [id, row] of owedRows) {
      list.push({ userId: id, name: row.name || "Former member", email: "", role: "former", group: "former", groupLabel: "Former", owed: Number(row.owed || 0), claims: Number(row.claims || 0), advance: Math.max(0, Number(row.advance || 0)) });
    }
    return list;
  }, [balances, members, company]);

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase();
    return people
      .filter((p) => (role === "all" ? true : role.startsWith("person:") ? p.userId === role.slice(7) : p.group === role))
      .filter((p) => (show === "owed" ? p.owed > 0 : true))
      .filter((p) => !q || `${p.name} ${p.email}`.toLowerCase().includes(q))
      .sort((a, b) => (sort === "name" ? a.name.localeCompare(b.name) : sort === "claims" ? b.claims - a.claims : b.owed - a.owed));
  }, [people, role, show, search, sort]);

  const payable = (p) => p.owed > 0 && p.userId !== String(user.id);
  const selectedPeople = people.filter((p) => selected.has(p.userId) && payable(p));
  const selectedTotal = round(selectedPeople.reduce((s, p) => s + p.owed, 0));
  const allVisibleSelected = visible.filter(payable).length > 0 && visible.filter(payable).every((p) => selected.has(p.userId));

  const toggle = (id) =>
    setSelected((cur) => {
      const next = new Set(cur);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  const toggleAll = () =>
    setSelected((cur) => {
      const next = new Set(cur);
      const ids = visible.filter(payable).map((p) => p.userId);
      if (allVisibleSelected) ids.forEach((id) => next.delete(id));
      else ids.forEach((id) => next.add(id));
      return next;
    });

  const totals = {
    all: round(people.reduce((s, p) => s + Math.max(0, p.owed), 0)),
    waiting: people.filter((p) => p.owed > 0).length,
  };
  const groups = [
    { key: "admin", label: roleNames(company).admins },
    { key: "manager", label: roleNames(company).managers },
    { key: "staff", label: roleNames(company).staffs },
    ...(company.customRoles || []).map((r) => ({ key: `role:${r._id}`, label: r.name })),
    { key: "former", label: "Former members" },
  ]
    .map((g) => {
      const inGroup = people.filter((p) => p.group === g.key);
      return { ...g, owed: round(inGroup.reduce((sum, p) => sum + Math.max(0, p.owed), 0)), waiting: inGroup.filter((p) => p.owed > 0).length, count: inGroup.length };
    })
    // former members only when something is still owed to them
    .filter((g) => g.key !== "former" || g.owed > 0);

  // payments made: company reimbursements, payments by a manager personally, and voucher set-offs
  const history = useMemo(() => {
    const rows = txs
      .filter((t) => (t.type === "reimburse" || t.type === "advance_offset") && !t.reversedBy)
      .map((t) => {
        const debit = (t.entries || []).find((e) => Number(e.debit) > 0 && /^Payable to /.test(e.accountId?.name || ""));
        const credit = (t.entries || []).find((e) => Number(e.credit) > 0);
        const personName = debit?.accountId?.name?.replace(/^Payable to /, "") || "Someone";
        const bySelf = /personally$/.test(t.memo || "");
        const how = t.type === "advance_offset" ? "Set off from voucher balance" : bySelf ? t.memo : `Company · ${credit?.accountId?.name || "fund"}`;
        return { id: t._id, note: t.note || "", company: !bySelf && t.type === "reimburse", fundName: credit?.accountId?.name || "", date: t.date || t.createdAt, personName, amount: Number(debit?.debit || 0), // who paid: the company (its name), or the manager who paid out of their own pocket
        by: bySelf ? (t.memo.match(/^Paid by (.+) personally$/)?.[1] || t.createdBy?.name || "Manager") : company?.name || "Company", how, method: t.method, reference: t.reference };
      })
      .sort((a, b) => new Date(b.date) - new Date(a.date)); // by payment date, which can be backdated
    const q = historySearch.trim().toLowerCase();
    return rows.filter((r) => {
      const day = String(r.date || "").slice(0, 10);
      if (historyPerson !== "all" && r.personName !== historyPerson) return false;
      if (historyFrom && day < historyFrom) return false;
      if (historyTo && day > historyTo) return false;
      if (q && !`${r.personName} ${r.how} ${r.by} ${r.reference || ""}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [txs, historyPerson, historySearch, historyFrom, historyTo, company?.name]);
  const historyNames = [...new Set(txs.filter((t) => t.type === "reimburse" || t.type === "advance_offset").map((t) => (t.entries || []).find((e) => Number(e.debit) > 0 && /^Payable to /.test(e.accountId?.name || ""))?.accountId?.name?.replace(/^Payable to /, "")).filter(Boolean))];

  const done = () => {
    setSelected(new Set());
    load();
    onChanged?.();
  };

  return (
    <>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
        <h1 style={{ fontSize: 22, margin: 0 }}>Payments</h1>
        <button className="btn btn-outline" onClick={load}>Refresh</button>
      </div>
      <p style={{ color: "var(--muted)", margin: "0 0 18px" }}>Pay off what the company owes each person, from company funds or out of your own pocket.</p>


      {!balances ? (
        <div style={{ display: "flex", justifyContent: "center", padding: 40 }}><div className="spinner dark" /></div>
      ) : (
        <>
          <div className="pay-tiles" style={{ marginBottom: 18 }}>
            {[
              { label: "Total owed", value: money(totals.all), sub: `${totals.waiting} ${totals.waiting === 1 ? "person" : "people"} waiting`, tone: totals.all > 0 ? "red" : "forest", onClick: () => setRole("all") },
              ...groups.map((g) => ({
                label: `Owed to ${g.label.toLowerCase()}`,
                value: money(g.owed),
                sub: g.waiting ? `${g.waiting} ${g.waiting === 1 ? "person" : "people"} waiting` : g.count ? "Nothing owed" : "No one in this role",
                tone: g.owed > 0 ? (g.key === "admin" ? "blue" : "red") : "forest",
                onClick: () => setRole(g.key),
              })),
              { label: "Company funds", value: money(funds.reduce((s, f) => s + Number(f.balance || 0), 0)), sub: funds.map((f) => `${f.name} ${money(f.balance)}`).slice(0, 2).join(" · "), tone: "forest" },
            ].map((t) => (
              <div
                key={t.label}
                className={`pay-tile tone-${t.tone}${t.onClick ? " clickable" : ""}`}
                onClick={t.onClick}
                role={t.onClick ? "button" : undefined}
                tabIndex={t.onClick ? 0 : undefined}
                title={t.onClick ? "Show only these people" : undefined}
              >
                <div className="pay-tile-label">{t.label}</div>
                <div className="pay-tile-value">{t.value}</div>
                <div className="pay-tile-sub">{t.sub}</div>
              </div>
            ))}
          </div>

          <div className="card payments-toolbar">
            <input className="field-input" placeholder="Search by name or email…" value={search} onChange={(e) => setSearch(e.target.value)} />
            <select className="field-select" value={role} onChange={(e) => setRole(e.target.value)} title="Role">
              <option value="all">Everyone</option>
              <option value="me">{user.name} (You)</option>
              <optgroup label="Roles">
                {groups.filter((g) => g.key !== "former").map((g) => <option key={g.key} value={g.key}>{g.label}</option>)}
              </optgroup>
              {/* then every person, by name, with their role */}
              <optgroup label="People">
                {[...people].filter((p) => p.userId !== String(user.id)).sort((a, b) => a.name.localeCompare(b.name)).map((p) => (
                  <option key={p.userId} value={`person:${p.userId}`}>{p.name} ({p.groupLabel})</option>
                ))}
              </optgroup>
            </select>
            <select className="field-select" value={show} onChange={(e) => setShow(e.target.value)} title="Show">
              <option value="owed">Owed money only</option>
              <option value="all">Include settled</option>
            </select>
            <select className="field-select" value={sort} onChange={(e) => setSort(e.target.value)} title="Sort">
              <option value="owed">Highest owed first</option>
              <option value="claims">Most unpaid claims</option>
              <option value="name">Name A–Z</option>
            </select>
          </div>

          {role === "me" ? (
            <OwnOutstanding companyId={companyId} company={company} user={user} funds={funds} focus={focusOwn} alwaysShow refreshKey={refreshKey} onPaid={() => { load(); onChanged?.(); }} />
          ) : (
          <>
          {selectedPeople.length > 0 && (
            <div className="payments-selection">
              <span><strong>{selectedPeople.length}</strong> selected · <strong>{money(selectedTotal)}</strong></span>
              <span style={{ display: "flex", gap: 8 }}>
                <button className="btn btn-outline btn-sm" onClick={() => setSelected(new Set())}>Clear</button>
                <button className="btn btn-primary btn-sm" onClick={() => setPaying(selectedPeople)}>Pay selected</button>
              </span>
            </div>
          )}

          <TableCard
            title="People owed"
            meta={tableMeta(visible.length, pageOf(visible, peoplePage, pageSize).page, pageOf(visible, peoplePage, pageSize).pages, "people")}
            page={pageOf(visible, peoplePage, pageSize).page}
            pages={pageOf(visible, peoplePage, pageSize).pages}
            onPage={setPeoplePage}
            count={visible.length}
            pageSize={pageSize}
            onPageSize={changePageSize}
          >
            {visible.length === 0 ? (
              <div className="dt-empty">{show === "owed" ? "Nobody is owed money right now." : "No one matches your search."}</div>
            ) : (
              <table className="dt">
                <thead>
                  <tr>
                    <th style={{ width: 36 }}><input type="checkbox" checked={allVisibleSelected} onChange={toggleAll} aria-label="Select all" /></th>
                    <th>Person</th>
                    <th>Role</th>
                    <th>Details</th>
                    <th className="num">Owed</th>
                    <th className="num">Action</th>
                  </tr>
                </thead>
                <tbody>
                  {pageOf(visible, peoplePage, pageSize).rows.map((p) => {
                    const me = p.userId === String(user.id);
                    return (
                      <tr key={p.userId} className={selected.has(p.userId) ? "dt-selected" : ""}>
                        <td><input type="checkbox" checked={selected.has(p.userId)} disabled={!payable(p)} onChange={() => toggle(p.userId)} aria-label={`Select ${p.name}`} /></td>
                        <td className="dt-strong">
                          <span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
                            <span className="payments-avatar">{initial(p.name)}</span>
                            {p.name}{me ? " (you)" : ""}
                          </span>
                        </td>
                        <td><span className={`payments-role ${p.group.startsWith("role:") ? "custom" : p.group}`}>{p.groupLabel}</span></td>
                        <td className="muted">
                          {p.claims > 0 ? `${money(p.claims)} in approved claims` : p.owed > 0 ? "Paid out of pocket" : "Nothing owed"}
                          {p.advance > 0 && <span className="dt-sub">holds {money(p.advance)} voucher money</span>}
                        </td>
                        <td className={`num ${p.owed > 0 ? "out" : "muted"}`}>{money(p.owed)}</td>
                        <td>
                          <span className="dt-actions">
                            {p.owed > 0 && <button className="btn btn-outline btn-sm" onClick={() => setViewing(p)}>View bills</button>}
                            {payable(p) && <button className="btn btn-primary btn-sm" onClick={() => setPaying([p])}>Pay</button>}
                            {me && p.owed > 0 && <span className="dt-sub">Pick "{user.name} (You)" above to pay it</span>}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </TableCard>
          </>
          )}

          <h2 style={{ fontSize: 20, margin: "28px 0 12px" }}>Payment history</h2>
          <div className="card payments-toolbar payments-history-toolbar">
            <input className="field-input" placeholder="Search payments…" value={historySearch} onChange={(e) => setHistorySearch(e.target.value)} />
            <select className="field-select" value={historyPerson} onChange={(e) => setHistoryPerson(e.target.value)}>
              <option value="all">Everyone</option>
              {historyNames.map((n) => <option key={n} value={n}>{n === user.name ? `${n} (You)` : n}</option>)}
            </select>
            <PeriodFilter
              from={historyFrom}
              to={historyTo}
              years={[...new Set(txs.map((t) => String(t.createdAt || "").slice(0, 4)).filter(Boolean))]}
              onChange={(from, to) => { setHistoryFrom(from); setHistoryTo(to); }}
            />
          </div>
          {(() => {
            const paged = pageOf(history, historyPage, pageSize);
            return (
              <TableCard title="Payments" meta={tableMeta(history.length, paged.page, paged.pages, "payments")} page={paged.page} pages={paged.pages} onPage={setHistoryPage} count={history.length} pageSize={pageSize} onPageSize={changePageSize}>
                {history.length === 0 ? (
                  <div className="dt-empty">No payments match.</div>
                ) : (
                  <table className="dt">
                    <thead>
                      <tr><th>Date</th><th>Paid to</th><th>How</th><th>Method</th><th>Reference</th><th>Paid by</th><th className="num">Amount</th>{canEditPayments && <th className="num">Action</th>}</tr>
                    </thead>
                    <tbody>
                      {paged.rows.map((h) => (
                        <tr key={h.id}>
                          <td className="nowrap">{formatDate(h.date)}</td>
                          <td className="dt-strong">{h.personName}</td>
                          <td>{h.how}</td>
                          <td>{h.method || "—"}</td>
                          <td className="dt-mono">{h.reference || "—"}</td>
                          <td>{h.by}</td>
                          <td className="num in">{money(h.amount)}</td>
                          {canEditPayments && (
                            <td>
                              <span className="dt-actions">
                                <button
                                  type="button"
                                  className="btn btn-outline btn-sm"
                                  onClick={() => {
                                    // start on the account it was paid from (matched by name), so nothing moves unless changed
                                    const current = funds.find((f) => h.fundName && (f.name === h.fundName || h.fundName.startsWith(f.name) || f.name.startsWith(h.fundName)));
                                    setEditingPayment({ row: h, amount: String(h.amount), fundId: current?.fundId || "", method: h.method || "", reference: h.reference || "", date: istInput(h.date), note: h.note });
                                  }}
                                >
                                  Edit
                                </button>
                              </span>
                            </td>
                          )}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </TableCard>
            );
          })()}
        </>
      )}

      {editingPayment && (
        <Modal onClose={() => setEditingPayment(null)} maxWidth={460}>
          <h2 style={{ margin: "0 0 4px", fontSize: 20 }}>Edit payment</h2>
          <p style={{ color: "var(--muted)", fontSize: 13, margin: "0 0 14px" }}>To {editingPayment.row.personName} · {editingPayment.row.how}</p>
          <div style={{ display: "grid", gap: 10 }}>
            <div>
              <label className="field-label">Amount (₹)</label>
              <input className="field-input" type="number" min="0.01" step="0.01" autoFocus value={editingPayment.amount} onChange={(ev) => setEditingPayment({ ...editingPayment, amount: ev.target.value })} />
            </div>
            {editingPayment.row.company && (
              <div>
                <label className="field-label">Paid from</label>
                <select className="field-select" value={editingPayment.fundId} onChange={(ev) => setEditingPayment({ ...editingPayment, fundId: ev.target.value, fundChanged: true })}>
                  {!editingPayment.fundId && <option value="">{editingPayment.row.fundName || "Current account"}</option>}
                  {funds.map((f) => <option key={f.fundId} value={f.fundId}>{f.name} · {money(f.balance)}</option>)}
                </select>
              </div>
            )}
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
              <div>
                <label className="field-label">Method</label>
                <select className="field-select" value={editingPayment.method} onChange={(ev) => setEditingPayment({ ...editingPayment, method: ev.target.value })}>
                  <option value="">—</option>
                  {[...new Set([...PAYMENT_METHODS, editingPayment.method].filter(Boolean))].map((m) => <option key={m} value={m}>{m}</option>)}
                </select>
              </div>
              <div>
                <label className="field-label">Reference</label>
                <input className="field-input" value={editingPayment.reference} onChange={(ev) => setEditingPayment({ ...editingPayment, reference: ev.target.value })} />
              </div>
            </div>
            <div>
              <label className="field-label">Date & time</label>
              <input className="field-input" type="datetime-local" value={editingPayment.date} onChange={(ev) => setEditingPayment({ ...editingPayment, date: ev.target.value })} />
            </div>
            <div>
              <label className="field-label">Description (optional)</label>
              <input className="field-input" value={editingPayment.note} onChange={(ev) => setEditingPayment({ ...editingPayment, note: ev.target.value })} />
            </div>
            <p style={{ color: "var(--muted)", fontSize: 12, margin: 0 }}>A new amount or account moves the balances by the difference; what {editingPayment.row.personName} is owed follows.</p>
            <div style={{ display: "flex", gap: 10, marginTop: 4 }}>
              <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setEditingPayment(null)} disabled={savingPayment}>Cancel</button>
              <button type="button" className="btn btn-primary" style={{ flex: 1 }} onClick={savePaymentEdit} disabled={savingPayment}>{savingPayment ? "Saving…" : "Save"}</button>
            </div>
          </div>
        </Modal>
      )}

      {viewing && (
        <BillsModal companyId={companyId} user={user} person={viewing} onClose={() => setViewing(null)} onPay={() => { setPaying([viewing]); setViewing(null); }} />
      )}
      {paying && (
        <PayModal
          companyId={companyId}
          company={company}
          user={user}
          people={paying}
          funds={funds}
          onClose={() => setPaying(null)}
          onDone={() => { setPaying(null); done(); }}
          showToast={showToast}
        />
      )}
    </>
  );
}

// One person's open bills, oldest first; all of them close when the full balance is paid.
function BillsModal({ companyId, user, person, onClose, onPay }) {
  const [state, setState] = useState({ loading: true, bills: [], owed: person.owed });
  useEffect(() => {
    let active = true;
    getPayableBills(companyId, person.userId, user.id).then((res) => {
      if (active) setState({ loading: false, bills: res.success ? res.bills || [] : [], owed: Number(res.owed ?? person.owed) });
    });
    return () => { active = false; };
  }, [companyId, person, user.id]);
  const me = person.userId === String(user.id);
  return (
    <Modal onClose={onClose} maxWidth={520}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>{person.name}</h2>
      <p style={{ margin: "0 0 4px", color: "var(--muted)", fontSize: 13 }}>Company owes <strong style={{ color: "var(--terracotta)" }}>{money(state.owed)}</strong></p>
      <PayableBillsPreview bills={state.bills} loading={state.loading} amount={state.owed} />
      <div style={{ display: "flex", gap: 10, marginTop: 18 }}>
        <button className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Close</button>
        {!me && state.owed > 0 && <button className="btn btn-primary" style={{ flex: 1 }} onClick={onPay}>Pay…</button>}
      </div>
    </Modal>
  );
}

// Pays the full balance of each person: from a company fund, or by the manager personally.
function PayModal({ companyId, company, user, people, funds, onClose, onDone, showToast }) {
  const [paidBy, setPaidBy] = useState("company");
  const [fundId, setFundId] = useState(funds[0]?.fundId || "cash");
  // the method follows the account paid from (Cash -> "Cash", a bank -> "Bank") until it is picked by hand
  const [method, setMethod] = useState(() => methodForFund(funds[0]?.fundId || "cash"));
  const [methodPicked, setMethodPicked] = useState(false);
  const [reference, setReference] = useState("");
  const [offset, setOffset] = useState(false);
  const [saving, setSaving] = useState(false);
  const anyHeld = people.some((p) => p.advance > 0);
  // the most cash that can go to a person: full balance, less voucher money they hold when netting
  const maxFor = (p) => round(Math.max(0, p.owed - (offset ? Math.min(p.advance, p.owed) : 0)));
  // amount typed per person; starts at the full balance and can be lowered to pay part of it
  const [amounts, setAmounts] = useState(() => Object.fromEntries(people.map((p) => [p.userId, String(p.owed)])));
  const cashFor = (p) => round(Math.max(0, Number(amounts[p.userId]) || 0));
  const total = round(people.reduce((s, p) => s + cashFor(p), 0));
  const fullTotal = round(people.reduce((s, p) => s + maxFor(p), 0));
  const fund = funds.find((f) => String(f.fundId) === String(fundId));
  const short = paidBy === "company" && fund && Number(fund.balance || 0) < total;
  const tooMuch = people.find((p) => cashFor(p) > maxFor(p) + 0.001);
  const nothing = people.every((p) => !(cashFor(p) > 0) && !(offset && p.advance > 0));
  const topUp = useFundTopUp({ companyId, user, funds });

  function toggleOffset(on) {
    setOffset(on);
    // refill each amount with the new full figure; it can still be lowered afterwards
    setAmounts(Object.fromEntries(people.map((p) => [p.userId, String(round(Math.max(0, p.owed - (on ? Math.min(p.advance, p.owed) : 0))))])));
  }

  // what this payment clears for a person: the cash typed, plus (when netting) held voucher money up to the rest
  const settledFor = (p) => round(cashFor(p) + (offset ? Math.min(p.advance, Math.max(0, p.owed - cashFor(p))) : 0));

  // one person: show which of their bills this amount closes
  const single = people.length === 1 ? people[0] : null;
  const [bills, setBills] = useState({ loading: Boolean(single), list: [] });
  useEffect(() => {
    if (!single) return undefined;
    let active = true;
    getPayableBills(companyId, single.userId, user.id).then((res) => {
      if (active) setBills({ loading: false, list: res.success ? res.bills || [] : [] });
    });
    return () => { active = false; };
  }, [companyId, single, user.id]);

  function submit() {
    if (tooMuch) return showToast(`${tooMuch.name} is owed only ${money(maxFor(tooMuch))}`, "error");
    if (short) return topUp.ask(fund, total, pay);
    pay();
  }

  async function pay() {
    setSaving(true);
    const failed = [];
    let paid = 0;
    for (const p of people) {
      if (!(cashFor(p) > 0) && !(offset && p.advance > 0)) continue; // left at ₹0: skip this person
      const res = await reimburseAdmin({
        companyId,
        userId: user.id,
        adminUserId: p.userId,
        amount: cashFor(p),
        fundId: paidBy === "company" ? fundId : undefined,
        paidBy,
        method,
        reference: reference.trim(),
        offsetAdvance: offset && p.advance > 0,
      });
      if (res.success) paid += 1;
      else failed.push(`${p.name}: ${res.message || "failed"}`);
    }
    setSaving(false);
    if (paid) showToast(`${paid} ${paid === 1 ? "person" : "people"} paid${paidBy === "self" ? " by you · the company now owes you " + money(total) : ""}`);
    if (failed.length) showToast(`Not paid — ${failed.join("; ")}`, "error");
    if (paid) onDone();
  }

  return (
    <Modal onClose={onClose} maxWidth={500}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>{people.length === 1 ? `Pay ${people[0].name}` : `Pay ${people.length} people`}</h2>
      <p style={{ margin: "0 0 12px", color: "var(--muted)", fontSize: 13 }}>
        The full balance is filled in. Lower any amount to pay part of it — the oldest bills close first and the rest stays owed.
      </p>

      <div className="payments-paylist">
        {people.map((p) => {
          const settled = settledFor(p);
          const left = round(p.owed - settled);
          const over = cashFor(p) > maxFor(p) + 0.001;
          return (
            <div key={p.userId} className="payments-payrow">
              <span className="payments-payrow-name">
                {p.name}
                <small>
                  {over
                    ? <span style={{ color: "var(--terracotta)" }}>Owed only {money(maxFor(p))}</span>
                    : left > 0
                      ? `Part payment · ${money(left)} stays owed`
                      : `Clears all ${money(p.owed)}`}
                  {offset && p.advance > 0 ? ` · ${money(Math.min(p.advance, Math.max(0, p.owed - cashFor(p))))} from voucher balance` : ""}
                </small>
              </span>
              <span className="payments-payrow-input">
                <span>₹</span>
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  max={maxFor(p)}
                  value={amounts[p.userId]}
                  onChange={(e) => setAmounts((cur) => ({ ...cur, [p.userId]: e.target.value }))}
                  aria-label={`Amount for ${p.name}`}
                />
              </span>
              {Number(amounts[p.userId]) !== maxFor(p) && (
                <button type="button" className="payments-full" onClick={() => setAmounts((cur) => ({ ...cur, [p.userId]: String(maxFor(p)) }))}>Full</button>
              )}
            </div>
          );
        })}
        <div className="payments-paylist-total">
          <span>Total{total !== fullTotal ? <small style={{ color: "var(--muted)", fontWeight: 500 }}> · full balance {money(fullTotal)}</small> : null}</span>
          <strong>{money(total)}</strong>
        </div>
      </div>
      {single && <PayableBillsPreview bills={bills.list} loading={bills.loading} amount={settledFor(single)} />}

      <label className="field-label" style={{ display: "block", marginTop: 14 }}>Paid by</label>
      <div className="payments-choice">
        <button type="button" className={paidBy === "company" ? "on" : ""} onClick={() => setPaidBy("company")}>
          <strong>{company?.name || "Company"}</strong>
          <span>From Cash or Bank</span>
        </button>
        <button type="button" className={paidBy === "self" ? "on" : ""} onClick={() => setPaidBy("self")}>
          <strong>Me (self)</strong>
          <span>The company will owe you {money(total)}</span>
        </button>
      </div>

      {paidBy === "company" && (
        <>
          <label className="field-label" style={{ display: "block", marginTop: 12 }}>Paid from</label>
          <select className="field-select" value={fundId} onChange={(e) => { setFundId(e.target.value); if (!methodPicked) setMethod(methodForFund(e.target.value)); }}>
            {funds.map((f) => <option key={f.fundId} value={f.fundId}>{f.name} · {money(f.balance)}</option>)}
          </select>
          {short && <div style={{ marginTop: 6, fontSize: 12, color: "var(--terracotta)", fontWeight: 600 }}>Only {money(fund.balance)} available in {fund.name}. You can add money when you pay.</div>}
        </>
      )}

      <label className="field-label" style={{ display: "block", marginTop: 12 }}>Payment method</label>
      <select className="field-select" value={method} onChange={(e) => { setMethod(e.target.value); setMethodPicked(true); }}>
        {PAYMENT_METHODS.map((m) => <option key={m} value={m}>{m}</option>)}
      </select>
      <label className="field-label" style={{ display: "block", marginTop: 12 }}>Reference (optional)</label>
      <input className="field-input" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="UTR / cheque no." />

      {anyHeld && (
        <label style={{ display: "flex", gap: 8, alignItems: "flex-start", marginTop: 12, fontSize: 13, cursor: "pointer" }}>
          <input type="checkbox" checked={offset} onChange={(e) => toggleOffset(e.target.checked)} style={{ marginTop: 2 }} />
          <span>Set off voucher money they hold<span style={{ display: "block", color: "var(--muted)", fontSize: 12 }}>Their held voucher balance counts towards what they're owed, so less is paid now.</span></span>
        </label>
      )}

      <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
        <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
        <button type="button" className="btn btn-primary" style={{ flex: 1 }} disabled={saving || Boolean(tooMuch) || nothing} onClick={submit}>
          {saving ? "Paying…" : `Pay ${money(total)}`}
        </button>
      </div>
      {topUp.ui}
    </Modal>
  );
}

// a date as "YYYY-MM-DDTHH:mm" in India time, for the date & time input
function istInput(at) {
  return new Date(new Date(at).getTime() + 330 * 60000).toISOString().slice(0, 16);
}
