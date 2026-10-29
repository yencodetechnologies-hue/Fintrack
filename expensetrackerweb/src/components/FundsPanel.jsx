import { useEffect, useState } from "react";
import DescriptionInput from "./DescriptionInput.jsx";
import { addBankAccount, addIncome, deleteBankAccount, getAccountsEntries, getCompanyDetails, updateCashAccountName } from "../api.js";
import AccountsPanel from "./AccountsPanel.jsx";
import { useToast } from "../context/ToastContext.jsx";
import { bankAccountLabel, downloadCsv, formatDate, money } from "../utils.js";

export default function FundsPanel({ company, user, bankAccounts, cashBalance, onChanged, refreshKey, canEdit = false }) {
  const { showToast } = useToast();
  const [accounts, setAccounts] = useState(bankAccounts);
  const [cash, setCash] = useState(cashBalance);
  const [cashName, setCashName] = useState(company?.cashAccountName || "InCash");
  const [isEditingCashName, setIsEditingCashName] = useState(false);
  const [editCashNameInput, setEditCashNameInput] = useState(company?.cashAccountName || "InCash");
  const [savingCashName, setSavingCashName] = useState(false);

  // whose statement is shown below the tiles: "cash" (default) or a bank account id
  const [viewFund, setViewFund] = useState("cash");
  const [statementKey, setStatementKey] = useState(0);
  const [mode, setMode] = useState("");
  const [saving, setSaving] = useState(false);
  const [exporting, setExporting] = useState(false);

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

  // after a change on the statement (edit / delete): fresh balances
  async function reloadAfterIncomeChange() {
    setStatementKey((n) => n + 1);
    const details = await getCompanyDetails(company._id, user.id);
    if (details.success && details.company) {
      setAccounts(details.company.bankAccounts || []);
      setCash(details.company.cashBalance ?? cash);
      onChanged(details.company.bankAccounts || [], details.company.cashBalance ?? cash, cashName);
    }
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
      setStatementKey((n) => n + 1);
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

  async function handleExportFunds() {
    if (exporting) return;
    setExporting(true);
    try {
      const fundTitle = viewFund === "cash" ? cashName : accounts.find((x) => String(x._id) === viewFund)?.bankName || "Bank";
      let allEntries = [];
      const res = await getAccountsEntries(company._id, user.id, {
        from: "2000-01-01",
        to: new Date().toISOString().slice(0, 10),
        page: 1,
        limit: 100,
        fund: viewFund,
        movesOnly: true,
      });
      if (res?.success && Array.isArray(res.entries)) {
        allEntries = [...res.entries];
        if (res.pages > 1) {
          const rest = await Promise.all(
            Array.from({ length: res.pages - 1 }, (_, i) =>
              getAccountsEntries(company._id, user.id, {
                from: "2000-01-01",
                to: new Date().toISOString().slice(0, 10),
                page: i + 2,
                limit: 100,
                fund: viewFund,
                movesOnly: true,
              })
            )
          );
          for (const p of rest) {
            if (p?.success && Array.isArray(p.entries)) allEntries.push(...p.entries);
          }
        }
      }

      if (!allEntries.length) {
        showToast("No fund transactions to export", "error");
        return;
      }

      const rows = [["Date", "Time", "Details", "Account", "Debit (Out)", "Credit (In)", "Balance", "By"]];
      for (const r of allEntries) {
        const d = new Date(r.at);
        rows.push([
          formatDate(d),
          d.toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit" }),
          r.details || r.label || "",
          r.account || "",
          r.amount < 0 ? String(-r.amount) : "",
          r.amount > 0 ? String(r.amount) : (r.transferAmount ? String(r.transferAmount) : ""),
          String(r.balance != null ? r.balance : ""),
          r.by || "",
        ]);
      }
      downloadCsv(`${fundTitle.replace(/\s+/g, "-")}-statement.csv`, rows);
    } catch (err) {
      console.error(err);
      showToast("Could not export CSV", "error");
    } finally {
      setExporting(false);
    }
  }

  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
        <h1 style={{ fontSize: 22, margin: 0 }}>Add Funds</h1>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
          <button
            type="button"
            className="btn btn-outline"
            onClick={handleExportFunds}
            disabled={exporting}
          >
            {exporting ? "Exporting…" : "Export CSV"}
          </button>
          <button className="btn btn-primary" onClick={() => setMode(mode === "income" ? "" : "income")}>
            ↗ Add Income
          </button>
          <button className="btn btn-outline" onClick={() => setMode(mode === "bank" ? "" : "bank")}>
            + Add Bank Account
          </button>
        </div>
      </div>
      <p style={{ color: "var(--muted)", margin: "0 0 18px" }}>
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
          selected={viewFund === "cash"}
          onSelect={() => setViewFund("cash")}
        />
        {accounts.map((a) => (
          <FundTile
            key={a._id}
            icon="🏦"
            title={a.bankName}
            subtitle={[a.accountHolder, `A/C ${a.accountNumber}`, a.ifsc ? `IFSC ${a.ifsc}` : ""].filter(Boolean).join(" • ")}
            balance={a.balance || 0}
            onDelete={() => handleDelete(a)}
            selected={viewFund === String(a._id)}
            onSelect={() => setViewFund(String(a._id))}
          />
        ))}
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

      {/* the chosen account: money added and moves to / from my other accounts (no expenses), with its real balance after each */}
      <AccountsPanel
        embedded
        movesOnly
        companyId={company._id}
        user={user}
        canEdit={canEdit}
        fund={viewFund}
        fundName={viewFund === "cash" ? cashName : accounts.find((x) => String(x._id) === viewFund)?.bankName || "Bank"}
        refreshKey={`${refreshKey}-${statementKey}`}
        onChanged={reloadAfterIncomeChange}
      />
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
  selected = false,
  onSelect,
}) {
  return (
    <div
      className={`stat-card fund-tile${selected ? " selected" : ""}`}
      style={{ display: "flex", alignItems: "flex-start", gap: 12 }}
      onClick={(e) => { if (!e.target.closest("button, input, form")) onSelect?.(); }}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => { if (e.key === "Enter" && e.target === e.currentTarget) onSelect?.(); }}
      title="Show this account's statement"
    >
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
