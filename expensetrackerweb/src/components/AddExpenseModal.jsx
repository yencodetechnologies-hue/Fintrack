import { useState } from "react";
import Modal from "./Modal.jsx";
import { addCustomCategory, createExpense } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { fileToBase64, BASE_CATEGORIES, money } from "../utils.js";

export default function AddExpenseModal({
  company,
  user,
  isAdmin,
  lockedLogAs, // "company" | "self" | null
  members,
  bankAccounts,
  cashBalance,
  customCategories,
  onClose,
  onCreated,
}) {
  const { showToast } = useToast();
  const [logAs, setLogAs] = useState(lockedLogAs || (isAdmin ? "company" : "self"));
  const [amount, setAmount] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState("General");
  const [newCategory, setNewCategory] = useState("");
  const [addingCategory, setAddingCategory] = useState(false);
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [attachment, setAttachment] = useState("");
  const [fundId, setFundId] = useState("");
  const [visibleTo, setVisibleTo] = useState(() => new Set(members.map((m) => m.userId)));
  const [saving, setSaving] = useState(false);

  const categoryOptions = Array.from(new Set([...BASE_CATEGORIES, ...customCategories]));
  const showToggle = isAdmin && !lockedLogAs;
  const needsFund = isAdmin && logAs === "company";
  const showVisibility = !isAdmin || logAs === "self";

  async function handleAddCategory() {
    const name = newCategory.trim();
    if (!name) return;
    setCategory(name);
    setAddingCategory(false);
    setNewCategory("");
    await addCustomCategory(company._id, user.id, name);
  }

  async function handleFile(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    const b64 = await fileToBase64(file);
    setAttachment(b64);
  }

  function toggleMember(id) {
    setVisibleTo((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function handleSubmit(e) {
    e.preventDefault();
    const amt = parseFloat(amount);
    if (!(amt > 0) || !description.trim()) {
      showToast("Enter a valid amount and description", "error");
      return;
    }
    if (needsFund && !fundId) {
      showToast("Select the bank account or InCash this expense is paid from", "error");
      return;
    }
    setSaving(true);
    const res = await createExpense({
      companyId: company._id,
      userId: user.id,
      amount: amt,
      description: description.trim(),
      category,
      date: new Date(date).toISOString(),
      attachment,
      logAs: isAdmin ? logAs : "self",
      visibleTo: Array.from(visibleTo),
      fundId: needsFund ? fundId : undefined,
    });
    setSaving(false);
    if (res.success) {
      showToast("Expense added successfully!");
      onCreated();
      onClose();
    } else {
      showToast(res.message || "Failed to add expense", "error");
    }
  }

  return (
    <Modal onClose={onClose} maxWidth={520}>
      <h2 style={{ marginTop: 0, fontSize: 20 }}>Add Expense</h2>
      <form onSubmit={handleSubmit}>
        {showToggle && (
          <>
            <label className="field-label">Log Expense As *</label>
            <div style={{ display: "flex", gap: 8, background: "#F8FAFC", border: "1px solid rgba(0,0,0,0.08)", borderRadius: 14, padding: 4, marginBottom: 6 }}>
              <button
                type="button"
                onClick={() => setLogAs("company")}
                className="btn"
                style={{
                  flex: 1,
                  background: logAs === "company" ? "var(--forest-dark)" : "transparent",
                  color: logAs === "company" ? "#fff" : "var(--dark-text)",
                  padding: "10px 8px",
                }}
              >
                Company ({company.name})
              </button>
              <button
                type="button"
                onClick={() => setLogAs("self")}
                className="btn"
                style={{
                  flex: 1,
                  background: logAs === "self" ? "var(--forest-dark)" : "transparent",
                  color: logAs === "self" ? "#fff" : "var(--dark-text)",
                  padding: "10px 8px",
                }}
              >
                Self ({(user.name || "").split(" ")[0]})
              </button>
            </div>
            <p style={{ fontSize: 11, fontStyle: "italic", color: "var(--muted)", marginTop: 0 }}>
              {logAs === "company"
                ? "Logged directly as official company expense (Settled)."
                : "Logged as individual member expense (Outstanding). Requires settlement."}
            </p>
          </>
        )}

        {needsFund && (
          <>
            <label className="field-label">Paid From *</label>
            <select className="field-select" value={fundId} onChange={(e) => setFundId(e.target.value)} style={{ marginBottom: 14 }}>
              <option value="">Select bank account or InCash</option>
              <option value="cash">InCash ({money(cashBalance)})</option>
              {bankAccounts.map((b) => (
                <option key={b._id} value={b._id}>
                  {b.bankName} •••• {String(b.accountNumber).slice(-4)} ({money(b.balance || 0)})
                </option>
              ))}
            </select>
          </>
        )}

        <label className="field-label">Category</label>
        {addingCategory ? (
          <div style={{ display: "flex", gap: 8, marginBottom: 14 }}>
            <input className="field-input" value={newCategory} onChange={(e) => setNewCategory(e.target.value)} placeholder="New category name" />
            <button type="button" className="btn btn-dark" onClick={handleAddCategory}>Add</button>
            <button type="button" className="btn btn-outline" onClick={() => setAddingCategory(false)}>✕</button>
          </div>
        ) : (
          <div style={{ display: "flex", gap: 8, marginBottom: 14 }}>
            <select className="field-select" value={category} onChange={(e) => setCategory(e.target.value)}>
              {categoryOptions.map((c) => (
                <option key={c} value={c}>{c}</option>
              ))}
            </select>
            <button type="button" className="btn btn-outline" onClick={() => setAddingCategory(true)}>+ New</button>
          </div>
        )}

        <label className="field-label">Amount (₹) *</label>
        <input className="field-input" type="number" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" style={{ marginBottom: 14 }} />

        <label className="field-label">Description / Purpose *</label>
        <input className="field-input" value={description} onChange={(e) => setDescription(e.target.value)} placeholder="What is this expense for?" style={{ marginBottom: 14 }} />

        <label className="field-label">Expense Date</label>
        <input className="field-input" type="date" value={date} onChange={(e) => setDate(e.target.value)} style={{ marginBottom: 14 }} />

        {showVisibility && members.length > 0 && (
          <>
            <label className="field-label">Visible To (Select Members)</label>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginBottom: 6 }}>
              {members.map((m) => {
                const isSelf = m.userId === user.id;
                const checked = isSelf || visibleTo.has(m.userId);
                return (
                  <button
                    type="button"
                    key={m.userId}
                    onClick={() => !isSelf && toggleMember(m.userId)}
                    className="pill"
                    style={{
                      background: checked ? "rgba(12,95,65,0.1)" : "#F1F5F9",
                      color: checked ? "var(--forest)" : "var(--dark-text)",
                      border: checked ? "1px solid var(--forest)" : "1px solid transparent",
                      cursor: isSelf ? "default" : "pointer",
                    }}
                  >
                    {isSelf ? `${m.name} (You)` : m.name}
                  </button>
                );
              })}
            </div>
            <p style={{ fontSize: 11, fontStyle: "italic", color: "var(--muted)", marginTop: 0 }}>
              Selected members can view this expense. Restriction automatically unlocks for everyone once paid/settled.
            </p>
          </>
        )}

        <label className="field-label">Receipt / Attachment (Optional)</label>
        <input type="file" accept="image/*" onChange={handleFile} style={{ marginBottom: 14 }} />
        {attachment && (
          <img src={attachment} alt="Receipt preview" style={{ maxWidth: "100%", borderRadius: 12, marginBottom: 14 }} />
        )}

        <button type="submit" className="btn btn-primary btn-block" disabled={saving} style={{ marginTop: 8 }}>
          {saving ? "Saving..." : "Save Expense"}
        </button>
      </form>
    </Modal>
  );
}
