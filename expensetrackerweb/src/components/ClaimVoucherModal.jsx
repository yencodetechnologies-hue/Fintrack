import { useState } from "react";
import Modal from "./Modal.jsx";
import { claimVoucher } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { companyCategories, fileToBase64, formatDate, money } from "../utils.js";

const rowStyle = { display: "flex", justifyContent: "space-between", gap: 12, padding: "8px 0", fontSize: 13 };

// The voucher's recipient records what they actually spent; the money was already given, so nobody pays it again.
export default function ClaimVoucherModal({ voucher, company, user, held = 0, onClose, onClaimed }) {
  const { showToast } = useToast();
  const [amount, setAmount] = useState(String(voucher.amount));
  const [category, setCategory] = useState("General");
  const [attachment, setAttachment] = useState("");
  const [saving, setSaving] = useState(false);

  const value = parseFloat(amount);
  const extra = value > voucher.amount ? Math.round((value - voucher.amount) * 100) / 100 : 0;
  const fromHeld = Math.min(extra, Math.max(0, held));
  const owed = Math.round((extra - fromHeld) * 100) / 100;
  const left = value > 0 && value < voucher.amount ? Math.round((voucher.amount - value) * 100) / 100 : 0;

  async function pickReceipt(file) {
    if (!file) return;
    if (!file.type.startsWith("image/")) return showToast("Receipt must be an image", "error");
    setAttachment(await fileToBase64(file));
  }

  async function submit(event) {
    event.preventDefault();
    if (!(value > 0)) return showToast("Enter the amount you spent", "error");
    setSaving(true);
    const res = await claimVoucher(voucher._id, { userId: user.id, amount: value, category, attachment: attachment || undefined });
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not claim voucher", "error");
    showToast(left > 0 ? `Claimed ${money(value)} · ${money(left)} stays with you` : `Claimed ${money(value)}`);
    onClaimed?.(res);
    onClose();
  }

  const funded = voucher.fundedBy === "company"
    ? `${company?.name || "Company"}${voucher.fundName ? ` · ${voucher.fundName}` : ""}`
    : `${voucher.createdBy?.name || "Manager"} (personally)`;

  return (
    <Modal onClose={onClose} maxWidth={460}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>Claim voucher</h2>
      <p style={{ margin: "0 0 12px", fontSize: 13, color: "var(--muted)" }}>Enter what you actually spent. The money was already given to you.</p>

      <div className="voucher-card" style={{ marginBottom: 14 }}>
        <div style={{ ...rowStyle, paddingTop: 0 }}><span style={{ color: "var(--muted)" }}>Purpose</span><strong style={{ textAlign: "right" }}>{voucher.purpose}</strong></div>
        <div style={rowStyle}><span style={{ color: "var(--muted)" }}>Voucher amount</span><strong>{money(voucher.amount)}</strong></div>
        <div style={rowStyle}><span style={{ color: "var(--muted)" }}>Given by</span><span>{voucher.createdBy?.name || "Manager"}</span></div>
        <div style={rowStyle}><span style={{ color: "var(--muted)" }}>Paid by</span><span style={{ textAlign: "right" }}>{funded}</span></div>
        <div style={{ ...rowStyle, paddingBottom: 0 }}><span style={{ color: "var(--muted)" }}>Given on</span><span>{formatDate(voucher.createdAt)}</span></div>
      </div>

      <form onSubmit={submit}>
        <label className="field-label">Amount spent (₹)</label>
        <input className="field-input" type="number" min="0.01" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} required />
        {value > 0 && (
          <div style={{ marginTop: 6, fontSize: 12.5, fontWeight: 600, color: owed > 0 ? "var(--terracotta)" : "var(--forest)" }}>
            {left > 0 && `${money(left)} stays with you as your voucher balance.`}
            {extra > 0 && fromHeld > 0 && `${money(fromHeld)} comes from your voucher balance. `}
            {owed > 0 && `The company will owe you ${money(owed)}.`}
            {value === voucher.amount && "Uses the full voucher."}
          </div>
        )}

        <label className="field-label" style={{ display: "block", marginTop: 12 }}>Category (optional)</label>
        <select className="field-select" value={category} onChange={(e) => setCategory(e.target.value)}>
          {companyCategories(company).map((c) => <option key={c} value={c}>{c}</option>)}
        </select>

        <label className="field-label" style={{ display: "block", marginTop: 12 }}>Receipt (optional)</label>
        <input type="file" accept="image/*" onChange={(e) => { pickReceipt(e.target.files?.[0]); e.target.value = ""; }} style={{ fontSize: 13 }} />
        {attachment && (
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 8 }}>
            <img src={attachment} alt="Receipt" style={{ width: 56, height: 56, objectFit: "cover", borderRadius: 8, border: "1px solid var(--slate-border)" }} />
            <button type="button" className="btn btn-outline btn-sm" onClick={() => setAttachment("")}>Remove</button>
          </div>
        )}

        <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>{saving ? "Claiming…" : "Proceed to claim"}</button>
        </div>
      </form>
    </Modal>
  );
}
