import { useState } from "react";
import Modal from "./Modal.jsx";
import { payExpense } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { bankAccountLabel, fileToBase64, money, PAYMENT_MODES } from "../utils.js";

export default function PayModal({ expense, user, isAdmin, lockedPayAs, bankAccounts, cashBalance, cashAccountName = "InCash", onClose, onPaid }) {
  const { showToast } = useToast();
  const [payAs, setPayAs] = useState(lockedPayAs || (isAdmin ? "company" : "self"));
  const [paymentMode, setPaymentMode] = useState("");
  const [fundId, setFundId] = useState("");
  const [proof, setProof] = useState("");
  const [saving, setSaving] = useState(false);

  const amount = expense.amount ?? 0;
  const showToggle = isAdmin && !lockedPayAs;
  const needsFund = isAdmin && payAs === "company";

  async function handleFile(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setProof(await fileToBase64(file));
  }

  async function handleSubmit(e) {
    e.preventDefault();
    if (!proof) {
      showToast("Payment proof screenshot/photo is required", "error");
      return;
    }
    if (!paymentMode) {
      showToast("Select a payment mode (Cash, Card or UPI)", "error");
      return;
    }
    if (needsFund && !fundId) {
      showToast(
        bankAccounts.length === 0 ? "Add a company bank account first" : `Select the bank account or ${cashAccountName} used for this payment`,
        "error"
      );
      return;
    }
    setSaving(true);
    const res = await payExpense(expense._id, {
      userId: user.id,
      paymentMode,
      paymentProof: proof,
      payAs: isAdmin ? payAs : "self",
      fundId: needsFund ? fundId : undefined,
    });
    setSaving(false);
    if (res.success) {
      showToast(res.message || "Payment submitted successfully!");
      onPaid();
      onClose();
    } else {
      showToast(res.message || "Failed to submit payment", "error");
    }
  }

  return (
    <Modal onClose={onClose} maxWidth={440}>
      <h2 style={{ marginTop: 0, fontSize: 19 }}>Pay Expense (₹{amount.toFixed(2)})</h2>
      <form onSubmit={handleSubmit}>
        {showToggle && (
          <>
            <label className="field-label">Pay As *</label>
            <div style={{ display: "flex", gap: 8, background: "#F8FAFC", border: "1px solid var(--slate-border)", borderRadius: 10, padding: 4, marginBottom: 16 }}>
              <button
                type="button"
                onClick={() => setPayAs("company")}
                className="btn"
                style={{ flex: 1, background: payAs === "company" ? "var(--forest)" : "transparent", color: payAs === "company" ? "#fff" : "var(--dark-text)", padding: "9px 8px" }}
              >
                Company
              </button>
              <button
                type="button"
                onClick={() => setPayAs("self")}
                className="btn"
                style={{ flex: 1, background: payAs === "self" ? "var(--forest)" : "transparent", color: payAs === "self" ? "#fff" : "var(--dark-text)", padding: "9px 8px" }}
              >
                Self
              </button>
            </div>
          </>
        )}

        <label className="field-label">Payment Mode *</label>
        <select className="field-select" value={paymentMode} onChange={(e) => setPaymentMode(e.target.value)} style={{ marginBottom: 16 }}>
          <option value="">Select payment mode</option>
          {Object.entries(PAYMENT_MODES).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>

        {needsFund && (
          <>
            <label className="field-label">Pay From *</label>
            <select className="field-select" value={fundId} onChange={(e) => setFundId(e.target.value)} style={{ marginBottom: 16 }}>
              <option value="">Select bank account or {cashAccountName}</option>
              <option value="cash">{cashAccountName} ({money(cashBalance)})</option>
              {bankAccounts.map((b) => (
                <option key={b._id} value={b._id}>
                  {bankAccountLabel(b)} · {money(b.balance || 0)}
                </option>
              ))}
            </select>
          </>
        )}

        <label className="field-label">Payment Proof Screenshot *</label>
        <input type="file" accept="image/*" onChange={handleFile} style={{ marginBottom: 16 }} />
        {proof && <img src={proof} alt="Proof preview" style={{ maxWidth: "100%", borderRadius: 10, marginBottom: 16 }} />}

        <div style={{ display: "flex", gap: 10 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>
            Cancel
          </button>
          <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>
            {saving ? "Submitting..." : "Submit Payment"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
