import { useCallback, useEffect, useState } from "react";
import { cancelVoucher, decideAdvanceReturn, deleteVoucher, editVoucher, getVouchers } from "../api.js";
import Modal from "./Modal.jsx";
import { useToast } from "../context/ToastContext.jsx";
import { formatDate, money, VOUCHER_STATUS as STATUS, roleNames } from "../utils.js";
import ConfirmDialog from "./ConfirmDialog.jsx";
import CreateVoucherModal from "./CreateVoucherModal.jsx";
import VoucherDetailModal from "./VoucherDetailModal.jsx";
import ClaimVoucherModal from "./ClaimVoucherModal.jsx";
import { TableCard, pageOf, tableMeta, usePageSize } from "./DataTable.jsx";



// Managers: every voucher, what each staff member holds, and hand-backs to confirm.
export default function VouchersPanel({ companyId, company, user, members, funds, onChanged, refreshKey, canEdit = false }) {
  const { showToast } = useToast();
  const [data, setData] = useState(null);
  const [filter, setFilter] = useState("all");
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = usePageSize();
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

  // the Admin editing a voucher: { v, purpose, amount, fundId, fundChanged, date }
  const [editing, setEditing] = useState(null);
  const [savingEdit, setSavingEdit] = useState(false);
  async function saveEdit() {
    const e = editing;
    const value = Number(e.amount);
    if (!e.purpose.trim()) return showToast("Enter what the voucher is for", "error");
    if (!(value > 0)) return showToast("Enter an amount greater than zero", "error");
    const changes = { purpose: e.purpose.trim(), date: e.date || undefined };
    if (value !== Number(e.v.amount)) changes.amount = value;
    if (e.v.fundedBy === "company" && e.fundChanged) changes.fundId = e.fundId;
    setSavingEdit(true);
    const res = await editVoucher(e.v._id, user.id, changes);
    setSavingEdit(false);
    if (!res.success) return showToast(res.message || "Could not save the voucher", "error");
    showToast("Voucher updated");
    setEditing(null);
    changed();
  }
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
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
        <h1 style={{ fontSize: 22, margin: 0 }}>Vouchers</h1>
        <button className="btn btn-primary" onClick={() => setCreating(true)}>+ Create voucher</button>
      </div>
      <p style={{ color: "var(--muted)", margin: "0 0 18px" }}>Review and manage staff vouchers and confirm returned balances.</p>

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
            <TableCard title="Hand-backs to confirm" meta={`${pendingReturns.length} waiting`} items={pendingReturns}>
              {(rows) => (
                <>
              <table className="dt">
                <thead>
                  <tr><th>Date</th><th>{roleNames(company).staff}</th><th>Note</th><th className="num">Amount</th><th className="num">Action</th></tr>
                </thead>
                <tbody>
                  {rows.map((r) => {
                    const own = String(r.userId?._id || r.userId) === String(user.id);
                    return (
                      <tr key={r._id}>
                        <td className="nowrap">{formatDate(r.createdAt)}</td>
                        <td className="dt-strong">{r.userId?.name || "Staff"}</td>
                        <td className="muted">{r.note || "—"}</td>
                        <td className="num">{money(r.amount)}</td>
                        <td>
                          <span className="dt-actions">
                            {own ? (
                              <span className="dt-sub">Another manager confirms</span>
                            ) : (
                              <>
                                <button className="btn btn-primary btn-sm" disabled={busy === r._id} onClick={() => decide(r, true)}>Received</button>
                                <button className="btn btn-outline btn-sm" disabled={busy === r._id} onClick={() => decide(r, false)}>Decline</button>
                              </>
                            )}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            
                </>
              )}
            </TableCard>
          )}

          <TableCard title={`By ${roleNames(company).staff.toLowerCase()} member`} meta={`${people.length} ${people.length === 1 ? "person" : "people"}`} items={people}>
            {(rows) => (
              <>
            {people.length === 0 ? (
              <div className="dt-empty">No vouchers given yet.</div>
            ) : (
              <table className="dt">
                <thead>
                  <tr><th>Name</th><th className="num">Given</th><th className="num">Claimed</th><th className="num">Open</th><th className="num">Holding</th></tr>
                </thead>
                <tbody>
                  {rows.map((p) => (
                    <tr key={p.userId}>
                      <td className="dt-strong">{p.name}</td>
                      <td className="num">{money(p.given)}</td>
                      <td className="num">{money(p.claimed)}</td>
                      <td className="num">{money(p.open)}</td>
                      <td className={`num ${p.held > 0 ? "out" : ""}`}>{money(Math.max(0, p.held))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          
              </>
            )}
          </TableCard>

          {(() => {
            const paged = pageOf(shown, page, pageSize);
            return (
              <TableCard
                title="All vouchers"
                meta={tableMeta(shown.length, paged.page, paged.pages, "vouchers")}
                page={paged.page}
                pages={paged.pages}
                onPage={setPage}
                count={shown.length}
                pageSize={pageSize}
                onPageSize={(n) => { setPageSize(n); setPage(1); }}
                actions={
                  <select className="field-select" style={{ width: "auto", height: 34 }} value={filter} onChange={(e) => { setFilter(e.target.value); setPage(1); }}>
                    <option value="all">All</option>
                    <option value="open">Open</option>
                    <option value="claimed">Claimed</option>
                    <option value="cancelled">Cancelled</option>
                  </select>
                }
              >
                {shown.length === 0 ? (
                  <div className="dt-empty">No vouchers here.</div>
                ) : (
                  <table className="dt">
                    <thead>
                      <tr><th>Date</th><th>Purpose</th><th>Given to</th><th>Given by</th><th>Paid from</th><th>Status</th><th className="num">Amount</th><th className="num">Action</th></tr>
                    </thead>
                    <tbody>
                      {paged.rows.map((v) => {
                        const status = STATUS[v.status] || STATUS.open;
                        const funded = v.fundedBy === "company" ? `Company${v.fundName ? ` · ${v.fundName}` : ""}` : `${v.createdBy?.name || "Manager"} (self)`;
                        const left = v.status === "claimed" ? Math.round((v.amount - v.claimedAmount) * 100) / 100 : 0;
                        const mine = String(v.createdBy?._id || v.createdBy) === String(user.id);
                        return (
                          <tr key={v._id} className="dt-click" tabIndex={0} onClick={() => setViewing(v)} onKeyDown={(e) => { if (e.key === "Enter") setViewing(v); }} title="View voucher details">
                            <td className="nowrap">{formatDate(v.createdAt)}</td>
                            <td className="dt-wrap-text">
                              <span className="dt-strong">{v.purpose}</span>
                              {v.status === "claimed" && (
                                <span className="dt-sub">
                                  Claimed {money(v.claimedAmount)}
                                  {left > 0 ? ` · ${money(left)} left with them` : ""}
                                  {v.owedToRecipient > 0 ? ` · company owes them ${money(v.owedToRecipient)}` : ""}
                                </span>
                              )}
                              {v.status === "cancelled" && v.cancelledBy && <span className="dt-sub">Cancelled by {v.cancelledBy.name}</span>}
                              {v.closedBy && <span className="dt-sub">Closed by {v.closedBy.name}</span>}
                            </td>
                            <td>{v.recipientId?.name || "Staff"}</td>
                            <td>{v.createdBy?.name || "Manager"}</td>
                            <td>{funded}</td>
                            <td><span className="pill" style={{ fontSize: 11, background: status.bg, color: status.color }}>{status.label}</span></td>
                            <td className="num">{money(v.amount)}</td>
                            <td onClick={(e) => e.stopPropagation()}>
                              <span className="dt-actions">
                                {canEdit && (
                                  <button
                                    className="btn btn-outline btn-sm"
                                    onClick={() => setEditing({ v, purpose: v.purpose, amount: String(v.amount), fundId: v.fundId || "cash", fundChanged: false, date: istInput(v.createdAt) })}
                                  >
                                    Edit
                                  </button>
                                )}
                                {v.status === "open" && mine && (
                                  <>
                                    <button className="btn btn-primary btn-sm" onClick={() => setClosingVoucher(v)}>Close</button>
                                    <button className="btn btn-outline-danger btn-sm" onClick={() => setCancelling(v)}>Cancel</button>
                                    <button className="btn btn-outline-danger btn-sm" onClick={() => setDeleting(v)}>Delete</button>
                                  </>
                                )}
                              </span>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                )}
              </TableCard>
            );
          })()}
        </>
      )}

      {editing && (
        <Modal onClose={() => setEditing(null)} maxWidth={460}>
          <h2 style={{ margin: "0 0 4px", fontSize: 20 }}>Edit voucher</h2>
          <p style={{ color: "var(--muted)", fontSize: 13, margin: "0 0 14px" }}>
            To {editing.v.recipientId?.name || "staff"} · {(STATUS[editing.v.status] || STATUS.open).label}
          </p>
          <div style={{ display: "grid", gap: 10 }}>
            <div>
              <label className="field-label">For</label>
              <input className="field-input" value={editing.purpose} onChange={(e) => setEditing({ ...editing, purpose: e.target.value })} />
            </div>
            {editing.v.status !== "cancelled" && (
              <div>
                <label className="field-label">Amount given (₹)</label>
                <input className="field-input" type="number" min="0.01" step="0.01" value={editing.amount} onChange={(e) => setEditing({ ...editing, amount: e.target.value })} />
              </div>
            )}
            {editing.v.status !== "cancelled" && editing.v.fundedBy === "company" && (
              <div>
                <label className="field-label">Paid from</label>
                <select className="field-select" value={editing.fundId} onChange={(e) => setEditing({ ...editing, fundId: e.target.value, fundChanged: true })}>
                  {!funds.some((f) => String(f.fundId) === String(editing.fundId)) && <option value={editing.fundId}>{editing.v.fundName || "Current account"}</option>}
                  {funds.map((f) => <option key={f.fundId} value={f.fundId}>{f.name} · {money(f.balance)}</option>)}
                </select>
              </div>
            )}
            <div>
              <label className="field-label">Date & time given</label>
              <input className="field-input" type="datetime-local" value={editing.date} onChange={(e) => setEditing({ ...editing, date: e.target.value })} />
            </div>
            <p style={{ color: "var(--muted)", fontSize: 12, margin: 0 }}>
              {editing.v.status === "claimed"
                ? `Already claimed (${money(editing.v.claimedAmount)}): a new amount changes what ${editing.v.recipientId?.name || "they"} still hold.`
                : "A new amount or account moves the balances by the difference."}
            </p>
            <div style={{ display: "flex", gap: 10, marginTop: 4 }}>
              <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setEditing(null)} disabled={savingEdit}>Cancel</button>
              <button type="button" className="btn btn-primary" style={{ flex: 1 }} onClick={saveEdit} disabled={savingEdit}>{savingEdit ? "Saving…" : "Save"}</button>
            </div>
          </div>
        </Modal>
      )}
      {creating && (
        <CreateVoucherModal companyId={companyId} company={company} user={user} members={members} funds={funds} onClose={() => setCreating(false)} onCreated={changed} />
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

// a date as "YYYY-MM-DDTHH:mm" in India time, for the date & time input
function istInput(at) {
  return new Date(new Date(at).getTime() + 330 * 60000).toISOString().slice(0, 16);
}
