import { useEffect, useState } from "react";
import Modal from "./Modal.jsx";
import { getLoanDetail, getLoanReceipts } from "../api.js";
import { formatDate, formatDateTime, money } from "../utils.js";

const initials = (name) => String(name || "?").trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase();

function Person({ role, name, company }) {
  return (
    <div className="loan-person">
      <span className="loan-avatar">{initials(name)}</span>
      <span style={{ minWidth: 0 }}>
        <span className="loan-person-role">{role}</span>
        <span className="loan-person-name">{name}</span>
        <span className="loan-person-sub">Manager of {company}</span>
      </span>
    </div>
  );
}

function Receipt({ label, src }) {
  return (
    <a className="loan-receipt" href={src} target="_blank" rel="noreferrer" title={`Open ${label.toLowerCase()}`}>
      <img src={src} alt={label} />
      <span>{label}</span>
    </a>
  );
}

const Loading = ({ text }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 10, color: "var(--muted)", fontSize: 13, padding: "10px 0" }}>
    <div className="spinner dark" style={{ width: 18, height: 18, borderWidth: 2 }} /> {text}
  </div>
);

// Inter-company loan: which bill it paid, who started the payment and who confirmed it, and the repayments.
// initialLoan is the row from the list, so the header shows at once while the rest loads.
export default function LoanDetailModal({ initialLoan, companyId, user, onClose, onRepay, onReceive, onDelete, refreshKey }) {
  const loanId = initialLoan._id;
  const [data, setData] = useState(null);
  const [error, setError] = useState("");
  const [receipts, setReceipts] = useState(null);

  useEffect(() => {
    let active = true;
    getLoanDetail(loanId, user.id).then((res) => {
      if (!active) return;
      if (!res.success) return setError(res.message || "Could not load loan details");
      setData(res);
      // images last: they are the heavy part of the response
      if (res.bill?.hasAttachment || res.bill?.hasPaymentReceipt) {
        getLoanReceipts(loanId, user.id).then((r) => { if (active && r.success) setReceipts(r); });
      }
    });
    return () => { active = false; };
  }, [loanId, user.id, refreshKey]);

  const loan = data?.loan || initialLoan;
  const { bill = null, group = null, initiatedBy = null, confirmedBy = null, repayments = [] } = data || {};
  const loading = !data && !error;
  const lender = loan.lenderCompanyId?.name || "Another company";
  const borrower = loan.borrowerCompanyId?.name || "Another company";
  const weBorrowed = String(loan.borrowerCompanyId?._id) === String(companyId);
  const balance = Number(loan.balance || 0);
  const amount = Number(loan.amount || 0);
  const repaid = Math.max(0, Math.round((amount - balance) * 100) / 100);
  const open = balance > 0;
  const pct = amount > 0 ? Math.min(100, Math.round((repaid / amount) * 100)) : 0;
  const sourceLabel = loan.source === "expense" ? "Paid an expense" : loan.source === "group" ? "Paid a group's expenses" : "Direct loan";
  // the loan itself, then each repayment (reversed ones shown crossed out, not counted)
  const statement = [];
  let due = amount;
  statement.push({ _id: "loan", date: loan.createdAt, label: weBorrowed ? `Borrowed from ${lender}` : `Lent to ${borrower}`, meta: [loan.note || sourceLabel, loan.method, loan.reference && `Ref ${loan.reference}`].filter(Boolean).join(" · "), taken: amount, due });
  for (const r of repayments) {
    if (!r.reversed) due = Math.round((due - r.amount) * 100) / 100;
    statement.push({ _id: r._id, date: r.date, label: weBorrowed ? "Repaid" : "Received back", meta: [r.by && `by ${r.by}`, r.byLender && "marked received by lender", r.method, r.reference && `Ref ${r.reference}`, r.reversed && "reversed"].filter(Boolean).join(" · "), paid: r.amount, reversed: r.reversed, due: Math.max(0, due) });
  }
  const method = bill?.method || loan.method;
  const reference = bill?.reference || loan.reference;

  return (
    <Modal onClose={onClose} maxWidth={560}>
      {/* Header */}
      <div style={{ paddingRight: 44 }}>
        <div className="loan-chips-row">
          <span className={`loan-chip ${weBorrowed ? "bad" : "good"}`}>{weBorrowed ? "Borrowed" : "Lent"}</span>
          <span className="loan-chip">{sourceLabel}</span>
          {!open && <span className="loan-chip good">Repaid</span>}
        </div>
        <h2 style={{ margin: 0, fontSize: 20 }}>{weBorrowed ? `Loan from ${lender}` : `Loan to ${borrower}`}</h2>
        <div style={{ fontSize: 13, color: "var(--muted)", marginTop: 2 }}>Recorded {formatDateTime(loan.createdAt)}{loan.createdBy?.name ? ` by ${loan.createdBy.name}` : ""}</div>
        {loan.note && (
          <div className="loan-reason">
            <span className="loan-label">{loan.source === "direct" ? "Reason for borrowing" : "Note"}</span>
            <span>{loan.note}</span>
          </div>
        )}
      </div>

      {/* Money flow */}
      <div className="loan-flow">
        <div className="loan-flow-node">
          <span className="loan-flow-role">Paid by</span>
          <span className="loan-flow-name">{lender}</span>
        </div>
        <div className="loan-flow-arrow">
          <span>{money(amount)}</span>
          <svg width="100%" height="10" viewBox="0 0 100 10" preserveAspectRatio="none" aria-hidden="true">
            <line x1="0" y1="5" x2="94" y2="5" stroke="currentColor" strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
            <path d="M92 1 L100 5 L92 9" fill="none" stroke="currentColor" strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
          </svg>
        </div>
        <div className="loan-flow-node" style={{ textAlign: "right" }}>
          <span className="loan-flow-role">Borrowed by</span>
          <span className="loan-flow-name">{borrower}</span>
        </div>
      </div>

      {/* Balance */}
      <div className="loan-balance">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12 }}>
          <div>
            <div className="loan-label">{open ? "Still due" : "Fully repaid"}</div>
            <div className="loan-due" style={{ color: open ? "var(--terracotta)" : "var(--forest)" }}>{money(open ? balance : amount)}</div>
          </div>
          <div style={{ textAlign: "right", fontSize: 13, color: "var(--muted)" }}>
            {money(repaid)} repaid
            <br />of {money(amount)}
          </div>
        </div>
        <div className="loan-progress"><span style={{ width: `${pct}%` }} /></div>
        {(method || reference) && (
          <div className="loan-chips">
            {method && <span>{method}</span>}
            {reference && <span style={{ fontFamily: "monospace" }}>Ref {reference}</span>}
          </div>
        )}
      </div>

      {loading && <Loading text="Loading bill and repayments…" />}
      {error && <div style={{ color: "var(--terracotta)", fontSize: 13, padding: "8px 0" }}>{error}</div>}

      {/* People */}
      {data && (initiatedBy || confirmedBy) && (
        <div className="loan-people">
          {initiatedBy && <Person role="Payment initiated by" name={initiatedBy.name} company={borrower} />}
          {confirmedBy && <Person role="Confirmed by" name={confirmedBy.name} company={lender} />}
        </div>
      )}

      {/* Bill */}
      {bill && (
        <section className="loan-section">
          <h3>Bill paid</h3>
          <div className="loan-bill">
            <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "flex-start" }}>
              <div style={{ minWidth: 0 }}>
                <div style={{ fontWeight: 700, fontSize: 16, color: "var(--dark-text)", wordBreak: "break-word" }}>{bill.description}</div>
                <div style={{ fontSize: 13, color: "var(--muted)", marginTop: 2 }}>{bill.category || "General"} · {formatDate(bill.date)}</div>
              </div>
              <div style={{ fontFamily: "Helvetica Neue, Helvetica, Arial, sans-serif", fontWeight: 700, fontSize: 20, color: "var(--forest)", whiteSpace: "nowrap" }}>{money(bill.amount)}</div>
            </div>
            {(bill.postedBy || bill.approvedBy) && (
              <div className="loan-bill-meta">
                {bill.postedBy && <span>Posted by <strong>{bill.postedBy}</strong></span>}
                {bill.approvedBy && <span>Approved by <strong>{bill.approvedBy}</strong></span>}
              </div>
            )}
            {(bill.hasAttachment || bill.hasPaymentReceipt) && (
              !receipts ? <Loading text="Loading receipts…" /> : (
                <div className="loan-receipts">
                  {receipts.attachment && <Receipt label="Bill receipt" src={receipts.attachment} />}
                  {receipts.paymentReceipt && <Receipt label="Payment proof" src={receipts.paymentReceipt} />}
                </div>
              )
            )}
          </div>
        </section>
      )}
      {data && !bill && loan.source === "expense" && <p style={{ fontSize: 13, color: "var(--muted)" }}>The bill for this loan was deleted.</p>}

      {/* Group */}
      {group && (
        <section className="loan-section">
          <h3>Group settled</h3>
          <div className="loan-bill">
            <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
              <div>
                <div style={{ fontWeight: 700, fontSize: 16, color: "var(--dark-text)" }}>{group.name}</div>
                <div style={{ fontSize: 13, color: "var(--muted)", marginTop: 2 }}>
                  {[group.createdBy && `Group admin ${group.createdBy}`, group.settledAt && `Settled ${formatDate(group.settledAt)}`].filter(Boolean).join(" · ")}
                </div>
              </div>
              {group.amount != null && <div style={{ fontFamily: "Helvetica Neue, Helvetica, Arial, sans-serif", fontWeight: 700, fontSize: 20, color: "var(--forest)" }}>{money(group.amount)}</div>}
            </div>
          </div>
        </section>
      )}

      {/* Statement: the loan, then every repayment, with what is still due after each */}
      {data && (
        <section className="loan-section">
          <h3>Statement</h3>
          <div className="dt-card" style={{ marginBottom: 8 }}>
            <div className="dt-scroll">
              <table className="dt">
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Details</th>
                    <th className="num">{weBorrowed ? "Paid" : "Lent"}</th>
                    <th className="num">{weBorrowed ? "Borrowed" : "Received"}</th>
                    <th className="num">Due</th>
                  </tr>
                </thead>
                <tbody>
                  {statement.map((r) => {
                    // money out on the left, in on the right (same as every statement)
                    const out = weBorrowed ? r.paid : r.taken;
                    const inn = weBorrowed ? r.taken : r.paid;
                    return (
                      <tr key={r._id} style={r.reversed ? { opacity: 0.5, textDecoration: "line-through" } : undefined}>
                        <td className="nowrap">{formatDate(r.date)}</td>
                        <td className="dt-wrap-text"><span className="dt-strong">{r.label}</span>{r.meta && <span className="dt-sub">{r.meta}</span>}</td>
                        <td className="num out">{out ? money(out) : "—"}</td>
                        <td className="num in">{inn ? money(inn) : "—"}</td>
                        <td className="num">{money(r.due)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
          {repayments.length === 0 && open && (
            <div className="loan-empty">No repayments yet{weBorrowed ? " — use Repay below when you pay it back." : " — use Received below when they pay you back."}</div>
          )}
        </section>
      )}

      <div style={{ display: "flex", gap: 10, marginTop: 22 }}>
        <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Close</button>
        {weBorrowed && open && onRepay && <button type="button" className="btn btn-primary" style={{ flex: 1 }} onClick={() => onRepay(loan)}>Repay {money(balance)}</button>}
        {!weBorrowed && open && onReceive && !loan.borrowerCompanyId?.external && <button type="button" className="btn btn-primary" style={{ flex: 1 }} onClick={() => onReceive(loan)}>Mark received</button>}
      </div>
      {/* only the person who recorded the borrow, and only before any repayment */}
      {onDelete && String(loan.createdBy?._id || loan.createdBy) === String(user.id) && (data ? repayments.filter((r) => !r.reversed).length === 0 : !(Number(loan.repaid) > 0)) && (
        <div style={{ textAlign: "center", marginTop: 10 }}>
          <button type="button" className="voucher-ticket-link" onClick={() => onDelete(loan)}>Delete this borrow</button>
        </div>
      )}
    </Modal>
  );
}
