import { useState } from "react";
import Modal from "./Modal.jsx";
import { changeLedgerPayerType, updateExpense, updateLedgerExpense, updateLedgerExpenseReceipts } from "../api.js";
import { fileToBase64, money } from "../utils.js";
import { useToast } from "../context/ToastContext.jsx";
import { companyCategories } from "../utils.js";

// Who paid, as the creating manager can switch it: "manager" (me), "company", or "unpaid" (approved, nothing booked yet — shown as "me").
function currentPayer(expense, userId) {
  if (expense.lifecycle === "paid_by_company" && expense.payerType === "company") return "company";
  const paidBy = expense.paidByAdminId?._id || expense.paidByAdminId;
  if (expense.lifecycle === "paid_by_admin" && String(paidBy) === String(userId)) return "manager";
  if (expense.lifecycle === "approved") return "unpaid";
  return null;
}

export default function EditExpenseModal({ expense, user, isAdmin = false, funds = [], customCategories, hiddenCategories = [], onClose, onUpdated }) {
  const { showToast } = useToast();
  const [amount, setAmount] = useState(String(expense.amount ?? ""));
  const [description, setDescription] = useState(expense.description || "");
  const [category, setCategory] = useState(expense.category || "General");
  const [date, setDate] = useState(() => new Date(expense.date || expense.createdAt).toISOString().slice(0, 10));
  const [saving, setSaving] = useState(false);
  const [newReceipt, setNewReceipt] = useState("");

  const isCreator = String(expense.createdBy?._id || expense.createdBy) === String(user.id);
  const startPayer = expense.lifecycle ? currentPayer(expense, user.id) : null;
  // only the manager who created it may switch who paid, at any status
  const canSwitchPayer = isAdmin && isCreator && startPayer !== null;
  // an approved expense the manager posted for themselves is already "paid by me" (it counts as owed to them)
  const shownPayer = startPayer === "unpaid" ? "manager" : startPayer;
  const [payer, setPayer] = useState(shownPayer);
  const [fundId, setFundId] = useState(funds[0]?.fundId || "cash");
  // once paid, amount and details are locked; only who-paid and the receipt can change
  const detailsLocked = Boolean(expense.lifecycle?.startsWith("paid") || expense.status === "paid");
  const payerChanged = canSwitchPayer && payer !== shownPayer;
  const selectedFund = funds.find((f) => String(f.fundId) === String(fundId));
  const fundTooLow = payer === "company" && payerChanged && selectedFund && Number(selectedFund.balance || 0) < Number(expense.amount || 0);

  async function handleReceipt(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      showToast("Choose an image file", "error");
      e.target.value = "";
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      showToast("Receipt must be 5 MB or smaller", "error");
      e.target.value = "";
      return;
    }
    setNewReceipt(await fileToBase64(file));
  }

  // company's current categories; the expense keeps its own even if that category was later removed
  const categoryOptions = Array.from(new Set([...companyCategories({ customCategories, hiddenCategories }), expense.category].filter(Boolean)));

  async function handleSubmit(e) {
    e.preventDefault();
    const amt = parseFloat(amount);
    if (!detailsLocked && (!(amt > 0) || !description.trim())) {
      showToast("Enter a valid amount and description", "error");
      return;
    }
    if (fundTooLow) {
      showToast(`Insufficient balance in ${selectedFund.name} (${money(selectedFund.balance)} available)`, "error");
      return;
    }
    setSaving(true);

    if (!detailsLocked) {
      // ledger expenses carry a lifecycle; older settlement-based ones don't
      const save = expense.lifecycle ? updateLedgerExpense : updateExpense;
      const res = await save(expense._id, {
        userId: user.id,
        amount: amt,
        description: description.trim(),
        category,
        date: new Date(date).toISOString(),
      });
      if (!res.success) {
        setSaving(false);
        showToast(res.message || "Failed to update expense", "error");
        return;
      }
    }

    const problems = [];
    if (payerChanged) {
      const res = await changeLedgerPayerType(expense._id, user.id, payer, payer === "company" ? fundId : undefined);
      if (!res.success) problems.push(`who paid: ${res.message || "failed"}`);
    }
    if (newReceipt && expense.lifecycle) {
      const res = await updateLedgerExpenseReceipts(expense._id, user.id, { attachment: newReceipt });
      if (!res.success) problems.push(`receipt: ${res.message || "upload failed"}`);
    }
    setSaving(false);
    onUpdated();
    if (problems.length) {
      showToast(`Saved, except ${problems.join("; ")}`, "error");
      return;
    }
    showToast(payerChanged ? `Now posted as ${payer === "company" ? "the company" : "you (manager)"}` : "Expense updated successfully");
    onClose();
  }

  const segment = (value, label) => (
    <button
      type="button"
      onClick={() => setPayer(value)}
      className={`btn ${payer === value ? "btn-dark" : "btn-outline"}`}
      style={{ flex: 1, padding: "8px 10px", fontSize: 13 }}
    >
      {label}
    </button>
  );

  return (
    <Modal onClose={onClose} maxWidth={440}>
      <h2 style={{ marginTop: 0, fontSize: 20 }}>Edit Expense</h2>
      <form onSubmit={handleSubmit}>
        {detailsLocked && (
          <p style={{ margin: "0 0 14px", padding: "8px 10px", background: "var(--slate-bg)", borderRadius: 8, fontSize: 12.5, color: "var(--muted)" }}>
            This expense is paid, so its details are locked.{canSwitchPayer ? " You can still change whether it is posted as you or the company, and the receipt." : " You can still change the receipt."}
          </p>
        )}

        {canSwitchPayer && (
          <div style={{ marginBottom: 14 }}>
            <label className="field-label">Post expense as</label>
            <div style={{ display: "flex", gap: 8 }}>
              {segment("manager", "Manager (Self)")}
              {segment("company", "Company")}
            </div>
            {payer === "company" && payerChanged && (
              <>
                <select className="field-select" value={fundId} onChange={(e) => setFundId(e.target.value)} style={{ marginTop: 8 }}>
                  {funds.map((f) => (
                    <option key={f.fundId} value={f.fundId}>
                      {f.name} · {money(f.balance)}{Number(f.balance || 0) < Number(expense.amount || 0) ? " ⚠️ (Insufficient)" : ""}
                    </option>
                  ))}
                </select>
                <small style={{ display: "block", marginTop: 6, color: fundTooLow ? "var(--terracotta)" : "var(--muted)" }}>
                  {fundTooLow ? "Not enough balance in this fund." : `${money(expense.amount)} will be taken from this fund.`}
                </small>
              </>
            )}
            {payer === "manager" && payerChanged && (
              <small style={{ display: "block", marginTop: 6, color: "var(--muted)" }}>
                The company will owe you {money(expense.amount)}{startPayer === "company" ? " and the fund gets the money back" : ""}.
              </small>
            )}
          </div>
        )}


        <label className="field-label">Amount (₹)</label>
        <input className="field-input" type="number" step="0.01" value={amount} disabled={detailsLocked} onChange={(e) => setAmount(e.target.value)} style={{ marginBottom: 14 }} />

        <label className="field-label">Description</label>
        <input className="field-input" value={description} disabled={detailsLocked} onChange={(e) => setDescription(e.target.value)} style={{ marginBottom: 14 }} />

        <label className="field-label">Category</label>
        <select className="field-select" value={category} disabled={detailsLocked} onChange={(e) => setCategory(e.target.value)} style={{ marginBottom: 14 }}>
          {categoryOptions.map((c) => (
            <option key={c} value={c}>{c}</option>
          ))}
        </select>

        <label className="field-label">Date</label>
        <input className="field-input" type="date" value={date} disabled={detailsLocked} onChange={(e) => setDate(e.target.value)} style={{ marginBottom: 14 }} />

        {expense.lifecycle && (
          <>
            <label className="field-label">{expense.hasAttachment ? "Replace bill receipt (optional)" : "Add bill receipt (optional)"}</label>
            <input className="field-input" type="file" accept="image/*" onChange={handleReceipt} style={{ marginBottom: newReceipt ? 8 : 18, padding: 8 }} />
            {newReceipt && (
              <img src={newReceipt} alt="New receipt" style={{ display: "block", maxHeight: 120, maxWidth: "100%", objectFit: "contain", borderRadius: 8, border: "1px solid var(--slate-border)", marginBottom: 18 }} />
            )}
          </>
        )}

        <div style={{ display: "flex", gap: 10 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={saving || fundTooLow}>
            {saving ? "Saving..." : "Save"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
