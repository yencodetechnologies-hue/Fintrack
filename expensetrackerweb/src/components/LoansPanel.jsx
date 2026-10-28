import { useEffect, useMemo, useState } from "react";
import { getLoanPartyStatement } from "../api.js";
import { formatDate, money } from "../utils.js";

const kindLabel = { borrowed: "Borrowed", repaid: "Repaid", lent: "Lent", received: "Received back" };

// Loans tab: every company / person this company borrowed from or lent to, with what is still outstanding.
// Click one for its statement (all loans and repayments by date); click a statement row for that loan.
export default function LoansPanel({ companyId, user, loans, pending = [], refreshKey, onOpenLoan }) {
  const [partyId, setPartyId] = useState(null);

  // one row per counterparty: net outstanding (> 0 this company owes them, < 0 they owe this company)
  const parties = useMemo(() => {
    const map = new Map();
    for (const loan of loans) {
      const weBorrowed = String(loan.borrowerCompanyId?._id || loan.borrowerCompanyId) === String(companyId);
      const other = weBorrowed ? loan.lenderCompanyId : loan.borrowerCompanyId;
      const id = String(other?._id || other);
      const row = map.get(id) || { id, name: other?.name || "Another company", person: other?.lenderKind === "person", external: Boolean(other?.external), owed: 0, count: 0, open: 0, last: null };
      row.owed += weBorrowed ? Number(loan.balance || 0) : -Number(loan.balance || 0);
      row.count += 1;
      if (Number(loan.balance) > 0) row.open += 1;
      if (!row.last || new Date(loan.createdAt) > new Date(row.last)) row.last = loan.createdAt;
      map.set(id, row);
    }
    // borrowings the lender hasn't confirmed yet: listed (and counted as waiting), not in the outstanding
    for (const e of pending) {
      const weBorrowed = String(e.companyId?._id || e.companyId) === String(companyId);
      const other = weBorrowed ? e.payerCompanyId : e.companyId;
      const id = String(other?._id || other);
      const row = map.get(id) || { id, name: other?.name || "Another company", person: other?.lenderKind === "person", external: Boolean(other?.external), owed: 0, count: 0, open: 0, last: null };
      row.waiting = (row.waiting || 0) + 1;
      const d = e.date || e.createdAt;
      if (!row.last || new Date(d) > new Date(row.last)) row.last = d;
      map.set(id, row);
    }
    return [...map.values()]
      .map((r) => ({ ...r, owed: Math.round(r.owed * 100) / 100 }))
      .sort((a, b) => Math.abs(b.owed) - Math.abs(a.owed) || new Date(b.last) - new Date(a.last));
  }, [loans, companyId]);

  const totals = useMemo(() => ({
    weOwe: parties.reduce((s, p) => s + Math.max(0, p.owed), 0),
    owedToUs: parties.reduce((s, p) => s + Math.max(0, -p.owed), 0),
  }), [parties]);

  const party = parties.find((p) => p.id === partyId);
  if (party) return <PartyStatement companyId={companyId} user={user} party={party} refreshKey={refreshKey} onBack={() => setPartyId(null)} onOpenLoan={onOpenLoan} />;

  return (
    <>
      <div className="accounts-summary" style={{ marginTop: 18 }}>
        <div className="stat-card"><small>We owe</small><strong className="out">{money(totals.weOwe)}</strong></div>
        <div className="stat-card"><small>Owed to us</small><strong className="in">{money(totals.owedToUs)}</strong></div>
        <div className="stat-card"><small>Companies / people</small><strong>{parties.length}</strong></div>
      </div>
      {parties.length === 0 ? (
        <div className="card" style={{ color: "var(--muted)", padding: "12px 16px", fontSize: 13 }}>No loans yet. Use Record a loan when you borrow from a company or a person.</div>
      ) : (
        <div className="card expense-list">
          {parties.map((p) => (
            <div key={p.id} className="expense-row loan-party-row" role="button" tabIndex={0} style={{ cursor: "pointer" }} onClick={() => setPartyId(p.id)} onKeyDown={(e) => { if (e.key === "Enter") setPartyId(p.id); }}>
              <span className="loan-party-amount">
                <strong style={{ color: p.owed > 0 ? "var(--terracotta)" : p.owed < 0 ? "var(--forest)" : "var(--muted)" }}>{money(Math.abs(p.owed))}</strong>
                <small>{p.owed > 0 ? "We owe" : p.owed < 0 ? "Owes us" : "Settled"}</small>
              </span>
              <span className="expense-row-main">
                <span className="expense-row-title">{p.name}</span>
                <span className="expense-row-meta">
                  {[p.person ? "Person" : p.external ? "Outside company" : "Company", p.count ? `${p.count} loan${p.count === 1 ? "" : "s"}` : "", p.count ? (p.open ? `${p.open} open` : "all repaid") : "", p.waiting ? `${p.waiting} awaiting confirmation` : "", `last ${formatDate(p.last)}`].filter(Boolean).join(" · ")}
                </span>
              </span>
              <span style={{ color: "var(--muted)", fontSize: 18 }} aria-hidden="true">›</span>
            </div>
          ))}
        </div>
      )}
    </>
  );
}

