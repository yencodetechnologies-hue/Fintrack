import { useCallback, useEffect, useState } from "react";
import { getVouchers } from "../api.js";
import { formatDate, money } from "../utils.js";
import ClaimVoucherModal from "./ClaimVoucherModal.jsx";

// Staff Home: open vouchers (highlighted, each with Claim) and hand-backs waiting for a manager.
export default function StaffVouchers({ companyId, company, user, refreshKey, onChanged }) {
  const [data, setData] = useState({ vouchers: [], returns: [], myAdvance: 0 });
  const [claiming, setClaiming] = useState(null);

  const load = useCallback(async () => {
    const res = await getVouchers(companyId, user.id);
    if (res.success) setData({ vouchers: res.vouchers || [], returns: res.returns || [], myAdvance: Number(res.myAdvance || 0) });
  }, [companyId, user.id]);

  useEffect(() => {
    load();
  }, [load, refreshKey]);

  const open = data.vouchers.filter((v) => v.status === "open");
  const pendingReturns = data.returns.filter((r) => r.status === "pending" || r.status === "processing");
  if (!open.length && !pendingReturns.length) return null;

  return (
    <section style={{ marginBottom: 22 }}>
      <h2 style={{ margin: "0 0 12px", fontSize: 19 }}>Vouchers</h2>
      <div style={{ display: "grid", gap: 10 }}>
        {open.map((v) => (
          <div key={v._id} className="voucher-card highlight">
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
              <div style={{ minWidth: 0 }}>
                <div className="voucher-card-tag">New voucher</div>
                <div style={{ fontWeight: 700, fontSize: 15, color: "var(--dark-text)", wordBreak: "break-word" }}>{v.purpose}</div>
                <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 2 }}>
                  From {v.createdBy?.name || "Manager"} · {formatDate(v.createdAt)}
                </div>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <span style={{ fontFamily: "Fraunces, serif", fontSize: 22, fontWeight: 700, color: "var(--forest)" }}>{money(v.amount)}</span>
                <button className="btn btn-primary" onClick={() => setClaiming(v)}>Claim voucher</button>
              </div>
            </div>
          </div>
        ))}
        {pendingReturns.map((r) => (
          <div key={r._id} className="card" style={{ padding: "10px 14px", fontSize: 13, color: "var(--muted)" }}>
            Hand-back of <strong style={{ color: "var(--dark-text)" }}>{money(r.amount)}</strong> waiting for a manager to confirm · {formatDate(r.createdAt)}
          </div>
        ))}
      </div>

      {claiming && (
        <ClaimVoucherModal
          voucher={claiming}
          company={company}
          user={user}
          held={data.myAdvance}
          onClose={() => setClaiming(null)}
          onClaimed={() => {
            load();
            onChanged?.();
          }}
        />
      )}
    </section>
  );
}
