import { useEffect, useMemo, useState } from "react";
import { getLoanPartyStatement } from "../api.js";
import { formatDate, money } from "../utils.js";
import { TableCard, pageOf, tableMeta, usePageSize } from "./DataTable.jsx";

const kindLabel = { borrowed: "Borrowed", repaid: "Repaid", lent: "Lent", received: "Received back" };

// Loans tab: every company / person this company borrowed from or lent to, with what is still outstanding.
// Click one for its statement (all loans and repayments by date); click a statement row for that loan.
export default function LoansPanel({ companyId, user, loans, pending = [], refreshKey, focus, onOpenLoan }) {
  const [partyId, setPartyId] = useState(null);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = usePageSize();
  // the page can open one company / person (right after recording a loan: the lender it came from)
  const [seenFocus, setSeenFocus] = useState(focus?.n);
  if (focus && focus.n !== seenFocus) {
    setSeenFocus(focus.n);
    setPartyId(focus.id || null);
  }

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
      <TableCard
        title="Loans"
        meta={tableMeta(parties.length, pageOf(parties, page, pageSize).page, pageOf(parties, page, pageSize).pages, "companies / people")}
        page={pageOf(parties, page, pageSize).page}
        pages={pageOf(parties, page, pageSize).pages}
        onPage={setPage}
        count={parties.length}
        pageSize={pageSize}
        onPageSize={(n) => { setPageSize(n); setPage(1); }}
      >
        {parties.length === 0 ? (
          <div className="dt-empty">No loans yet. Use Record a loan when you borrow from a company or a person.</div>
        ) : (
          <table className="dt">
            <thead>
              <tr>
                <th>Outstanding</th>
                <th>Company / person</th>
                <th>Type</th>
                <th className="center">Loans</th>
                <th>Status</th>
                <th>Last</th>
              </tr>
            </thead>
            <tbody>
              {pageOf(parties, page, pageSize).rows.map((p) => (
                <tr key={p.id} className="dt-click" tabIndex={0} onClick={() => setPartyId(p.id)} onKeyDown={(e) => { if (e.key === "Enter") setPartyId(p.id); }}>
                  <td className={`num ${p.owed > 0 ? "out" : p.owed < 0 ? "in" : "muted"}`} style={{ textAlign: "left" }}>
                    {money(Math.abs(p.owed))}
                    <span className="dt-sub" style={{ fontWeight: 600 }}>{p.owed > 0 ? "We owe" : p.owed < 0 ? "Owes us" : "Settled"}</span>
                  </td>
                  <td className="dt-strong">{p.name}</td>
                  <td>{p.person ? "Person" : p.external ? "Outside company" : "Company"}</td>
                  <td className="center">{p.count}</td>
                  <td>
                    {p.count > 0 && <span className={`dt-status ${p.open ? "wait" : "good"}`}>{p.open ? `${p.open} open` : "All repaid"}</span>}
                    {p.waiting ? <span className="dt-sub">{p.waiting} awaiting confirmation</span> : null}
                  </td>
                  <td className="nowrap">{formatDate(p.last)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </TableCard>
    </>
  );
}

function PartyStatement({ companyId, user, party, refreshKey, onBack, onOpenLoan }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState("");
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = usePageSize();

  useEffect(() => {
    let active = true;
    getLoanPartyStatement(companyId, party.id, user.id).then((res) => {
      if (!active) return;
      if (!res.success) return setError(res.message || "Could not load the statement");
      setData(res);
    });
    return () => { active = false; };
  }, [companyId, party.id, user.id, refreshKey]);

  // running balances are worked out oldest first; the table lists the latest first
  const newestFirst = data ? [...data.rows].reverse() : [];
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
          <TableCard
            title="Statement"
            meta={tableMeta(data.rows.length, pageOf(newestFirst, page, pageSize).page, pageOf(newestFirst, page, pageSize).pages, "entries")}
            page={pageOf(newestFirst, page, pageSize).page}
            pages={pageOf(newestFirst, page, pageSize).pages}
            onPage={setPage}
            count={data.rows.length}
            pageSize={pageSize}
            onPageSize={(n) => { setPageSize(n); setPage(1); }}
          >
            {data.rows.length === 0 ? (
              <div className="dt-empty">No loans with {party.name}.</div>
            ) : (
              <table className="dt">
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Type</th>
                    <th>Details</th>
                    <th>Taken by</th>
                    <th>Method / Ref</th>
                    <th className="num">Debit (out)</th>
                    <th className="num">Credit (in)</th>
                    <th className="num">Balance</th>
                  </tr>
                </thead>
                <tbody>
                  {pageOf(newestFirst, page, pageSize).rows.map((r) => (
                    <tr key={r._id} className="dt-click" tabIndex={0} title="View this loan" onClick={() => onOpenLoan(r.loanId)} onKeyDown={(e) => { if (e.key === "Enter") onOpenLoan(r.loanId); }}>
                      <td className="nowrap">{formatDate(r.date)}</td>
                      <td className="nowrap">{kindLabel[r.kind]}</td>
                      <td className="dt-wrap-text">
                        <span className="dt-strong">{r.particulars}</span>
                        {r.category && <span className="dt-sub">{r.category}</span>}
                      </td>
                      <td>{r.takenBy || r.by || "—"}{r.by && r.takenBy && r.by !== r.takenBy && <span className="dt-sub">recorded by {r.by}</span>}</td>
                      <td>{r.method || "—"}{r.reference && <span className="dt-sub dt-mono">{r.reference}</span>}</td>
                      <td className="num out">{r.moneyOut ? money(r.moneyOut) : "—"}</td>
                      <td className="num in">{r.moneyIn ? money(r.moneyIn) : "—"}</td>
                      <td className="num">{r.balance > 0 ? `${money(r.balance)} due` : r.balance < 0 ? `${money(-r.balance)} to get` : money(0)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </TableCard>
          {data.pending?.length > 0 && (
            <TableCard title="Awaiting confirmation" meta={`${data.pending.length} not counted yet`} items={data.pending}>
              {(rows) => (
                <>
              <table className="dt">
                <thead>
                  <tr><th>Date</th><th>Type</th><th>Details</th><th>Taken by</th><th>Status</th><th className="num">Amount</th></tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r._id}>
                      <td className="nowrap">{formatDate(r.date)}</td>
                      <td className="nowrap">{r.kind === "borrowed" ? "Borrowing" : "Asked to pay"}</td>
                      <td className="dt-wrap-text"><span className="dt-strong">{r.particulars}</span>{r.category && <span className="dt-sub">{r.category}</span>}</td>
                      <td>{r.takenBy || "—"}</td>
                      <td><span className="dt-status wait">{r.kind === "borrowed" ? `Waiting for ${party.name}` : "Accept under Payment confirmations"}</span></td>
                      <td className="num muted">{money(r.amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            
                </>
              )}
            </TableCard>
          )}
        </>
      )}
    </>
  );
}