function PartyStatement({ companyId, user, party, refreshKey, onBack, onOpenLoan }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    getLoanPartyStatement(companyId, party.id, user.id).then((res) => {
      if (!active) return;
      if (!res.success) return setError(res.message || "Could not load the statement");
      setData(res);
    });
    return () => { active = false; };
  }, [companyId, party.id, user.id, refreshKey]);

  const t = data?.totals;
  const balance = t?.balance ?? party.owed;
  return (
    <>
      <button type="button" className="report-link" style={{ marginTop: 14 }} onClick={onBack}>‹ All loans</button>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12, flexWrap: "wrap", margin: "6px 0 12px" }}>
        <h2 style={{ fontSize: 20, margin: 0 }}>{party.name}</h2>
        <span style={{ fontWeight: 800, fontSize: 16, color: balance > 0 ? "var(--terracotta)" : balance < 0 ? "var(--forest)" : "var(--muted)" }}>
          {balance > 0 ? `We owe ${money(balance)}` : balance < 0 ? `Owes us ${money(-balance)}` : "Settled"}
        </span>
      </div>
      {error ? (
        <div className="card" style={{ color: "var(--terracotta)" }}>{error}</div>
      ) : !data ? (
        <div style={{ display: "flex", justifyContent: "center", padding: 40 }}><div className="spinner dark" /></div>
      ) : (
        <>
          <div className="accounts-summary">
            {t.borrowed > 0 && <div className="stat-card"><small>Borrowed</small><strong className="in">{money(t.borrowed)}</strong></div>}
            {t.borrowed > 0 && <div className="stat-card"><small>Repaid</small><strong className="out">{money(t.repaid)}</strong></div>}
            {t.lent > 0 && <div className="stat-card"><small>Lent</small><strong className="out">{money(t.lent)}</strong></div>}
            {t.lent > 0 && <div className="stat-card"><small>Received back</small><strong className="in">{money(t.received)}</strong></div>}
          </div>
          {data.rows.length === 0 ? (
            <div className="card" style={{ color: "var(--muted)", padding: 20, textAlign: "center" }}>No loans with {party.name}.</div>
          ) : (
            <div className="card accounts-statement">
              <div className="statement-row statement-head" aria-hidden="true">
                <span>Date</span>
                <span>Details</span>
                <span className="num">Credit (in)</span>
                <span className="num">Debit (out)</span>
                <span className="num">Balance</span>
              </div>
              {data.rows.map((r) => (
                <div key={r._id} className="statement-row" role="button" tabIndex={0} style={{ cursor: "pointer" }} title="View this loan" onClick={() => onOpenLoan(r.loanId)} onKeyDown={(e) => { if (e.key === "Enter") onOpenLoan(r.loanId); }}>
                  <span className="statement-date"><strong>{formatDate(r.date)}</strong></span>
                  <span className="statement-details">
                    <strong>{kindLabel[r.kind]}{r.particulars ? ` · ${r.particulars}` : ""}</strong>
                    <small>{rowMeta(r) || "Tap to view the loan"}</small>
                  </span>
                  <span className="num in" data-label="In">{r.moneyIn ? `+${money(r.moneyIn)}` : "—"}</span>
                  <span className="num out" data-label="Out">{r.moneyOut ? `−${money(r.moneyOut)}` : "—"}</span>
                  <span className="num statement-balance" data-label="Balance">
                    {r.balance > 0 ? `${money(r.balance)} due` : r.balance < 0 ? `${money(-r.balance)} to get` : money(0)}
                  </span>
                </div>
              ))}
            </div>
          )}
          {data.pending?.length > 0 && (
            <>
              <h3 style={{ fontSize: 15, margin: "18px 0 8px" }}>Awaiting confirmation</h3>
              <div className="card accounts-statement">
                {data.pending.map((r) => (
                  <div key={r._id} className="statement-row">
                    <span className="statement-date"><strong>{formatDate(r.date)}</strong></span>
                    <span className="statement-details">
                      <strong>{r.kind === "borrowed" ? "Borrowing" : "Asked to pay"} · {r.particulars}</strong>
                      <small>{[rowMeta(r), r.kind === "borrowed" ? `waiting for ${party.name} to confirm` : "accept or reject it under Payment confirmations"].filter(Boolean).join(" · ")}</small>
                    </span>
                    <span className="num" data-label="Amount" style={{ color: "var(--muted)" }}>{money(r.amount)}</span>
                    <span className="num" style={{ color: "var(--muted)", fontSize: 12 }}>Not counted yet</span>
                    <span />
                  </div>
                ))}
              </div>
            </>
          )}
        </>
      )}
    </>
  );
}

// category · who took it · who recorded it · method · reference
const rowMeta = (r) =>
  [
    r.category,
    r.takenBy ? `taken by ${r.takenBy}` : "",
    r.by && r.by !== r.takenBy ? `recorded by ${r.by}` : "",
    r.method,
    r.reference ? `Ref ${r.reference}` : "",
  ].filter(Boolean).join(" · ");
