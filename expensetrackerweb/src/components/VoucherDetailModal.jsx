import { useEffect, useState } from "react";
import Modal from "./Modal.jsx";
import { getLedgerExpenseReceipts } from "../api.js";
import { formatDateTime, money, VOUCHER_STATUS } from "../utils.js";


const boxStyle = { margin: "18px 0", padding: "4px 14px", background: "var(--slate-bg)", border: "1px solid var(--slate-border-2)", borderRadius: 12 };
const rowStyle = { display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 16, padding: "9px 0", fontSize: 13 };
const subStyle = { display: "block", fontSize: 11.5, color: "var(--muted)", fontWeight: 400, marginTop: 2 };
const round = (n) => Math.round(n * 100) / 100;

// Everything about one voucher: who got it, who paid for it, and how it was claimed (with the claim receipt).
export default function VoucherDetailModal({ voucher, user, onClose, onCancel, onDelete, onCloseVoucher }) {
  const isCreator = String(voucher.createdBy?._id || voucher.createdBy) === String(user.id);
  const [receipt, setReceipt] = useState({ loading: Boolean(voucher.expenseId), src: "" });

  useEffect(() => {
    if (!voucher.expenseId) return undefined;
    let active = true;
    getLedgerExpenseReceipts(voucher.expenseId, user.id).then((res) => {
      if (active) setReceipt({ loading: false, src: res.success ? res.attachment || "" : "" });
    });
    return () => { active = false; };
  }, [voucher.expenseId, user.id]);

  const status = VOUCHER_STATUS[voucher.status] || VOUCHER_STATUS.open;
  const claimed = voucher.status === "claimed";
  const left = claimed ? round(voucher.amount - voucher.claimedAmount) : 0;
  const fromHeld = claimed ? round(Math.max(0, voucher.fromAdvance - Math.min(voucher.amount, voucher.claimedAmount))) : 0;

  const rows = [
    ["Given to", voucher.recipientId?.name || "Staff"],
    ["Given by", voucher.createdBy?.name || "Manager"],
    ["Given on", formatDateTime(voucher.createdAt)],
    voucher.fundedBy === "company"
      ? ["Paid by", <span key="paid">Company<span style={subStyle}>From {voucher.fundName || "company fund"}</span></span>]
      : ["Paid by", <span key="paid">{voucher.createdBy?.name || "Manager"} (self)<span style={subStyle}>The company owes them this amount</span></span>],
    claimed && ["Amount spent", <strong key="spent">{money(voucher.claimedAmount)}</strong>],
    claimed && ["Claimed on", formatDateTime(voucher.claimedAt)],
    claimed && left > 0 && ["Left with staff", <span key="left" style={{ color: "var(--terracotta)", fontWeight: 700 }}>{money(left)}<span style={subStyle}>Kept as their voucher balance</span></span>],
    claimed && fromHeld > 0 && ["From earlier balance", money(fromHeld)],
    claimed && voucher.owedToRecipient > 0 && ["Company owes staff", <span key="owed" style={{ color: "var(--terracotta)", fontWeight: 700 }}>{money(voucher.owedToRecipient)}<span style={subStyle}>Spent more than they held</span></span>],
    voucher.closedBy && ["Closed by", <span key="closed">{voucher.closedBy.name}<span style={subStyle}>Recorded as used by {voucher.recipientId?.name || "staff"} · {formatDateTime(voucher.closedAt)}</span></span>],
    voucher.status === "cancelled" && ["Cancelled by", voucher.cancelledBy?.name || "Manager"],
    voucher.status === "cancelled" && voucher.cancelledAt && ["Cancelled on", formatDateTime(voucher.cancelledAt)],
  ].filter(Boolean);

  return (
    <Modal onClose={onClose} maxWidth={520}>
      <div style={{ paddingRight: 40 }}>
        <span className="pill" style={{ fontSize: 11, background: status.bg, color: status.color }}>{status.label}</span>
      </div>
      <h2 style={{ margin: "14px 0 2px", fontSize: 21, lineHeight: 1.25, color: "var(--dark-text)", wordBreak: "break-word" }}>{voucher.purpose}</h2>
      <div style={{ fontFamily: "Inter, system-ui, sans-serif", fontSize: 30, fontWeight: 700, color: "var(--forest)" }}>{money(voucher.amount)}</div>

      <dl style={boxStyle}>
        {rows.map(([label, value], idx) => (
          <div key={label} style={{ ...rowStyle, borderTop: idx === 0 ? "none" : "1px solid var(--slate-border-2)" }}>
            <dt style={{ color: "var(--muted)", margin: 0 }}>{label}</dt>
            <dd style={{ margin: 0, textAlign: "right", color: "var(--dark-text)" }}>{value}</dd>
          </div>
        ))}
      </dl>

      {voucher.expenseId && (
        <>
          <div className="field-label" style={{ marginBottom: 8 }}>Claim receipt</div>
          {receipt.loading ? (
            <div className="spinner dark" />
          ) : receipt.src ? (
            <a href={receipt.src} target="_blank" rel="noreferrer">
              <img src={receipt.src} alt="Claim receipt" style={{ maxWidth: "100%", maxHeight: 280, borderRadius: 10, border: "1px solid var(--slate-border)" }} />
            </a>
          ) : (
            <div style={{ fontSize: 13, color: "var(--muted)" }}>No receipt was attached.</div>
          )}
        </>
      )}

      <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
        {voucher.status === "open" && isCreator && onCloseVoucher && (
          <button type="button" className="btn btn-primary" style={{ flex: 1 }} onClick={() => onCloseVoucher(voucher)}>Close voucher</button>
        )}
        {voucher.status === "open" && isCreator && onDelete && (
          <button type="button" className="btn btn-outline-danger" style={{ flex: 1 }} onClick={() => onDelete(voucher)}>Delete</button>
        )}
        {voucher.status === "open" && isCreator && onCancel && (
          <button type="button" className="btn btn-outline-danger" style={{ flex: 1 }} onClick={() => onCancel(voucher)}>Cancel voucher</button>
        )}
        <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Close</button>
      </div>
    </Modal>
  );
}
