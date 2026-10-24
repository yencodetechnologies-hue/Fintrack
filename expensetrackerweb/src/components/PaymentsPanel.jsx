import { useCallback, useEffect, useMemo, useState } from "react";
import { getLedgerBalances, getLedgerTransactions, getPayableBills, reimburseAdmin } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { formatDate, money, PAYMENT_METHODS, roleNames } from "../utils.js";
import Modal from "./Modal.jsx";
import PayableBillsPreview from "./PayableBillsPreview.jsx";
import PeriodFilter from "./PeriodFilter.jsx";
import { useFundTopUp } from "./FundTopUp.jsx";
import OwnOutstanding from "./OwnOutstanding.jsx";

const round = (n) => Math.round(n * 100) / 100;
const initial = (name) => String(name || "?").trim().charAt(0).toUpperCase();

// Managers: pay off everything the company owes any staff member or manager, by company funds or out of
// their own pocket ("by self": the company then owes the paying manager instead). One person or many at once.
export default function PaymentsPanel({ companyId, company, user, members, funds, onChanged, refreshKey, focusOwn = false }) {
  const { showToast } = useToast();
  const [balances, setBalances] = useState(null);
  const [txs, setTxs] = useState([]);
  const [search, setSearch] = useState("");
  // people filter: all | me | managers | staff — "me" shows my own outstanding (pay it here) instead of the list;
  // opened from the Home "My outstanding" tile it starts on "me"
  const [role, setRole] = useState(focusOwn ? "me" : "all");
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
  const [historyFrom, setHistoryFrom] = useState("");
  const [historyTo, setHistoryTo] = useState("");

  const load = useCallback(async () => {
    const [b, t] = await Promise.all([getLedgerBalances(companyId, user.id), getLedgerTransactions(companyId, user.id)]);
    if (b.success) setBalances(b);
    else showToast(b.message || "Could not load balances", "error");
    if (t.success) setTxs(t.transactions || []);
  }, [companyId, user.id, showToast]);

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
        owed: Number(row?.owed || 0),
        claims: Number(row?.claims || 0),
        advance: Math.max(0, Number(row?.advance || 0)),
      };
    });
    for (const [id, row] of owedRows) {
      list.push({ userId: id, name: row.name || "Former member", email: "", role: "former", owed: Number(row.owed || 0), claims: Number(row.claims || 0), advance: Math.max(0, Number(row.advance || 0)) });
    }
    return list;
  }, [balances, members]);

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase();
    return people
      .filter((p) => (role === "all" ? true : role === "managers" ? p.role === "manager" : p.role !== "manager"))
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
    managers: round(people.filter((p) => p.role === "manager").reduce((s, p) => s + Math.max(0, p.owed), 0)),
    staff: round(people.filter((p) => p.role !== "manager").reduce((s, p) => s + Math.max(0, p.owed), 0)),
    waiting: people.filter((p) => p.owed > 0).length,
  };

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
        return { id: t._id, date: t.date || t.createdAt, personName, amount: Number(debit?.debit || 0), by: t.createdBy?.name || "Manager", how, method: t.method, reference: t.reference };
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
  }, [txs, historyPerson, historySearch, historyFrom, historyTo]);
  const historyNames = [...new Set(txs.filter((t) => t.type === "reimburse" || t.type === "advance_offset").map((t) => (t.entries || []).find((e) => Number(e.debit) > 0 && /^Payable to /.test(e.accountId?.name || ""))?.accountId?.name?.replace(/^Payable to /, "")).filter(Boolean))];

  const done = () => {
    setSelected(new Set());
    load();
    onChanged?.();
  };

  return (
    <>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
        <h1 style={{ fontSize: 26, margin: 0 }}>Payments</h1>
        <button className="btn btn-outline" onClick={load}>Refresh</button>
      </div>
      <p style={{ color: "var(--muted)", margin: "0 0 18px" }}>Pay off what the company owes each staff member or manager, from company funds or out of your own pocket.</p>


      {!balances ? (
        <div style={{ display: "flex", justifyContent: "center", padding: 40 }}><div className="spinner dark" /></div>
      ) : (
        <>
          <div className="pay-tiles" style={{ marginBottom: 18 }}>
            {[
              { label: "Total owed", value: money(totals.all), sub: `${totals.waiting} ${totals.waiting === 1 ? "person" : "people"} waiting`, tone: totals.all > 0 ? "red" : "forest" },
              { label: `Owed to ${roleNames(company).managers.toLowerCase()}`, value: money(totals.managers), sub: "Paid out of their own pocket", tone: "blue" },
              { label: `Owed to ${roleNames(company).staffs.toLowerCase()}`, value: money(totals.staff), sub: "Claims and payments", tone: totals.staff > 0 ? "red" : "forest" },
              { label: "Company funds", value: money(funds.reduce((s, f) => s + Number(f.balance || 0), 0)), sub: funds.map((f) => `${f.name} ${money(f.balance)}`).slice(0, 2).join(" · "), tone: "forest" },
            ].map((t) => (
              <div key={t.label} className={`pay-tile tone-${t.tone}`}>
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
              <option value="managers">{roleNames(company).managers}</option>
              <option value="staff">{roleNames(company).staffs}</option>
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

          {visible.length === 0 ? (
            <div className="card" style={{ color: "var(--muted)", textAlign: "center", padding: 24 }}>
              {show === "owed" ? "Nobody is owed money right now." : "No one matches your search."}
            </div>
          ) : (
            <div className="card expense-list">
              <div className="payments-row payments-head">
                <input type="checkbox" checked={allVisibleSelected} onChange={toggleAll} aria-label="Select all" />
                <span>Person</span>
                <span className="payments-num">Owed</span>
                <span />
              </div>
              {visible.map((p) => {
                const me = p.userId === String(user.id);
                return (
                  <div key={p.userId} className={`payments-row ${selected.has(p.userId) ? "is-selected" : ""}`}>
                    <input type="checkbox" checked={selected.has(p.userId)} disabled={!payable(p)} onChange={() => toggle(p.userId)} aria-label={`Select ${p.name}`} />
                    <span className="payments-person">
                      <span className="payments-avatar">{initial(p.name)}</span>
                      <span style={{ minWidth: 0 }}>
                        <span className="payments-name">
                          {p.name}{me ? " (you)" : ""}
                          <span className={`payments-role ${p.role}`}>{p.role === "manager" ? roleNames(company).manager : p.role === "staff" ? roleNames(company).staff : "Former"}</span>
                        </span>
                        <span className="payments-meta">
                          {p.claims > 0 ? `${money(p.claims)} in approved claims` : p.owed > 0 ? "Paid out of pocket" : "Nothing owed"}
                          {p.advance > 0 ? ` · holds ${money(p.advance)} voucher money` : ""}
                        </span>
                      </span>
                    </span>
                    <span className="payments-num" style={{ color: p.owed > 0 ? "var(--terracotta)" : "var(--muted)" }}>{money(p.owed)}</span>
                    <span className="payments-actions">
                      {p.owed > 0 && <button className="btn btn-outline btn-sm" onClick={() => setViewing(p)}>View bills</button>}
                      {payable(p) && <button className="btn btn-primary btn-sm" onClick={() => setPaying([p])}>Pay</button>}
                      {me && p.owed > 0 && <span className="payments-meta">Pick "{user.name} (You)" above to pay it</span>}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
          </>
          )}

          <h2 style={{ fontSize: 19, margin: "28px 0 12px" }}>Payment history</h2>
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
          {history.length === 0 ? (
            <div className="card" style={{ color: "var(--muted)", textAlign: "center", padding: 20 }}>No payments match.</div>
          ) : (
            <div className="card expense-list">
              {history.map((h) => (
                <div key={h.id} className="expense-row static">
                  <span className="expense-row-main">
                    <span className="expense-row-title">{h.personName}</span>
                    <span className="expense-row-meta">{formatDate(h.date)} · {h.how}{h.method ? ` · ${h.method}` : ""}{h.reference ? ` · Ref ${h.reference}` : ""} · by {h.by}</span>
                  </span>
                  <span className="expense-row-amount" style={{ color: "var(--forest)" }}>{money(h.amount)}</span>
                </div>
              ))}
            </div>
          )}
        </>
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
  const [method, setMethod] = useState("UPI");
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
          <select className="field-select" value={fundId} onChange={(e) => setFundId(e.target.value)}>
            {funds.map((f) => <option key={f.fundId} value={f.fundId}>{f.name} · {money(f.balance)}</option>)}
          </select>
          {short && <div style={{ marginTop: 6, fontSize: 12, color: "var(--terracotta)", fontWeight: 600 }}>Only {money(fund.balance)} available in {fund.name}. You can add money when you pay.</div>}
        </>
      )}

      <label className="field-label" style={{ display: "block", marginTop: 12 }}>Payment method</label>
      <select className="field-select" value={method} onChange={(e) => setMethod(e.target.value)}>
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
