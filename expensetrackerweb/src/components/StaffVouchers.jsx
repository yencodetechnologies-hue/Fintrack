import { useCallback, useEffect, useState } from "react";
import { cancelVoucher, deleteVoucher, getVouchers } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { formatDate, money } from "../utils.js";
import ClaimVoucherModal from "./ClaimVoucherModal.jsx";
import ConfirmDialog from "./ConfirmDialog.jsx";

// Home: open vouchers, highlighted.
// Staff see their own (Claim) and hand-backs waiting for a manager.
// Managers see every open voucher in the company; Close / Cancel / Delete only on the ones they created.
export default function StaffVouchers({ companyId, company, user, isAdmin = false, can = () => true, refreshKey, onChanged }) {
  const { showToast } = useToast();
  const [data, setData] = useState({ vouchers: [], returns: [], people: [], myAdvance: 0 });
  const [claiming, setClaiming] = useState(null);
  const [closing, setClosing] = useState(null);
  const [cancelling, setCancelling] = useState(null);
  const [deleting, setDeleting] = useState(null);

  const load = useCallback(async () => {
    const res = await getVouchers(companyId, user.id);
    if (res.success) setData({ vouchers: res.vouchers || [], returns: res.returns || [], people: res.people || [], myAdvance: Number(res.myAdvance || 0) });
  }, [companyId, user.id]);

  useEffect(() => {
    load();
  }, [load, refreshKey]);

  const changed = () => {
    load();
    onChanged?.();
  };

  async function confirmCancel() {
    const voucher = cancelling;
    setCancelling(null);
    const res = await cancelVoucher(voucher._id, user.id);
    if (res.success) {
      showToast(`Voucher cancelled · ${money(voucher.amount)} returned`);
      changed();
    } else showToast(res.message || "Could not cancel voucher", "error");
  }

  async function confirmDelete() {
    const voucher = deleting;
    setDeleting(null);
    const res = await deleteVoucher(voucher._id, user.id);
    if (res.success) {
      showToast(`Voucher deleted · ${money(voucher.amount)} returned`);
      changed();
    } else showToast(res.message || "Could not delete voucher", "error");
  }

  const open = data.vouchers.filter((v) => v.status === "open");
  const pendingReturns = isAdmin ? [] : data.returns.filter((r) => r.status === "pending" || r.status === "processing");
  if (!open.length && !pendingReturns.length) return null;

  const heldOf = (v) => Math.max(0, Number(data.people.find((p) => String(p.userId) === String(v.recipientId?._id || v.recipientId))?.held || 0));

  return (
    <section style={{ marginBottom: 22 }}>
      <h2 style={{ margin: "0 0 12px", fontSize: 20 }}>{isAdmin ? "Open vouchers" : "Vouchers"}</h2>
      <div style={{ display: "grid", gap: 10 }}>
        {open.map((v) => {
          const mine = String(v.createdBy?._id || v.createdBy) === String(user.id);
          const recipient = v.recipientId?.name || "Staff";
          const creator = mine ? "you" : v.createdBy?.name || "Manager";
          const days = Math.max(0, Math.floor((Date.now() - new Date(v.createdAt).getTime()) / 86400000));
          const age = days === 0 ? "Given today" : days === 1 ? "Open 1 day" : `Open ${days} days`;
          const funded = v.fundedBy === "company" ? `Company${v.fundName ? ` · ${v.fundName}` : ""}` : `${mine ? "You" : v.createdBy?.name || "Manager"} (self)`;
          return (
            <div key={v._id} className="voucher-ticket">
              <div className="voucher-ticket-main">
                <div className="voucher-ticket-icon" aria-hidden="true">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M2 9a3 3 0 0 1 0 6v2a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-2a3 3 0 0 1 0-6V7a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2Z" />
                    <path d="M13 5v2" />
                    <path d="M13 17v2" />
                    <path d="M13 11v2" />
                  </svg>
                </div>
                <div className="voucher-ticket-body">
                  <div className="voucher-ticket-tag">
                    <span>{isAdmin ? "Open voucher" : "New voucher"}</span>
                    <span className="voucher-ticket-age">{age}</span>
                  </div>
                  <div className="voucher-ticket-title">{v.purpose}</div>
                  <div className="voucher-ticket-meta">
                    {isAdmin ? (
                      <span className="voucher-ticket-person" title={`Given to ${recipient}`}>
                        <span className="voucher-ticket-avatar">{recipient.trim().charAt(0).toUpperCase()}</span>
                        {recipient}
                      </span>
                    ) : (
                      <span>From <strong>{v.createdBy?.name || "Manager"}</strong></span>
                    )}
                    <span className="voucher-ticket-dot" />
                    <span>Paid by {funded}</span>
                    <span className="voucher-ticket-dot" />
                    <span>{formatDate(v.createdAt)}{isAdmin ? ` · by ${creator}` : ""}</span>
                  </div>
                </div>
              </div>
              <div className="voucher-ticket-stub">
                <div className="voucher-ticket-amount-label">Amount</div>
                <div className="voucher-ticket-amount">{money(v.amount)}</div>
                {!isAdmin && can("vouchers") && (
                  <button className="btn btn-primary voucher-ticket-btn" onClick={() => setClaiming(v)}>Claim voucher</button>
                )}
                {isAdmin && mine && can("vouchers") && (
                  <div className="voucher-ticket-actions">
                    <button className="btn btn-primary voucher-ticket-btn" onClick={() => setClosing(v)}>Close voucher</button>
                    <div className="voucher-ticket-links">
                      <button type="button" className="voucher-ticket-link" onClick={() => setCancelling(v)}>Cancel</button>
                      <span aria-hidden="true">·</span>
                      <button type="button" className="voucher-ticket-link" onClick={() => setDeleting(v)}>Delete</button>
                    </div>
                  </div>
                )}
                {isAdmin && !mine && <div className="voucher-ticket-note">Only {v.createdBy?.name || "its creator"} can close it</div>}
              </div>
            </div>
          );
        })}
        {pendingReturns.map((r) => (
          <div key={r._id} className="card" style={{ padding: "10px 14px", fontSize: 13, color: "var(--muted)" }}>
            Hand-back of <strong style={{ color: "var(--dark-text)" }}>{money(r.amount)}</strong> waiting for a manager to confirm · {formatDate(r.createdAt)}
          </div>
        ))}
      </div>

      {claiming && (
        <ClaimVoucherModal voucher={claiming} company={company} user={user} held={data.myAdvance} onClose={() => setClaiming(null)} onClaimed={changed} />
      )}
      {closing && (
        <ClaimVoucherModal mode="close" voucher={closing} company={company} user={user} held={heldOf(closing)} onClose={() => setClosing(null)} onClaimed={changed} />
      )}
      {deleting && (
        <ConfirmDialog
          title="Delete voucher?"
          message={`${money(deleting.amount)} for "${deleting.purpose}" goes back to ${deleting.fundedBy === "company" ? deleting.fundName || "the company fund" : "you (removed from what the company owes you)"}, and the voucher is removed from the lists. Use Cancel instead to keep it listed as cancelled.`}
          confirmLabel="Delete voucher"
          danger
          onConfirm={confirmDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
      {cancelling && (
        <ConfirmDialog
          title="Cancel voucher?"
          message={`${money(cancelling.amount)} for "${cancelling.purpose}" goes back to ${cancelling.fundedBy === "company" ? cancelling.fundName || "the company fund" : "you (removed from what the company owes you)"}.`}
          confirmLabel="Cancel voucher"
          danger
          onConfirm={confirmCancel}
          onCancel={() => setCancelling(null)}
        />
      )}
    </section>
  );
}
