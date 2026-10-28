import { useCallback, useEffect, useState } from "react";
import { cancelVoucher, decideAdvanceReturn, deleteVoucher, getVouchers } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { formatDate, money, VOUCHER_STATUS as STATUS } from "../utils.js";
import ConfirmDialog from "./ConfirmDialog.jsx";
import CreateVoucherModal from "./CreateVoucherModal.jsx";
import VoucherDetailModal from "./VoucherDetailModal.jsx";
import ClaimVoucherModal from "./ClaimVoucherModal.jsx";
import { TableCard, pageOf, tableMeta } from "./DataTable.jsx";



// Managers: every voucher, what each staff member holds, and hand-backs to confirm.
export default function VouchersPanel({ companyId, company, user, members, funds, onChanged, refreshKey }) {
  const { showToast } = useToast();
  const [data, setData] = useState(null);
  const [filter, setFilter] = useState("all");
  const [page, setPage] = useState(1);
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
        <h1 style={{ fontSize: 22, margin: 0 }}>Vouchers</h1>
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
            <TableCard title="Hand-backs to confirm" meta={`${pendingReturns.length} waiting`}>
              <table className="dt">
                <thead>
                  <tr><th>Date</th><th>Staff</th><th>Note</th><th className="num">Amount</th><th className="num">Action</th></tr>
                </thead>
                <tbody>
                  {pendingReturns.map((r) => {
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
            </TableCard>
          )}

          <TableCard title="By staff member" meta={`${people.length} ${people.length === 1 ? "person" : "people"}`}>
            {people.length === 0 ? (
              <div className="dt-empty">No vouchers given yet.</div>
            ) : (
              <table className="dt">
                <thead>
                  <tr><th>Name</th><th className="num">Given</th><th className="num">Claimed</th><th className="num">Open</th><th className="num">Holding</th></tr>
                </thead>
                <tbody>
                  {people.map((p) => (
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
          </TableCard>

          {(() => {
            const paged = pageOf(shown, page, 25);
            return (
              <TableCard
                title="All vouchers"
                meta={tableMeta(shown.length, paged.page, paged.pages, "vouchers")}
                page={paged.page}
                pages={paged.pages}
                onPage={setPage}
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
                                  Claimed {money(v.claimedAmount)} on {formatDate(v.claimedAt)}
                                  {left > 0 ? ` · ${money(left)} left with them` : ""}
                                  {v.owedToRecipient > 0 ? ` · company owes them ${money(v.owedToRecipient)}` : ""}
                                </span>
                              )}
                              {v.status === "cancelled" && v.cancelledBy && <span className="dt-sub">Cancelled by {v.cancelledBy.name} · {formatDate(v.cancelledAt)}</span>}
                              {v.closedBy && <span className="dt-sub">Closed by {v.closedBy.name} · {formatDate(v.closedAt)}</span>}
                            </td>
                            <td>{v.recipientId?.name || "Staff"}</td>
                            <td>{v.createdBy?.name || "Manager"}</td>
                            <td>{funded}</td>
                            <td><span className="pill" style={{ fontSize: 11, background: status.bg, color: status.color }}>{status.label}</span></td>
                            <td className="num">{money(v.amount)}</td>
                            <td onClick={(e) => e.stopPropagation()}>
                              {v.status === "open" && mine && (
                                <span className="dt-actions">
                                  <button className="btn btn-primary btn-sm" onClick={() => setClosingVoucher(v)}>Close</button>
                                  <button className="btn btn-outline-danger btn-sm" onClick={() => setCancelling(v)}>Cancel</button>
                                  <button className="btn btn-outline-danger btn-sm" onClick={() => setDeleting(v)}>Delete</button>
                                </span>
                              )}
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
