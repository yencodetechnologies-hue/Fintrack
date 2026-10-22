import { useState } from "react";
import Modal from "./Modal.jsx";
import { requestAdvanceReturn } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { money } from "../utils.js";

// Staff hands unused voucher balance back; company Cash goes up once a manager confirms they got it.
export default function HandBackModal({ companyId, user, held, onClose, onDone }) {
  const { showToast } = useToast();
  const [amount, setAmount] = useState(String(held));
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);

  async function submit(event) {
    event.preventDefault();
    const value = parseFloat(amount);
    if (!(value > 0)) return showToast("Enter a valid amount", "error");
    if (value > held) return showToast(`You hold only ${money(held)}`, "error");
    setSaving(true);
    const res = await requestAdvanceReturn(companyId, user.id, value, note.trim());
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not send hand-back", "error");
    showToast(`Hand-back of ${money(value)} sent · a manager will confirm`);
    onDone?.();
    onClose();
  }

  return (
    <Modal onClose={onClose} maxWidth={420}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>Hand back balance</h2>
      <p style={{ margin: "0 0 14px", fontSize: 13, color: "var(--muted)" }}>
        You hold {money(held)} of voucher money. Give the cash to a manager; it goes back into company Cash when they confirm.
      </p>
      <form onSubmit={submit}>
        <label className="field-label">Amount (₹)</label>
        <input className="field-input" type="number" min="0.01" step="0.01" max={held} value={amount} onChange={(e) => setAmount(e.target.value)} required />
        <label className="field-label" style={{ display: "block", marginTop: 12 }}>Note (optional)</label>
        <input className="field-input" placeholder="e.g. Gave cash to Ravi" value={note} onChange={(e) => setNote(e.target.value)} maxLength={140} />
        <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>{saving ? "Sending…" : "Send hand-back"}</button>
        </div>
      </form>
    </Modal>
  );
}
