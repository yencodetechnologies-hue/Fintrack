import { useState } from "react";
import Modal from "./Modal.jsx";
import ConfirmDialog from "./ConfirmDialog.jsx";
import { addCompanyCategory, deleteCompanyCategory } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { companyCategories } from "../utils.js";

// Managers add or remove the categories offered when posting expenses. Existing expenses keep their category.
export default function ManageCategoriesModal({ company, user, onClose, onChanged }) {
  const { showToast } = useToast();
  const [state, setState] = useState({
    customCategories: company.customCategories || [],
    hiddenCategories: company.hiddenCategories || [],
  });
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [deleting, setDeleting] = useState(null);

  const categories = companyCategories({ ...company, ...state });

  async function handleAdd(e) {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) return;
    if (categories.some((c) => c.toLowerCase() === trimmed.toLowerCase())) {
      showToast(`"${trimmed}" already exists`, "error");
      return;
    }
    setBusy(true);
    const res = await addCompanyCategory(company._id, user.id, trimmed);
    setBusy(false);
    if (res.success) {
      setState({ customCategories: res.customCategories, hiddenCategories: res.hiddenCategories });
      setName("");
      showToast(`Category "${trimmed}" added`);
      onChanged?.();
    } else showToast(res.message || "Could not add category", "error");
  }

  async function confirmDelete() {
    const target = deleting;
    setDeleting(null);
    setBusy(true);
    const res = await deleteCompanyCategory(company._id, user.id, target);
    setBusy(false);
    if (res.success) {
      setState({ customCategories: res.customCategories, hiddenCategories: res.hiddenCategories });
      showToast(res.inUse ? `"${target}" removed · ${res.inUse} existing expense(s) keep it` : `"${target}" removed`);
      onChanged?.();
    } else showToast(res.message || "Could not delete category", "error");
  }

  return (
    <Modal onClose={onClose} maxWidth={460}>
      <h2 style={{ marginTop: 0, fontSize: 20 }}>Manage categories</h2>
      <p style={{ color: "var(--muted)", fontSize: 13, margin: "-4px 0 16px" }}>
        These appear when posting an expense. Removing one doesn't change expenses that already use it.
      </p>

      <form onSubmit={handleAdd} style={{ display: "flex", gap: 8, marginBottom: 14 }}>
        <input
          className="field-input"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="New category name"
          maxLength={40}
          style={{ flex: 1, height: 40, marginBottom: 0 }}
          autoFocus
        />
        <button type="submit" className="btn btn-primary" disabled={busy || !name.trim()} style={{ height: 40 }}>
          Add
        </button>
      </form>

      <div className="card expense-list" style={{ maxHeight: 320, overflowY: "auto" }}>
        {categories.length === 0 ? (
          <div style={{ color: "var(--muted)", fontSize: 13, padding: "12px 16px" }}>No categories. Add one above.</div>
        ) : (
          categories.map((c) => (
            <div key={c} className="expense-row static">
              <span className="expense-row-main">
                <span className="expense-row-title">{c}</span>
              </span>
              <span className="expense-row-action">
                <button
                  type="button"
                  className="btn btn-outline-danger btn-sm"
                  disabled={busy}
                  onClick={() => setDeleting(c)}
                  aria-label={`Delete ${c}`}
                >
                  Delete
                </button>
              </span>
            </div>
          ))
        )}
      </div>

      {deleting && (
        <ConfirmDialog
          title="Delete category?"
          message={`"${deleting}" will no longer be offered when posting expenses. Expenses already in this category keep it.`}
          confirmLabel="Delete"
          danger
          onConfirm={confirmDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
    </Modal>
  );
}
