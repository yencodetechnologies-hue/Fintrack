import { useState } from "react";
import Modal from "./Modal.jsx";
import { editExpenseSettlement } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { fileToBase64, LEGACY_PAYMENT_MODES } from "../utils.js";

export default function EditSettlementModal({ expense, settlement, user, onClose, onSaved }) {
  const { showToast } = useToast();
  const initialMode = (settlement?.paymentMode || "cash").toLowerCase();
  const [paymentMode, setPaymentMode] = useState(LEGACY_PAYMENT_MODES[initialMode] ? initialMode : "cash");
  const [proof, setProof] = useState(settlement?.paymentProof || "");
  const [saving, setSaving] = useState(false);

  async function handleFile(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setProof(await fileToBase64(file));
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setSaving(true);
    const res = await editExpenseSettlement(expense._id, user.id, paymentMode, proof);
    setSaving(false);
    if (res.success) {
      showToast("Payment details updated successfully");
      onSaved();
      onClose();
    } else {
      showToast(res.message || "Failed to update payment details", "error");
    }
  }

  return (
    <Modal onClose={onClose} maxWidth={420}>
      <h2 style={{ marginTop: 0, fontSize: 20 }}>Edit Payment Details</h2>
      <form onSubmit={handleSubmit}>
        <label className="field-label">Payment Mode</label>
        <select className="field-select" value={paymentMode} onChange={(e) => setPaymentMode(e.target.value)} style={{ marginBottom: 14 }}>
          {Object.entries(LEGACY_PAYMENT_MODES).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>

        <label className="field-label">Payment Proof</label>
        <input type="file" accept="image/*" onChange={handleFile} style={{ marginBottom: 14 }} />
        {proof && <img src={proof} alt="Proof preview" style={{ maxWidth: "100%", borderRadius: 12, marginBottom: 14 }} />}

        <div style={{ display: "flex", gap: 10 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>
            {saving ? "Saving..." : "Save"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
