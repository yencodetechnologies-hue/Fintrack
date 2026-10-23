import { useCallback, useEffect, useState } from "react";
import { cancelVoucher, decideAdvanceReturn, deleteVoucher, getVouchers } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { formatDate, money, VOUCHER_STATUS as STATUS } from "../utils.js";
import ConfirmDialog from "./ConfirmDialog.jsx";
import CreateVoucherModal from "./CreateVoucherModal.jsx";
import VoucherDetailModal from "./VoucherDetailModal.jsx";
import ClaimVoucherModal from "./ClaimVoucherModal.jsx";

const th = { textAlign: "left", fontSize: 11, fontWeight: 700, letterSpacing: 0.5, color: "var(--muted)", padding: "8px 10px", borderBottom: "1px solid var(--slate-border)" };
const td = { padding: "9px 10px", fontSize: 13, borderBottom: "1px solid var(--slate-border-2)" };
const num = { ...td, textAlign: "right", whiteSpace: "nowrap" };


// Managers: every voucher, what each staff member holds, and hand-backs to confirm.
export default function VouchersPanel({ companyId, company, user, members, funds, onChanged, refreshKey }) {
  const { showToast } = useToast();
  const [data, setData] = useState(null);
  const [filter, setFilter] = useState("all");
  const [creating, setCreating] = useState(false);
  const [cancelling, setCancelling] = useState(null);
  const [deleting, setDeleting] = useState(null);
  const [viewing, setViewing] = useState(null);
  // open voucher the creating manager is closing on the staff member's behalf
  const [closingVoucher, setClosingVoucher] = useState(null);
  const [busy, setBusy] = useState("");

  const load = useCallback(async () => {
    const res = await getVouchers(companyId, user.id);
    if (res.success) setData(res);
    else showToast(res.message || "Could not load vouchers", "error");
  }, [companyId, user.id, showToast]);

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

  async function decide(ret, accept) {
    setBusy(ret._id);
    const res = await decideAdvanceReturn(ret._id, user.id, accept);
    setBusy("");
    if (res.success) {
      showToast(accept ? `${money(ret.amount)} received into Cash` : "Hand-back declined");
      changed();
    } else showToast(res.message || "Could not update hand-back", "error");
  }

  const vouchers = data?.vouchers || [];
  const shown = filter === "all" ? vouchers : vouchers.filter((v) => v.status === filter);
  const pendingReturns = (data?.returns || []).filter((r) => r.status === "pending");
  const people = (data?.people || []).filter((p) => p.given || p.held);
  const totals = people.reduce((t, p) => ({ given: t.given + p.given, open: t.open + p.open, held: t.held + Math.max(0, p.held) }), { given: 0, open: 0, held: 0 });

  return (
    <>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 18 }}>
        <h1 style={{ fontSize: 26, margin: 0 }}>Vouchers</h1>
        <button className="btn btn-primary" onClick={() => setCreating(true)}>+ Create voucher</button>
      </div>

      {!data ? (
        <div style={{ display: "flex", justifyContent: "center", padding: 32 }}><div className="spinner dark" /></div>
      ) : (
        <>
          <div className="home-tiles staff m-voucher-tiles" style={{ maxWidth: 840, gridTemplateColumns: "repeat(3, minmax(0, 1fr))" }}>
            <div className="stat-card home-tile"><div className="home-tile-label">Given (not cancelled)</div><div className="home-tile-value">{money(totals.given)}</div></div>
            <div className="stat-card home-tile"><div className="home-tile-label">Open, not claimed</div><div className="home-tile-value">{money(totals.open)}</div></div>
            <div className="stat-card home-tile"><div className="home-tile-label">Held by staff</div><div className="home-tile-value" style={{ color: totals.held > 0 ? "var(--terracotta)" : undefined }}>{money(totals.held)}</div></div>
          </div>

          {pendingReturns.length > 0 && (
            <>
              <h2 style={{ margin: "4px 0 12px", fontSize: 19 }}>Hand-backs to confirm</h2>
              <div className="card expense-list" style={{ marginBottom: 20 }}>
                {pendingReturns.map((r) => {
                  const own = String(r.userId?._id || r.userId) === String(user.id);
                  return (
                    <div key={r._id} className="expense-row static">
                      <span className="expense-row-main">
                        <span className="expense-row-title">{r.userId?.name || "Staff"} is handing back cash</span>
                        <span className="expense-row-meta">{formatDate(r.createdAt)}{r.note ? ` · ${r.note}` : ""}</span>
                      </span>
                      <span className="expense-row-amount">{money(r.amount)}</span>
                      <span className="expense-row-action" style={{ display: "flex", gap: 6 }}>
                        {own ? (
                          <span style={{ fontSize: 12, color: "var(--muted)" }}>Another manager confirms</span>
                        ) : (
                          <>
                            <button className="btn btn-primary btn-sm" disabled={busy === r._id} onClick={() => decide(r, true)}>Received</button>
                            <button className="btn btn-outline btn-sm" disabled={busy === r._id} onClick={() => decide(r, false)}>Decline</button>
                          </>
                        )}
                      </span>
                    </div>
                  );
                })}
              </div>
            </>
          )}

          <div className="card" style={{ padding: 0, overflowX: "auto", marginBottom: 20 }}>
            <h3 style={{ fontSize: 16, margin: 0, padding: "14px 14px 6px" }}>By staff member</h3>
            {people.length === 0 ? (
              <div style={{ color: "var(--muted)", padding: "6px 14px 16px", fontSize: 13 }}>No vouchers given yet.</div>
            ) : (
              <table style={{ width: "100%", borderCollapse: "collapse", minWidth: 520 }}>
                <thead>
                  <tr>
                    <th style={th}>NAME</th>
                    <th style={{ ...th, textAlign: "right" }}>GIVEN</th>
                    <th style={{ ...th, textAlign: "right" }}>CLAIMED</th>
                    <th style={{ ...th, textAlign: "right" }}>OPEN</th>
                    <th style={{ ...th, textAlign: "right" }}>HOLDING</th>
                  </tr>
                </thead>
                <tbody>
                  {people.map((p) => (
                    <tr key={p.userId}>
                      <td style={td}><strong>{p.name}</strong></td>
                      <td style={num}>{money(p.given)}</td>
                      <td style={num}>{money(p.claimed)}</td>
                      <td style={num}>{money(p.open)}</td>
                      <td style={{ ...num, fontWeight: 800, color: p.held > 0 ? "var(--terracotta)" : "var(--dark-text)" }}>{money(Math.max(0, p.held))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>

          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 10 }}>
            <h2 style={{ margin: 0, fontSize: 19 }}>All vouchers</h2>
            <select className="field-select" style={{ width: "auto" }} value={filter} onChange={(e) => setFilter(e.target.value)}>
              <option value="all">All</option>
              <option value="open">Open</option>
              <option value="claimed">Claimed</option>
              <option value="cancelled">Cancelled</option>
            </select>
          </div>
          {shown.length === 0 ? (
            <div className="card" style={{ color: "var(--muted)", textAlign: "center" }}>No vouchers here.</div>
          ) : (
            <div className="card expense-list">
              {shown.map((v) => {
                const status = STATUS[v.status] || STATUS.open;
                const funded = v.fundedBy === "company" ? `Company${v.fundName ? ` · ${v.fundName}` : ""}` : `${v.createdBy?.name || "Manager"} (self)`;
                const left = v.status === "claimed" ? Math.round((v.amount - v.claimedAmount) * 100) / 100 : 0;
                return (
                  <div key={v._id} className="expense-row" role="button" tabIndex={0} style={{ cursor: "pointer" }} onClick={() => setViewing(v)} onKeyDown={(e) => { if (e.key === "Enter") setViewing(v); }} title="View voucher details">
                    <span className="expense-row-main">
                      <span className="expense-row-title">{v.purpose}</span>
                      <span className="expense-row-meta">
                        To {v.recipientId?.name || "Staff"} · by {v.createdBy?.name || "Manager"} · {formatDate(v.createdAt)} · Paid by {funded}
                      </span>
                      {v.status === "claimed" && (
                        <span className="expense-row-meta">
                          Claimed {money(v.claimedAmount)} on {formatDate(v.claimedAt)}
                          {left > 0 ? ` · ${money(left)} left with them` : ""}
                          {v.owedToRecipient > 0 ? ` · company owes them ${money(v.owedToRecipient)}` : ""}
                        </span>
                      )}
                      {v.status === "cancelled" && v.cancelledBy && <span className="expense-row-meta">Cancelled by {v.cancelledBy.name} · {formatDate(v.cancelledAt)}</span>}
                      {v.closedBy && <span className="expense-row-meta">Closed by {v.closedBy.name} · {formatDate(v.closedAt)}</span>}
                    </span>
                    <span className="pill" style={{ fontSize: 11, background: status.bg, color: status.color }}>{status.label}</span>
                    <span className="expense-row-amount">{money(v.amount)}</span>
                    <span className="expense-row-action">
                      {v.status === "open" && (
                        <span style={{ display: "flex", gap: 6 }}>
                          {String(v.createdBy?._id || v.createdBy) === String(user.id) && (
                            <button className="btn btn-primary btn-sm" onClick={(e) => { e.stopPropagation(); setClosingVoucher(v); }}>Close</button>
                          )}
                          {String(v.createdBy?._id || v.createdBy) === String(user.id) && (
                            <button className="btn btn-outline-danger btn-sm" onClick={(e) => { e.stopPropagation(); setCancelling(v); }}>Cancel</button>
                          )}
                          {String(v.createdBy?._id || v.createdBy) === String(user.id) && (
                            <button className="btn btn-outline-danger btn-sm" onClick={(e) => { e.stopPropagation(); setDeleting(v); }}>Delete</button>
                          )}
                        </span>
                      )}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </>
      )}

      {creating && (
        <CreateVoucherModal companyId={companyId} user={user} members={members} funds={funds} onClose={() => setCreating(false)} onCreated={changed} />
      )}
      {viewing && (
        <VoucherDetailModal voucher={viewing} user={user} onClose={() => setViewing(null)} onCancel={(v) => { setViewing(null); setCancelling(v); }} onDelete={(v) => { setViewing(null); setDeleting(v); }} onCloseVoucher={(v) => { setViewing(null); setClosingVoucher(v); }} />
      )}
      {closingVoucher && (
        <ClaimVoucherModal
          mode="close"
          voucher={closingVoucher}
          company={company}
          user={user}
          held={Math.max(0, Number((data?.people || []).find((p) => String(p.userId) === String(closingVoucher.recipientId?._id || closingVoucher.recipientId))?.held || 0))}
          onClose={() => setClosingVoucher(null)}
          onClaimed={changed}
        />
      )}
      {deleting && (
        <ConfirmDialog
          title="Delete voucher?"
          message={`${money(deleting.amount)} for "${deleting.purpose}" goes back to ${deleting.fundedBy === "company" ? deleting.fundName || "the company fund" : `${deleting.createdBy?.name || "the manager"} (removed from what the company owes them)`}, and the voucher is removed from the lists. Use Cancel instead to keep it listed as cancelled.`}
          confirmLabel="Delete voucher"
          danger
          onConfirm={confirmDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
      {cancelling && (
        <ConfirmDialog
          title="Cancel voucher?"
          message={`${money(cancelling.amount)} for "${cancelling.purpose}" goes back to ${cancelling.fundedBy === "company" ? cancelling.fundName || "the company fund" : `${cancelling.createdBy?.name || "the manager"} (removed from what the company owes them)`}.`}
          confirmLabel="Cancel voucher"
          danger
          onConfirm={confirmCancel}
          onCancel={() => setCancelling(null)}
        />
      )}
    </>
  );
}
