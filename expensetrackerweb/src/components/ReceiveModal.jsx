import { useState } from "react";
import Modal from "./Modal.jsx";
import { receiveExpense } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { LEGACY_PAYMENT_MODES } from "../utils.js";

export default function ReceiveModal({ expense, user, members, onClose, onReceived }) {
  const { showToast } = useToast();
  const otherMembers = members.filter((m) => m.userId !== user.id);
  const [payerUserId, setPayerUserId] = useState(otherMembers[0]?.userId || "");
  const [paymentMode, setPaymentMode] = useState("cash");
  const [saving, setSaving] = useState(false);

  async function handleSubmit(e) {
    e.preventDefault();
    if (!payerUserId) {
      showToast("Please select who paid you", "error");
      return;
    }
    setSaving(true);
    const res = await receiveExpense(expense._id, { userId: user.id, payerUserId, paymentMode });
    setSaving(false);
    if (res.success) {
      showToast(res.message || "Payment marked as received");
      onReceived();
      onClose();
    } else {
      showToast(res.message || "Failed to record payment", "error");
    }
  }

  return (
    <Modal onClose={onClose} maxWidth={400}>
      <h2 style={{ marginTop: 0, fontSize: 19 }}>Mark Payment Received</h2>
      <form onSubmit={handleSubmit}>
        <label className="field-label">Who paid you? *</label>
        <select className="field-select" value={payerUserId} onChange={(e) => setPayerUserId(e.target.value)} style={{ marginBottom: 16 }}>
          <option value="">Select member</option>
          {otherMembers.map((m) => (
            <option key={m.userId} value={m.userId}>{m.name}</option>
          ))}
        </select>

        <label className="field-label">Payment Mode *</label>
        <select className="field-select" value={paymentMode} onChange={(e) => setPaymentMode(e.target.value)} style={{ marginBottom: 20 }}>
          {Object.entries(LEGACY_PAYMENT_MODES).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>

        <div style={{ display: "flex", gap: 10 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>
            Cancel
          </button>
          <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>
            {saving ? "Saving..." : "Confirm"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
