import { useEffect, useState } from "react";
import DescriptionInput from "./DescriptionInput.jsx";
import { addBankAccount, addIncome, deleteAccountsEntry, deleteBankAccount, editAccountsEntry, getCompanyDetails, getIncomeHistory, updateCashAccountName } from "../api.js";
import ConfirmDialog from "./ConfirmDialog.jsx";
import Modal from "./Modal.jsx";
import { useToast } from "../context/ToastContext.jsx";
import { bankAccountLabel, formatDate, money } from "../utils.js";
import { TableCard } from "./DataTable.jsx";

function incomeRoute(i, cashName) {
  const to = i.destinationType === "cash" ? cashName : i.destinationName;
  return i.sourceName ? `${to} ← ${i.sourceName}` : to;
}

export default function FundsPanel({ company, user, bankAccounts, cashBalance, onChanged, refreshKey, canEdit = false }) {
  const { showToast } = useToast();
  const [accounts, setAccounts] = useState(bankAccounts);
  const [cash, setCash] = useState(cashBalance);
  const [cashName, setCashName] = useState(company?.cashAccountName || "InCash");
  const [isEditingCashName, setIsEditingCashName] = useState(false);
  const [editCashNameInput, setEditCashNameInput] = useState(company?.cashAccountName || "InCash");
  const [savingCashName, setSavingCashName] = useState(false);

  const [income, setIncome] = useState([]);
  // the Admin editing / deleting an income entry
  const [editingIncome, setEditingIncome] = useState(null); // { id, amount, description, date }
  const [deletingIncome, setDeletingIncome] = useState(null);
  const [savingIncome, setSavingIncome] = useState(false);
  const [mode, setMode] = useState("");
  const [saving, setSaving] = useState(false);

  const [bankName, setBankName] = useState("");
  const [holder, setHolder] = useState("");
  const [number, setNumber] = useState("");
  const [ifsc, setIfsc] = useState("");

  const [incomeAmount, setIncomeAmount] = useState("");
  const [incomeDescription, setIncomeDescription] = useState("");
  const [destination, setDestination] = useState("");
  const [sourceBank, setSourceBank] = useState("");

  useEffect(() => {
    setAccounts(bankAccounts);
    setCash(cashBalance);
  }, [bankAccounts, cashBalance]);

  useEffect(() => {
    const name = company?.cashAccountName || "InCash";
    setCashName(name);
    setEditCashNameInput(name);
  }, [company?.cashAccountName]);

  useEffect(() => {
    getIncomeHistory(company._id, user.id).then((res) => {
      if (res.success) setIncome(res.income || []);
    });
  }, [company._id, user.id, refreshKey]);

  // after an income edit / delete: fresh list and balances
  async function reloadAfterIncomeChange() {
    const [list, details] = await Promise.all([getIncomeHistory(company._id, user.id), getCompanyDetails(company._id, user.id)]);
    if (list.success) setIncome(list.income || []);
    if (details.success && details.company) {
      setAccounts(details.company.bankAccounts || []);
      setCash(details.company.cashBalance ?? cash);
      onChanged(details.company.bankAccounts || [], details.company.cashBalance ?? cash, cashName);
    }
  }

  async function saveIncomeEdit() {
    const value = Number(editingIncome.amount);
    if (!(value > 0)) return showToast("Enter an amount greater than zero", "error");
    setSavingIncome(true);
    const res = await editAccountsEntry(company._id, user.id, `income:${editingIncome.id}`, { amount: value, details: editingIncome.description.trim(), date: editingIncome.date || undefined });
    setSavingIncome(false);
    if (!res.success) return showToast(res.message || "Could not save the changes", "error");
    showToast("Income updated · balances adjusted");
    setEditingIncome(null);
    reloadAfterIncomeChange();
  }

  async function confirmDeleteIncome() {
    const entry = deletingIncome;
    setDeletingIncome(null);
    const res = await deleteAccountsEntry(company._id, user.id, `income:${entry._id}`);
    if (!res.success) return showToast(res.message || "Could not delete it", "error");
    showToast(`Deleted · ${money(entry.amount)} taken back out`);
    reloadAfterIncomeChange();
  }

  function handleStartEditCashName() {
    setEditCashNameInput(cashName);
    setIsEditingCashName(true);
  }

  function handleCancelEditCashName() {
    setEditCashNameInput(cashName);
    setIsEditingCashName(false);
  }

  async function handleSaveCashName(e) {
    if (e) e.preventDefault();
    const trimmed = editCashNameInput.trim();
    if (!trimmed) {
      showToast("Cash account name cannot be empty", "error");
      return;
    }
    setSavingCashName(true);
    const res = await updateCashAccountName(company._id, user.id, trimmed);
    setSavingCashName(false);
    if (res.success) {
      setCashName(trimmed);
      setIsEditingCashName(false);
      showToast("Cash account name updated");
      if (onChanged) onChanged(accounts, cash, trimmed);
    } else {
      showToast(res.message || "Failed to update name", "error");
    }
  }

  async function handleSaveBank(e) {
    e.preventDefault();
    if (!bankName.trim() || !number.trim()) {
      showToast("Bank name and account number are required", "error");
      return;
    }
    setSaving(true);
    const res = await addBankAccount(company._id, user.id, bankName.trim(), holder.trim(), number.trim(), ifsc.trim());
    setSaving(false);
    if (res.success) {
      setAccounts(res.bankAccounts || []);
      setMode("");
      setBankName(""); setHolder(""); setNumber(""); setIfsc("");
      onChanged(res.bankAccounts, cash, cashName);
    } else {
      showToast(res.message || "Failed to save bank account", "error");
    }
  }

  async function handleSaveIncome(e) {
    e.preventDefault();
    const amt = parseFloat(incomeAmount);
    if (!(amt > 0)) {
      showToast("Enter a valid amount", "error");
      return;
    }
    if (!destination) {
      showToast(`Select a bank account or ${cashName}`, "error");
      return;
    }
    if (!sourceBank) {
      showToast("Select where the money is coming from", "error");
      return;
    }
    setSaving(true);
    const res = await addIncome(company._id, user.id, amt, destination, sourceBank, incomeDescription.trim());
    setSaving(false);
    if (res.success) {
      setAccounts(res.bankAccounts || []);
      setCash(res.cashBalance ?? cash);
      onChanged(res.bankAccounts, res.cashBalance ?? cash, cashName);
      setMode("");
      setIncomeAmount(""); setIncomeDescription(""); setDestination(""); setSourceBank("");
      getIncomeHistory(company._id, user.id).then((r) => r.success && setIncome(r.income || []));
    } else {
      showToast(res.message || "Failed to add income", "error");
    }
  }

  async function handleDelete(account) {
    const res = await deleteBankAccount(company._id, user.id, account._id);
    if (res.success) {
      setAccounts(res.bankAccounts || []);
      onChanged(res.bankAccounts, cash, cashName);
    } else {
      showToast(res.message || "Failed to remove bank account", "error");
    }
  }

  return (
    <div>
      <h1 style={{ fontSize: 22, margin: "0 0 6px" }}>Company Funds</h1>
      <p style={{ color: "var(--muted)", fontSize: 14, margin: "0 0 28px" }}>
        Track {cashName} and bank balances, and where company money moves.
      </p>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))", gap: 14, marginBottom: 28 }}>
        <FundTile
          icon="💵"
          title={cashName}
          subtitle="Cash in hand"
          balance={cash}
          isEditing={isEditingCashName}
          editValue={editCashNameInput}
          onEditChange={setEditCashNameInput}
          onStartEdit={handleStartEditCashName}
          onCancelEdit={handleCancelEditCashName}
          onSaveEdit={handleSaveCashName}
          savingEdit={savingCashName}
        />
        {accounts.map((a) => (
          <FundTile
            key={a._id}
            icon="🏦"
            title={a.bankName}
            subtitle={[a.accountHolder, `A/C ${a.accountNumber}`, a.ifsc ? `IFSC ${a.ifsc}` : ""].filter(Boolean).join(" • ")}
            balance={a.balance || 0}
            onDelete={() => handleDelete(a)}
          />
        ))}
      </div>

      <div style={{ display: "flex", gap: 10, marginBottom: 24 }}>
        <button className="btn btn-primary" onClick={() => setMode(mode === "income" ? "" : "income")}>
          ↗ Add Income
        </button>
        <button className="btn btn-outline" onClick={() => setMode(mode === "bank" ? "" : "bank")}>
          + Add Bank Account
        </button>
      </div>

      {mode === "bank" && (
        <form onSubmit={handleSaveBank} className="card" style={{ maxWidth: 440, marginBottom: 28 }}>
          <h3 style={{ marginTop: 0, fontSize: 16 }}>New bank account</h3>
          <input className="field-input" value={bankName} onChange={(e) => setBankName(e.target.value)} placeholder="Bank name *" style={{ marginBottom: 10 }} />
          <input className="field-input" value={holder} onChange={(e) => setHolder(e.target.value)} placeholder="Account holder name" style={{ marginBottom: 10 }} />
          <input className="field-input" value={number} onChange={(e) => setNumber(e.target.value)} placeholder="Account number *" style={{ marginBottom: 10 }} />
          <input className="field-input" value={ifsc} onChange={(e) => setIfsc(e.target.value.toUpperCase())} placeholder="IFSC code" style={{ marginBottom: 14 }} />
          <div style={{ display: "flex", gap: 10 }}>
            <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setMode("")}>Cancel</button>
            <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>{saving ? "Saving..." : "Save"}</button>
          </div>
        </form>
      )}

      {mode === "income" && (
        <form onSubmit={handleSaveIncome} className="card" style={{ maxWidth: 440, marginBottom: 28 }}>
          <h3 style={{ marginTop: 0, fontSize: 16 }}>Add income</h3>
          <input className="field-input" type="number" step="0.01" value={incomeAmount} onChange={(e) => setIncomeAmount(e.target.value)} placeholder="Amount (₹) *" style={{ marginBottom: 10 }} />
          <div style={{ marginBottom: 10 }}>
            <DescriptionInput companyId={company._id} userId={user.id} kind="fund" value={incomeDescription} onChange={setIncomeDescription} placeholder="Description (optional)" style={{ marginBottom: 0 }} />
          </div>
          <select className="field-select" value={destination} onChange={(e) => { setDestination(e.target.value); setSourceBank(""); }} style={{ marginBottom: 10 }}>
            <option value="">Add to *</option>
            <option value="cash">{cashName} ({money(cash)})</option>
            {accounts.map((b) => (
              <option key={b._id} value={b._id}>{bankAccountLabel(b)} · {money(b.balance || 0)}</option>
            ))}
          </select>
          {destination && (
            <>
              <select className="field-select" value={sourceBank} onChange={(e) => setSourceBank(e.target.value)} style={{ marginBottom: 6 }}>
                <option value="">Money coming from *</option>
                <option value="direct">{destination === "cash" ? "Direct cash (new money)" : "Direct income (new money)"}</option>
                {accounts.filter((b) => b._id !== destination).map((b) => (
                  <option key={b._id} value={b._id}>{bankAccountLabel(b)} · {money(b.balance || 0)}</option>
                ))}
              </select>
              {sourceBank && (
                <p style={{ fontSize: 11, fontStyle: "italic", color: "var(--muted)", marginTop: 0 }}>
                  {sourceBank === "direct"
                    ? "This amount is added as new money; no other balance changes."
                    : "This amount is taken out of the selected bank's balance and moved here."}
                </p>
              )}
            </>
          )}
          <div style={{ display: "flex", gap: 10, marginTop: 8 }}>
            <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setMode("")}>Cancel</button>
            <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>{saving ? "Saving..." : "Save"}</button>
          </div>
        </form>
      )}

      {income.length > 0 && (
        <TableCard title="Income" meta={`${income.length} ${income.length === 1 ? "entry" : "entries"}`} items={income}>
          {(rows) => (
            <>
          <table className="dt">
            <thead>
              <tr><th>Date</th><th>Details</th><th>Into</th><th className="num">Amount</th>{canEdit && <th className="num">Action</th>}</tr>
            </thead>
            <tbody>
              {rows.map((i) => (
                <tr key={i._id}>
                  <td className="nowrap">{formatDate(i.createdAt)}</td>
                  <td className="dt-wrap-text dt-strong">{i.description || incomeRoute(i, cashName)}</td>
                  <td>{i.destinationType === "cash" ? "💵" : "🏦"} {incomeRoute(i, cashName)}</td>
                  <td className="num in">{money(i.amount)}</td>
                  {canEdit && (
                    <td>
                      <span className="dt-actions">
                        <button type="button" className="btn btn-outline btn-sm" onClick={() => setEditingIncome({ id: i._id, amount: String(i.amount), description: i.description || "", date: istInput(i.createdAt) })}>Edit</button>
                        <button type="button" className="btn btn-outline-danger btn-sm" onClick={() => setDeletingIncome(i)}>Delete</button>
                      </span>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        
            </>
          )}
        </TableCard>
      )}
      {editingIncome && (
        <Modal onClose={() => setEditingIncome(null)} maxWidth={440}>
          <h2 style={{ margin: "0 0 14px", fontSize: 20 }}>Edit income</h2>
          <div style={{ display: "grid", gap: 10 }}>
            <div>
              <label className="field-label">Amount (₹)</label>
              <input className="field-input" type="number" min="0.01" step="0.01" autoFocus value={editingIncome.amount} onChange={(e) => setEditingIncome({ ...editingIncome, amount: e.target.value })} />
            </div>
            <div>
              <label className="field-label">Description</label>
              <input className="field-input" value={editingIncome.description} onChange={(e) => setEditingIncome({ ...editingIncome, description: e.target.value })} />
            </div>
            <div>
              <label className="field-label">Date & time</label>
              <input className="field-input" type="datetime-local" value={editingIncome.date} onChange={(e) => setEditingIncome({ ...editingIncome, date: e.target.value })} />
            </div>
            <p style={{ color: "var(--muted)", fontSize: 12, margin: 0 }}>A new amount changes that account's balance by the difference.</p>
            <div style={{ display: "flex", gap: 10, marginTop: 4 }}>
              <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setEditingIncome(null)} disabled={savingIncome}>Cancel</button>
              <button type="button" className="btn btn-primary" style={{ flex: 1 }} onClick={saveIncomeEdit} disabled={savingIncome}>{savingIncome ? "Saving…" : "Save"}</button>
            </div>
          </div>
        </Modal>
      )}
      {deletingIncome && (
        <ConfirmDialog
          title="Delete this income?"
          message={`${money(deletingIncome.amount)}${deletingIncome.description ? ` (${deletingIncome.description})` : ""} will be taken back out of ${deletingIncome.destinationType === "cash" ? cashName : deletingIncome.destinationName || "the bank"}${deletingIncome.sourceName && deletingIncome.sourceBankAccountId ? ` and put back into ${deletingIncome.sourceName}` : ""}, and the entry removed.`}
          confirmLabel="Delete"
          danger
          onCancel={() => setDeletingIncome(null)}
          onConfirm={confirmDeleteIncome}
        />
      )}
    </div>
  );
}

function FundTile({
  icon,
  title,
  subtitle,
  balance,
  onDelete,
  isEditing,
  editValue,
  onEditChange,
  onStartEdit,
  onCancelEdit,
  onSaveEdit,
  savingEdit,
}) {
  return (
    <div className="stat-card" style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
      <span style={{ fontSize: 20, marginTop: 2 }}>{icon}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        {isEditing ? (
          <form onSubmit={onSaveEdit} style={{ display: "flex", gap: 6, alignItems: "center", marginBottom: 6 }}>
            <input
              type="text"
              value={editValue}
              onChange={(e) => onEditChange(e.target.value)}
              autoFocus
              className="field-input"
              style={{
                padding: "3px 8px",
                fontSize: 14,
                fontWeight: 600,
                height: 28,
                flex: 1,
                minWidth: 0,
              }}
            />
            <button
              type="submit"
              className="btn btn-primary"
              disabled={savingEdit}
              style={{ padding: "0 8px", fontSize: 12, height: 28, lineHeight: 1 }}
              title="Save"
            >
              {savingEdit ? "..." : "✓"}
            </button>
            <button
              type="button"
              className="btn btn-outline"
              onClick={onCancelEdit}
              style={{ padding: "0 8px", fontSize: 12, height: 28, lineHeight: 1 }}
              title="Cancel"
            >
              ✕
            </button>
          </form>
        ) : (
          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <div style={{ fontWeight: 700, fontSize: 14 }}>{title}</div>
            {onStartEdit && (
              <button
                type="button"
                onClick={onStartEdit}
                style={{
                  background: "none",
                  border: "none",
                  cursor: "pointer",
                  color: "var(--muted)",
                  fontSize: 13,
                  padding: "0 2px",
                  display: "inline-flex",
                  alignItems: "center",
                  lineHeight: 1,
                }}
                title="Edit name"
              >
                ✏️
              </button>
            )}
          </div>
        )}
        {subtitle && <div style={{ fontSize: 12, color: "var(--muted)", whiteSpace: "pre-wrap", marginTop: 2 }}>{subtitle}</div>}
        <div style={{ fontFamily: "Helvetica Neue, Helvetica, Arial, sans-serif", fontWeight: 700, color: "var(--forest)", fontSize: 20, marginTop: 8 }}>
          {money(balance)}
        </div>
      </div>
      {onDelete && (
        <button
          onClick={onDelete}
          style={{ background: "none", border: "none", color: "var(--terracotta)", fontSize: 16, cursor: "pointer" }}
          title="Delete bank account"
        >
          🗑
        </button>
      )}
    </div>
  );
}

// a date as "YYYY-MM-DDTHH:mm" in India time, for the date & time input
function istInput(at) {
  return new Date(new Date(at).getTime() + 330 * 60000).toISOString().slice(0, 16);
}
