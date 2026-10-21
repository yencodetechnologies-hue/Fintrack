import { useState } from "react";
import Modal from "./Modal.jsx";
import { updateExpense, updateLedgerExpense } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { BASE_CATEGORIES } from "../utils.js";

export default function EditExpenseModal({ expense, user, customCategories, onClose, onUpdated }) {
  const { showToast } = useToast();
  const [amount, setAmount] = useState(String(expense.amount ?? ""));
  const [description, setDescription] = useState(expense.description || "");
  const [category, setCategory] = useState(expense.category || "General");
  const [date, setDate] = useState(() => new Date(expense.date || expense.createdAt).toISOString().slice(0, 10));
  const [saving, setSaving] = useState(false);

  const categoryOptions = Array.from(new Set([...BASE_CATEGORIES, ...customCategories, expense.category].filter(Boolean)));

  async function handleSubmit(e) {
    e.preventDefault();
    const amt = parseFloat(amount);
    if (!(amt > 0) || !description.trim()) {
      showToast("Enter a valid amount and description", "error");
      return;
    }
    setSaving(true);
    // ledger expenses carry a lifecycle; older settlement-based ones don't
    const save = expense.lifecycle ? updateLedgerExpense : updateExpense;
    const res = await save(expense._id, {
      userId: user.id,
      amount: amt,
      description: description.trim(),
      category,
      date: new Date(date).toISOString(),
    });
    setSaving(false);
    if (res.success) {
      showToast("Expense updated successfully");
      onUpdated();
      onClose();
    } else {
      showToast(res.message || "Failed to update expense", "error");
    }
  }

  return (
    <Modal onClose={onClose} maxWidth={420}>
      <h2 style={{ marginTop: 0, fontSize: 20 }}>Edit Expense</h2>
      <form onSubmit={handleSubmit}>
        <label className="field-label">Amount (₹)</label>
        <input className="field-input" type="number" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} style={{ marginBottom: 14 }} />

        <label className="field-label">Description</label>
        <input className="field-input" value={description} onChange={(e) => setDescription(e.target.value)} style={{ marginBottom: 14 }} />

        <label className="field-label">Category</label>
        <select className="field-select" value={category} onChange={(e) => setCategory(e.target.value)} style={{ marginBottom: 14 }}>
          {categoryOptions.map((c) => (
            <option key={c} value={c}>{c}</option>
          ))}
        </select>

        <label className="field-label">Date</label>
        <input className="field-input" type="date" value={date} onChange={(e) => setDate(e.target.value)} style={{ marginBottom: 18 }} />

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
