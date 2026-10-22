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
export default function LoanDetailModal({ initialLoan, companyId, user, onClose, onRepay }) {
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
  }, [loanId, user.id]);

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
  const method = bill?.method || loan.method;
  const reference = bill?.reference || loan.reference;

  return (
    <Modal onClose={onClose} maxWidth={560}>
      {/* Header */}
      <div style={{ paddingRight: 44 }}>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 10 }}>
          <span className={`row-tag ${weBorrowed ? "bad" : "good"}`}>{weBorrowed ? "Borrowed" : "Lent"}</span>
          <span className="pill pill-category" style={{ fontSize: 11 }}>{sourceLabel}</span>
          {!open && <span className="row-tag good">Repaid</span>}
        </div>
        <h2 style={{ margin: 0, fontSize: 20 }}>{weBorrowed ? `Loan from ${lender}` : `Loan to ${borrower}`}</h2>
        <div style={{ fontSize: 12.5, color: "var(--muted)", marginTop: 2 }}>Recorded {formatDateTime(loan.createdAt)}</div>
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
          <div style={{ textAlign: "right", fontSize: 12.5, color: "var(--muted)" }}>
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
                <div style={{ fontWeight: 700, fontSize: 15, color: "var(--dark-text)", wordBreak: "break-word" }}>{bill.description}</div>
                <div style={{ fontSize: 12.5, color: "var(--muted)", marginTop: 2 }}>{bill.category || "General"} · {formatDate(bill.date)}</div>
              </div>
              <div style={{ fontFamily: "Fraunces, serif", fontWeight: 700, fontSize: 18, color: "var(--forest)", whiteSpace: "nowrap" }}>{money(bill.amount)}</div>
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
                <div style={{ fontWeight: 700, fontSize: 15, color: "var(--dark-text)" }}>{group.name}</div>
                <div style={{ fontSize: 12.5, color: "var(--muted)", marginTop: 2 }}>
                  {[group.createdBy && `Group admin ${group.createdBy}`, group.settledAt && `Settled ${formatDate(group.settledAt)}`].filter(Boolean).join(" · ")}
                </div>
              </div>
              {group.amount != null && <div style={{ fontFamily: "Fraunces, serif", fontWeight: 700, fontSize: 18, color: "var(--forest)" }}>{money(group.amount)}</div>}
            </div>
          </div>
        </section>
      )}

      {/* Repayments */}
      {data && (
        <section className="loan-section">
          <h3>Repayments</h3>
          {repayments.length === 0 ? (
            <div className="loan-empty">No repayments yet{open && weBorrowed ? " — use Repay below when you pay it back." : "."}</div>
          ) : (
            <ol className="loan-timeline">
              {repayments.map((r) => (
                <li key={r._id} className={r.reversed ? "reversed" : ""}>
                  <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
                    <strong>{money(r.amount)}</strong>
                    <span style={{ color: "var(--muted)", fontSize: 12.5 }}>{formatDate(r.date)}</span>
                  </div>
                  <div style={{ fontSize: 12.5, color: "var(--muted)" }}>
                    {[r.by && `by ${r.by}`, r.method, r.reference && `Ref ${r.reference}`, r.reversed && "reversed"].filter(Boolean).join(" · ")}
                  </div>
                </li>
              ))}
            </ol>
          )}
        </section>
      )}

      <div style={{ display: "flex", gap: 10, marginTop: 22 }}>
        <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Close</button>
        {weBorrowed && open && onRepay && <button type="button" className="btn btn-primary" style={{ flex: 1 }} onClick={() => onRepay(loan)}>Repay {money(balance)}</button>}
      </div>
    </Modal>
  );
}
