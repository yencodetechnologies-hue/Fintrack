import { useEffect, useState } from "react";
import DescriptionInput from "./DescriptionInput.jsx";
import { addBankAccount, addIncome, deleteBankAccount, getIncomeHistory, updateCashAccountName } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { bankAccountLabel, formatDate, money } from "../utils.js";

function incomeRoute(i, cashName) {
  const to = i.destinationType === "cash" ? cashName : i.destinationName;
  return i.sourceName ? `${to} ← ${i.sourceName}` : to;
}

export default function FundsPanel({ company, user, bankAccounts, cashBalance, onChanged, refreshKey }) {
  const { showToast } = useToast();
  const [accounts, setAccounts] = useState(bankAccounts);
  const [cash, setCash] = useState(cashBalance);
  const [cashName, setCashName] = useState(company?.cashAccountName || "InCash");
  const [isEditingCashName, setIsEditingCashName] = useState(false);
  const [editCashNameInput, setEditCashNameInput] = useState(company?.cashAccountName || "InCash");
  const [savingCashName, setSavingCashName] = useState(false);

  const [income, setIncome] = useState([]);
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
      <h1 style={{ fontSize: 26, margin: "0 0 6px" }}>Company Funds</h1>
      <p style={{ color: "var(--muted)", fontSize: 13.5, margin: "0 0 28px" }}>
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
          <h3 style={{ marginTop: 0, fontSize: 15 }}>New bank account</h3>
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
          <h3 style={{ marginTop: 0, fontSize: 15 }}>Add income</h3>
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
        <>
          <h3 style={{ fontSize: 16, marginBottom: 10 }}>Recent Income</h3>
          <div className="card" style={{ padding: 6 }}>
            {income.slice(0, 10).map((i, idx) => (
              <div
                key={i._id}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 10,
                  padding: "10px 12px",
                  fontSize: 13,
                  borderBottom: idx < income.length - 1 ? "1px solid var(--slate-border-2)" : "none",
                }}
              >
                <span>{i.destinationType === "cash" ? "💵" : "🏦"}</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                    {i.description || incomeRoute(i, cashName)}
                  </div>
                  {i.description && (
                    <small style={{ color: "var(--muted)", fontSize: 11.5, display: "block" }}>
                      {incomeRoute(i, cashName)}
                    </small>
                  )}
                </div>
                <span style={{ color: "var(--muted)", fontSize: 11.5 }}>{formatDate(i.createdAt)}</span>
                <span style={{ color: "var(--forest)", fontWeight: 700 }}>+{money(i.amount)}</span>
              </div>
            ))}
          </div>
        </>
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
      <span style={{ fontSize: 22, marginTop: 2 }}>{icon}</span>
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
                fontSize: 13.5,
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
            <div style={{ fontWeight: 700, fontSize: 14.5 }}>{title}</div>
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
        {subtitle && <div style={{ fontSize: 11.5, color: "var(--muted)", whiteSpace: "pre-wrap", marginTop: 2 }}>{subtitle}</div>}
        <div style={{ fontFamily: "Inter, system-ui, sans-serif", fontWeight: 700, color: "var(--forest)", fontSize: 19, marginTop: 8 }}>
          {money(balance)}
        </div>
      </div>
      {onDelete && (
        <button
          onClick={onDelete}
          style={{ background: "none", border: "none", color: "var(--terracotta)", fontSize: 15, cursor: "pointer" }}
          title="Delete bank account"
        >
          🗑
        </button>
      )}
    </div>
  );
}
