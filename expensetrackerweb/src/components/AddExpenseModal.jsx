import { useState } from "react";
import Modal from "./Modal.jsx";
import { addCustomCategory, createLedgerExpense, saveVisibilityPreference } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { bankAccountLabel, companyCategories, fileToBase64, formatDate } from "../utils.js";
import ConfirmDialog from "./ConfirmDialog.jsx";

export default function AddExpenseModal({
  company,
  user,
  isAdmin,
  members,
  customCategories,
  hiddenStaffIds = [],
  existingExpenses = [],
  onCategoryAdded,
  onHiddenStaffChange,
  onClose,
  onCreated,
}) {
  const { showToast } = useToast();
  const [amount, setAmount] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState("General");
  const [newCategory, setNewCategory] = useState("");
  const [addingCategory, setAddingCategory] = useState(false);
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [attachment, setAttachment] = useState("");
  // Starts from the members this manager unticked last time (saved on the server), so new members stay visible.
  const [visibleTo, setVisibleTo] = useState(() => {
    const hiddenSet = new Set(hiddenStaffIds.map(String));
    return new Set(members.map((m) => m.userId).filter((id) => !hiddenSet.has(String(id))));
  });
  const [postAs, setPostAs] = useState("self");
  const [fundId, setFundId] = useState("cash");
  const [saving, setSaving] = useState(false);
  const [duplicateFound, setDuplicateFound] = useState(null);

  // Categories added in this form show up at once; the server save happens in the background.
  const [addedCategories, setAddedCategories] = useState([]);
  // company's categories (minus ones a manager removed) + any just added in this form
  const categoryOptions = Array.from(new Set([...companyCategories({ ...company, customCategories }), ...addedCategories]));

  function handleAddCategory() {
    const name = newCategory.trim();
    if (!name) return;
    const existing = categoryOptions.find((c) => c.toLowerCase() === name.toLowerCase());
    if (!existing) setAddedCategories((list) => [...list, name]);
    setCategory(existing || name);
    setAddingCategory(false);
    setNewCategory("");
    if (existing) return;
    addCustomCategory(company._id, user.id, name).then((res) => {
      if (res.success) onCategoryAdded?.(res.customCategories || [...customCategories, name]);
      else showToast(res.message || "Category will be saved with the expense", "error");
    });
  }

  async function handleFile(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) {
      showToast("Receipt must be 5 MB or smaller", "error");
      return;
    }
    const b64 = await fileToBase64(file);
    setAttachment(b64);
  }

  function toggleMember(id) {
    const next = new Set(visibleTo);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setVisibleTo(next);
    const selected = new Set([...next].map(String));
    const hidden = members.map((m) => String(m.userId)).filter((memberId) => !selected.has(memberId));
    onHiddenStaffChange?.(hidden);
    saveVisibilityPreference(company._id, user.id, hidden).then((res) => {
      if (!res.success) showToast(res.message || "Couldn't save your visibility choice", "error");
    });
  }

  const selectedFundBalance = (() => {
    if (fundId === "cash") return Number(company.cashBalance || 0);
    const b = (company.bankAccounts || []).find((acct) => String(acct._id) === String(fundId));
    return b ? Number(b.balance || 0) : 0;
  })();
  const parsedAmt = parseFloat(amount) || 0;
  const isInsufficientFund = isAdmin && postAs === "company" && parsedAmt > 0 && selectedFundBalance < parsedAmt;

  // Live hint from already-loaded expenses; the server makes the final check on submit.
  const sameExpense = (exp) =>
    exp.lifecycle !== "rejected" &&
    Number(exp.amount) === parsedAmt &&
    String(exp.description || "").trim().toLowerCase() === description.trim().toLowerCase();
  const likelyDuplicate = parsedAmt > 0 && description.trim() ? existingExpenses.find(sameExpense) : null;

  async function handleSubmit(e, confirmDuplicate = false) {
    e?.preventDefault();
    const amt = parseFloat(amount);
    if (!(amt > 0) || !description.trim()) {
      showToast("Enter a valid amount and description", "error");
      return;
    }
    if (isInsufficientFund) {
      showToast(`Insufficient balance in selected fund (₹${selectedFundBalance.toFixed(2)} available)`, "error");
      return;
    }
    setSaving(true);
    const res = await createLedgerExpense({
      companyId: company._id,
      userId: user.id,
      amount: amt,
      description: description.trim(),
      category,
      date: new Date(date).toISOString(),
      attachment,
      visibleTo: Array.from(visibleTo),
      postAs: isAdmin ? postAs : "self",
      fundId: isAdmin && postAs === "company" ? fundId : undefined,
      checkDuplicate: true,
      confirmDuplicate,
    });
    setSaving(false);
    if (res.success) {
      showToast("Expense added successfully!");
      onCreated();
      onClose();
    } else if (res.code === "DUPLICATE_EXPENSE") {
      setDuplicateFound(res.duplicate || {});
    } else {
      showToast(res.message || "Failed to add expense", "error");
    }
  }

  return (
    <Modal onClose={onClose} maxWidth={520}>
      <div style={{ marginBottom: 18 }}>
        <h2 style={{ margin: "0 0 4px", fontSize: 21, fontWeight: 700, letterSpacing: "-0.2px" }}>Add Expense</h2>
        <p style={{ margin: 0, fontSize: 13, color: "var(--muted)" }}>
          Record a new expense for <strong>{company.name}</strong>
        </p>
      </div>

      <form onSubmit={handleSubmit}>
        {isAdmin && (
          <div style={{ marginBottom: 16 }}>
            <label className="field-label" style={{ marginBottom: 6 }}>Post expense as</label>
            <div className={`segmented-toggle ${postAs === "company" ? "active-second" : ""}`} role="tablist">
              <div className="segmented-toggle-thumb" aria-hidden="true" />
              <button
                type="button"
                className={postAs === "self" ? "active" : ""}
                onClick={() => setPostAs("self")}
              >
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" />
                  <circle cx="12" cy="7" r="4" />
                </svg>
                Manager (Self)
              </button>
              <button
                type="button"
                className={postAs === "company" ? "active" : ""}
                onClick={() => setPostAs("company")}
              >
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                  <rect width="16" height="20" x="4" y="2" rx="2" ry="2" />
                  <path d="M9 22v-4h6v4" />
                  <path d="M8 6h.01" />
                  <path d="M16 6h.01" />
                  <path d="M8 10h.01" />
                  <path d="M16 10h.01" />
                  <path d="M8 14h.01" />
                  <path d="M16 14h.01" />
                </svg>
                Company ({company.name})
              </button>
            </div>

            {postAs === "company" ? (
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  padding: "8px 12px",
                  background: "rgba(25, 87, 84, 0.08)",
                  border: "1px solid rgba(25, 87, 84, 0.16)",
                  borderRadius: 8,
                  marginTop: 10,
                }}
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--forest)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
                  <path d="M20 6 9 17l-5-5" />
                </svg>
                <span style={{ fontSize: 12, color: "var(--forest)", fontWeight: 600 }}>
                  Marked as paid by company and credited under {company.name}.
                </span>
              </div>
            ) : (
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  padding: "8px 12px",
                  background: "#F8FAFC",
                  border: "1px solid var(--slate-border-2)",
                  borderRadius: 8,
                  marginTop: 10,
                }}
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--muted)" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
                  <circle cx="12" cy="12" r="10" />
                  <line x1="12" y1="16" x2="12" y2="12" />
                  <line x1="12" y1="8" x2="12.01" y2="8" />
                </svg>
                <span style={{ fontSize: 12, color: "var(--muted)", fontWeight: 500 }}>
                  Logged under your manager account as payable to you.
                </span>
              </div>
            )}
          </div>
        )}

        {isAdmin && postAs === "company" && (
          <div style={{ marginBottom: 14 }}>
            <label className="field-label">Paid from (Company Fund)</label>
            <select
              className="field-select"
              style={{ height: 40 }}
              value={fundId}
              onChange={(e) => setFundId(e.target.value)}
            >
              <option value="cash">
                Cash Fund · ₹{Number(company.cashBalance || 0).toFixed(2)} {parsedAmt > 0 && Number(company.cashBalance || 0) < parsedAmt ? "⚠️ (Insufficient)" : ""}
              </option>
              {(company.bankAccounts || []).map((b) => {
                const bal = Number(b.balance || 0);
                const low = parsedAmt > 0 && bal < parsedAmt;
                return (
                  <option key={b._id} value={b._id}>
                    {bankAccountLabel(b)} · ₹{bal.toFixed(2)} {low ? "⚠️ (Insufficient)" : ""}
                  </option>
                );
              })}
            </select>
            {isInsufficientFund && (
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  marginTop: 6,
                  padding: "7px 10px",
                  background: "#FEF2F2",
                  border: "1px solid #FECACA",
                  borderRadius: 8,
                  color: "#DC2626",
                  fontSize: 12,
                  fontWeight: 600,
                }}
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
                  <circle cx="12" cy="12" r="10" />
                  <line x1="12" y1="8" x2="12" y2="12" />
                  <line x1="12" y1="16" x2="12.01" y2="16" />
                </svg>
                <span>Insufficient balance: ₹{selectedFundBalance.toFixed(2)} available (₹{parsedAmt.toFixed(2)} required)</span>
              </div>
            )}
          </div>
        )}

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 14 }}>
          <div>
            <label className="field-label">Amount (₹) *</label>
            <div style={{ position: "relative" }}>
              <span style={{ position: "absolute", left: 12, top: "50%", transform: "translateY(-50%)", fontSize: 15, fontWeight: 700, color: "var(--muted)" }}>
                ₹
              </span>
              <input
                className="field-input"
                type="number"
                step="0.01"
                min="0.01"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0.00"
                style={{ paddingLeft: 28, height: 40, marginBottom: 0, fontWeight: 600 }}
                required
              />
            </div>
          </div>

          <div>
            <label className="field-label">Expense Date</label>
            <input
              className="field-input"
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              style={{ height: 40, marginBottom: 0 }}
              required
            />
          </div>
        </div>

        <div style={{ marginBottom: 14 }}>
          <label className="field-label">Category</label>
          {addingCategory ? (
            <div style={{ display: "flex", gap: 8 }}>
              <input
                className="field-input"
                style={{ height: 40, marginBottom: 0 }}
                value={newCategory}
                onChange={(e) => setNewCategory(e.target.value)}
                onKeyDown={(e) => {
                  // Enter adds the category instead of submitting the whole expense form
                  if (e.key === "Enter") {
                    e.preventDefault();
                    handleAddCategory();
                  }
                }}
                placeholder="New category name"
                autoFocus
              />
              <button type="button" className="btn btn-dark" style={{ height: 40, padding: "0 16px" }} onClick={handleAddCategory}>
                Add
              </button>
              <button type="button" className="btn btn-outline" style={{ height: 40, padding: "0 12px" }} onClick={() => setAddingCategory(false)}>
                ✕
              </button>
            </div>
          ) : (
            <div style={{ display: "flex", gap: 8 }}>
              <select
                className="field-select"
                style={{ height: 40, flex: 1 }}
                value={category}
                onChange={(e) => setCategory(e.target.value)}
              >
                {categoryOptions.map((c) => (
                  <option key={c} value={c}>{c}</option>
                ))}
              </select>
              <button
                type="button"
                className="btn btn-outline"
                style={{ height: 40, padding: "0 14px", whiteSpace: "nowrap" }}
                onClick={() => setAddingCategory(true)}
              >
                + New
              </button>
            </div>
          )}
        </div>

        <div style={{ marginBottom: 14 }}>
          <label className="field-label">Description / Purpose *</label>
          <input
            className="field-input"
            style={{ height: 40, marginBottom: 0 }}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="What was this expense for?"
            required
          />
          {likelyDuplicate && (
            <div style={{ marginTop: 6, padding: "7px 10px", background: "#FFF7ED", border: "1px solid #FED7AA", borderRadius: 8, color: "#C2410C", fontSize: 12, fontWeight: 600 }}>
              ⚠️ Possible duplicate: "{likelyDuplicate.description}" for ₹{Number(likelyDuplicate.amount).toFixed(2)} was already posted
              {likelyDuplicate.createdBy?.name ? ` by ${likelyDuplicate.createdBy.name}` : ""} on {formatDate(likelyDuplicate.date || likelyDuplicate.createdAt)}.
            </div>
          )}
        </div>

        {isAdmin && members.length > 0 && (
          <div style={{ marginBottom: 16 }}>
            <label className="field-label" style={{ marginBottom: 6 }}>Visible To</label>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
              {members.map((m) => {
                const isSelf = m.userId === user.id;
                const checked = isSelf || visibleTo.has(m.userId);
                return (
                  <button
                    type="button"
                    key={m.userId}
                    onClick={() => !isSelf && toggleMember(m.userId)}
                    style={{
                      display: "inline-flex",
                      alignItems: "center",
                      gap: 6,
                      padding: "5px 11px",
                      borderRadius: 20,
                      fontSize: 12,
                      fontWeight: 600,
                      cursor: isSelf ? "default" : "pointer",
                      border: checked ? "1px solid rgba(25, 87, 84, 0.3)" : "1px solid var(--slate-border-2)",
                      background: checked ? "rgba(25, 87, 84, 0.08)" : "#F8FAFC",
                      color: checked ? "var(--forest)" : "var(--muted)",
                      transition: "all 0.15s ease",
                    }}
                  >
                    {checked && (
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                        <polyline points="20 6 9 17 4 12" />
                      </svg>
                    )}
                    <span>{isSelf ? `${m.name} (You)` : m.name}</span>
                  </button>
                );
              })}
            </div>
            <p style={{ fontSize: 11, color: "var(--muted)", margin: "6px 0 0" }}>
              Choose which staff can view this expense in their list.
            </p>
          </div>
        )}

        <div style={{ marginBottom: 18 }}>
          <label className="field-label" style={{ marginBottom: 6 }}>Receipt / Attachment (optional)</label>
          <label
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              padding: "10px 14px",
              border: "1.5px dashed var(--slate-border-2)",
              borderRadius: 10,
              background: attachment ? "#F0FDF4" : "#F8FAFC",
              cursor: "pointer",
              transition: "all 0.15s ease",
            }}
          >
            <input type="file" accept="image/*" onChange={handleFile} style={{ display: "none" }} />
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <div
                style={{
                  width: 32,
                  height: 32,
                  borderRadius: 8,
                  background: attachment ? "rgba(25, 87, 84, 0.12)" : "#E2E8F0",
                  color: attachment ? "var(--forest)" : "var(--muted)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  flexShrink: 0,
                }}
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                  <polyline points="17 8 12 3 7 8" />
                  <line x1="12" y1="3" x2="12" y2="15" />
                </svg>
              </div>
              <span style={{ fontSize: 12.5, fontWeight: 600, color: attachment ? "var(--forest)" : "var(--dark-text)" }}>
                {attachment ? "Receipt selected · Click to replace" : "Choose receipt image"}
              </span>
            </div>

            {attachment && (
              <button
                type="button"
                onClick={(e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  setAttachment("");
                }}
                style={{
                  border: "none",
                  background: "none",
                  color: "var(--muted)",
                  cursor: "pointer",
                  fontSize: 12,
                  fontWeight: 600,
                  padding: "4px 8px",
                }}
              >
                Remove
              </button>
            )}
          </label>

          {attachment && (
            <div style={{ marginTop: 8, textAlign: "center" }}>
              <img
                src={attachment}
                alt="Receipt preview"
                style={{ maxHeight: 160, maxWidth: "100%", borderRadius: 8, border: "1px solid var(--slate-border-2)", objectFit: "contain" }}
              />
            </div>
          )}
        </div>

        <button
          type="submit"
          className="btn btn-primary btn-block"
          disabled={saving || isInsufficientFund}
          style={{
            height: 44,
            fontSize: 14,
            fontWeight: 700,
            borderRadius: 10,
            opacity: isInsufficientFund ? 0.55 : 1,
            cursor: isInsufficientFund ? "not-allowed" : "pointer",
          }}
        >
          {saving ? "Submitting…" : isInsufficientFund ? "Insufficient Fund Balance" : "Submit Expense"}
        </button>
      </form>

      {duplicateFound && (
        <ConfirmDialog
          title="Duplicate expense?"
          message={[
            `An expense "${duplicateFound.description || description.trim()}" for ₹${Number(duplicateFound.amount ?? parsedAmt).toFixed(2)} already exists`,
            duplicateFound.createdBy?.name ? ` (posted by ${duplicateFound.createdBy.name})` : "",
            duplicateFound.date || duplicateFound.createdAt ? ` on ${formatDate(duplicateFound.date || duplicateFound.createdAt)}` : "",
            ". Post it again anyway?",
          ].join("")}
          confirmLabel="Post anyway"
          onConfirm={() => {
            setDuplicateFound(null);
            handleSubmit(null, true);
          }}
          onCancel={() => setDuplicateFound(null)}
        />
      )}
    </Modal>
  );
}
