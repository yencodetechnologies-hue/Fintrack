import { useState } from "react";
import { formatDate, formatDateTime, money, personId, personName } from "../utils.js";

export default function ExpenseCard({
  expense,
  user,
  isAdmin,
  companyName,
  showCompanyTotals,
  onPay,
  onReceive,
  onEdit,
  onEditSettlement,
  onToggleStatus,
  onDelete,
  onViewDetail,
}) {
  const [expanded, setExpanded] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);

  const creator = expense.createdBy;
  const creatorId = personId(creator);
  const creatorName = personName(creator);
  const isCreator = creatorId === user.id;

  const currentCreditor = expense.currentCreditor || creator;
  const creditorId = personId(currentCreditor);
  const creditorName = personName(currentCreditor);
  const isViewerCreditor = creditorId === user.id;

  const isPaid = expense.status === "paid";
  const settlements = expense.settlements || [];
  const settlement = expense.settlement || null;

  const settlementPayerName =
    settlement?.paidAs === "company" ? companyName : personName(settlement?.paidBy);
  const settlementPayerId = personId(settlement?.paidBy);
  const settlementRecipientName = personName(settlement?.paidTo, creatorName);

  const isPayer = settlementPayerId === user.id;
  const isReceiver = personId(settlement?.paidTo) === user.id;
  const canManagePayment = isAdmin || isCreator || isPayer || isReceiver;
  const isSubmitted = !expense.lifecycle || expense.lifecycle === "submitted";
  const canEditExpense =
    (isAdmin && !isPaid && settlements.length === 0) ||
    (!isAdmin && isCreator && isSubmitted && !isPaid && settlements.length === 0);
  const canDeleteExpense = isAdmin || (isCreator && !isPaid && settlements.length === 0);

  const logAsType = expense.logAs || (isPaid ? "company" : "self");
  const isCompanyLogged = logAsType === "company";

  let subtext;
  if (isPaid) {
    subtext = isCompanyLogged
      ? `Logged by ${companyName} (Company)`
      : isCreator
      ? `Logged by ${creatorName} (You • Paid)`
      : `Paid by ${creatorName}`;
  } else if (settlement) {
    subtext = isViewerCreditor
      ? `Paid to ${settlementRecipientName} • Owed to You`
      : `Owed to ${creditorName}`;
  } else {
    subtext = isCreator ? `Logged by ${creatorName} (You) • Owed to You` : `Logged by ${creatorName} • Owed to ${creditorName}`;
  }

  return (
    <div className="card" style={{ padding: 12, marginBottom: 10 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 8 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap", flex: 1, minWidth: 0 }}>
          <span className="pill pill-category">{expense.category || "General"}</span>
          <span style={{ fontSize: 11, color: "var(--muted)" }}>{formatDate(expense.date || expense.createdAt)}</span>
          <span className={`pill ${isPaid ? "pill-paid" : "pill-outstanding"}`}>{isPaid ? "PAID / SETTLED" : "OUTSTANDING"}</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          {canManagePayment && (
            <div style={{ position: "relative" }}>
              <button onClick={() => setMenuOpen((v) => !v)} style={iconBtnStyle}>⋮</button>
              {menuOpen && (
                <div style={menuStyle} onMouseLeave={() => setMenuOpen(false)}>
                  {canEditExpense && (
                    <button style={menuItemStyle} onClick={() => { setMenuOpen(false); onEdit(expense); }}>
                      ✎ Edit Expense
                    </button>
                  )}
                  {(isPaid || settlement) && (
                    <button style={menuItemStyle} onClick={() => { setMenuOpen(false); onEditSettlement(expense); }}>
                      ✎ Edit Payment Details
                    </button>
                  )}
                  <button style={menuItemStyle} onClick={() => { setMenuOpen(false); onToggleStatus(expense, isPaid ? "outstanding" : "paid"); }}>
                    {isPaid ? "↺ Change to Unpaid" : "✓ Mark as Paid / Settled"}
                  </button>
                  {canDeleteExpense && (
                    <button style={{ ...menuItemStyle, color: "var(--terracotta)" }} onClick={() => { setMenuOpen(false); onDelete(expense); }}>
                      🗑 Delete Expense
                    </button>
                  )}
                </div>
              )}
            </div>
          )}
          <button onClick={() => setExpanded((v) => !v)} style={iconBtnStyle}>{expanded ? "▲" : "▼"}</button>
        </div>
      </div>

      <div
        onClick={() => onViewDetail && onViewDetail(expense)}
        style={{ cursor: onViewDetail ? "pointer" : "default" }}
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 6 }}>
          <div style={{ fontWeight: 700, fontSize: 15 }}>{expense.description}</div>
          <div style={{ fontFamily: "Inter, system-ui, sans-serif", fontWeight: 700, fontSize: 16 }}>{money(expense.amount)}</div>
        </div>
        <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 2 }}>{subtext}</div>
      </div>

      {expanded && (
        <div style={{ marginTop: 10, paddingTop: 10, borderTop: "1px solid var(--slate-border-2)" }}>
          {expense.attachment && (
            <div style={{ marginBottom: 10 }}>
              <div style={{ fontSize: 11.5, fontWeight: 700, color: "var(--forest)", marginBottom: 6 }}>📎 Receipt Attached</div>
              <img src={expense.attachment} alt="Receipt" style={{ maxWidth: "100%", borderRadius: 10 }} />
            </div>
          )}

          {!isPaid && (
            isViewerCreditor ? (
              canManagePayment && (
                <button className="btn btn-outline btn-block" onClick={() => onReceive(expense)}>
                  ✓ Mark Payment Received
                </button>
              )
            ) : (
              (!showCompanyTotals || isAdmin) && (
                <button className="btn btn-primary btn-block" onClick={() => onPay(expense)}>
                  💳 Pay (₹{Number(expense.amount).toFixed(0)})
                </button>
              )
            )
          )}

          {settlements.length > 0 && (
            <div style={{ marginTop: 10 }}>
              <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 6 }}>Payment History ({settlements.length})</div>
              {settlements.map((s, idx) => {
                const payerLabel = s.paidAs === "company" ? companyName : personName(s.paidBy);
                return (
                  <div key={s._id || idx} style={{ fontSize: 12, color: "var(--muted)", padding: "4px 0" }}>
                    {idx + 1}. {payerLabel} → {personName(s.paidTo)} · {(s.paymentMode || "cash").toUpperCase()} · {formatDateTime(s.createdAt)}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

const iconBtnStyle = {
  width: 26,
  height: 26,
  borderRadius: 8,
  border: "none",
  background: "#F1F5F9",
  color: "var(--dark-text)",
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  fontSize: 13,
};

const menuStyle = {
  position: "absolute",
  right: 0,
  top: 30,
  background: "#fff",
  borderRadius: 12,
  boxShadow: "0 6px 20px rgba(0,0,0,0.18)",
  padding: 6,
  zIndex: 20,
  minWidth: 190,
};

const menuItemStyle = {
  display: "block",
  width: "100%",
  textAlign: "left",
  background: "none",
  border: "none",
  padding: "8px 10px",
  fontSize: 12.5,
  fontWeight: 600,
  borderRadius: 8,
  color: "var(--dark-text)",
};
