import { useState } from "react";
import Modal from "./Modal.jsx";
import { useFundTopUp } from "./FundTopUp.jsx";
import { createVoucher } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { money } from "../utils.js";

// Manager gives a staff member money up front, paid by the company (from a fund now) or by the manager.
export default function CreateVoucherModal({ companyId, user, members, funds, onClose, onCreated }) {
  const { showToast } = useToast();
  const staff = members.filter((m) => m.role !== "admin" && String(m.userId) !== String(user.id));
  const [recipientId, setRecipientId] = useState(staff.length === 1 ? String(staff[0].userId) : "");
  const [amount, setAmount] = useState("");
  const [purpose, setPurpose] = useState("");
  const [fundedBy, setFundedBy] = useState("company");
  const [fundId, setFundId] = useState(funds[0]?.fundId || "cash");
  const [saving, setSaving] = useState(false);

  const value = parseFloat(amount);
  const fund = funds.find((f) => f.fundId === fundId);
  const short = fundedBy === "company" && value > 0 && fund && Number(fund.balance) < value;

  const topUp = useFundTopUp({ companyId, user, funds });

  function submit(event) {
    event.preventDefault();
    if (!recipientId) return showToast("Choose who gets the voucher", "error");
    if (!(value > 0)) return showToast("Enter a valid amount", "error");
    if (!purpose.trim()) return showToast("Enter what the voucher is for", "error");
    if (short) return topUp.ask(fund, value, save);
    save();
  }

  async function save() {
    setSaving(true);
    const res = await createVoucher(companyId, { userId: user.id, recipientId, amount: value, purpose: purpose.trim(), fundedBy, fundId: fundedBy === "company" ? fundId : undefined });
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not create voucher", "error");
    const name = staff.find((m) => String(m.userId) === recipientId)?.name || "staff member";
    showToast(`Voucher of ${money(value)} given to ${name}`);
    onCreated?.(res.voucher);
    onClose();
  }

  const choice = (key, title, sub) => (
    <button
      type="button"
      onClick={() => setFundedBy(key)}
      style={{
        flex: 1,
        textAlign: "left",
        padding: "10px 12px",
        borderRadius: 10,
        cursor: "pointer",
        border: `1.5px solid ${fundedBy === key ? "var(--forest)" : "var(--slate-border)"}`,
        background: fundedBy === key ? "rgba(25, 87, 84, 0.06)" : "#fff",
      }}
    >
      <div style={{ fontWeight: 700, fontSize: 13.5, color: "var(--dark-text)" }}>{title}</div>
      <div style={{ fontSize: 11.5, color: "var(--muted)", marginTop: 2 }}>{sub}</div>
    </button>
  );

  return (
    <Modal onClose={onClose} maxWidth={460}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>Create voucher</h2>
      <p style={{ margin: "0 0 16px", fontSize: 13, color: "var(--muted)" }}>Give a staff member money up front. They claim what they actually spent.</p>
      {staff.length === 0 ? (
        <div className="card" style={{ color: "var(--muted)", fontSize: 13 }}>This company has no staff members yet. Vouchers can be given to staff only.</div>
      ) : (
        <form onSubmit={submit}>
          <label className="field-label">For whom</label>
          <select className="field-select" value={recipientId} onChange={(e) => setRecipientId(e.target.value)} required>
            <option value="">Choose staff member</option>
            {staff.map((m) => <option key={m.userId} value={m.userId}>{m.name}</option>)}
          </select>

          <label className="field-label" style={{ display: "block", marginTop: 12 }}>Amount (₹)</label>
          <input className="field-input" type="number" min="0.01" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} required />

          <label className="field-label" style={{ display: "block", marginTop: 12 }}>Purpose</label>
          <input className="field-input" placeholder="e.g. Site visit travel" value={purpose} onChange={(e) => setPurpose(e.target.value)} maxLength={140} required />

          <label className="field-label" style={{ display: "block", marginTop: 12 }}>Paid by</label>
          <div style={{ display: "flex", gap: 8 }}>
            {choice("company", "Company", "Taken from Cash or Bank now")}
            {choice("manager", "Me (Self)", "The company will owe you this")}
          </div>

          {fundedBy === "company" && (
            <>
              <label className="field-label" style={{ display: "block", marginTop: 12 }}>From fund</label>
              <select className="field-select" value={fundId} onChange={(e) => setFundId(e.target.value)}>
                {funds.map((f) => <option key={f.fundId} value={f.fundId}>{f.name} · {money(f.balance)}</option>)}
              </select>
              {short && <div style={{ marginTop: 6, fontSize: 12, color: "var(--terracotta)", fontWeight: 600 }}>Only {money(fund.balance)} available in {fund.name}. You can add money when you pay.</div>}
            </>
          )}

          <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
            <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
            <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>{saving ? "Saving…" : "Give voucher"}</button>
          </div>
        </form>
      )}
      {topUp.ui}
    </Modal>
  );
}
