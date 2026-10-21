import { useEffect, useState } from "react";
import Modal from "./Modal.jsx";
import { getLedgerExpenseReceipts, updateLedgerExpenseReceipts } from "../api.js";
import { fileToBase64, formatDate, formatDateTime, money } from "../utils.js";
import { useToast } from "../context/ToastContext.jsx";

export default function ExpenseDetailModal({
  expense,
  user,
  isAdmin,
  company,
  onClose,
  onEdit,
  onApprove,
  onReject,
  onRecordPayment,
  onDelete,
  onVisibility,
  onReceiptsUpdated,
}) {
  const { showToast } = useToast();
  const [uploadingField, setUploadingField] = useState("");
  const [receipts, setReceipts] = useState({
    attachment: expense?.attachment || "",
    paymentReceipt: expense?.paymentReceipt || "",
  });
  const [loadingReceipts, setLoadingReceipts] = useState(false);
  const [activeImageZoom, setActiveImageZoom] = useState(null);

  useEffect(() => {
    if (!expense?._id) return;
    if (expense.hasAttachment || expense.hasPaymentReceipt) {
      if (!expense.attachment && !expense.paymentReceipt) {
        setLoadingReceipts(true);
        getLedgerExpenseReceipts(expense._id, user.id)
          .then((res) => {
            if (res.success) {
              const toDataUrl = (data) => {
                if (!data) return "";
                return data.startsWith("data:") ? data : `data:image/jpeg;base64,${data}`;
              };
              setReceipts({
                attachment: toDataUrl(res.attachment),
                paymentReceipt: toDataUrl(res.paymentReceipt),
              });
            }
          })
          .finally(() => setLoadingReceipts(false));
      } else {
        const toDataUrl = (data) => {
          if (!data) return "";
          return data.startsWith("data:") ? data : `data:image/jpeg;base64,${data}`;
        };
        setReceipts({
          attachment: toDataUrl(expense.attachment),
          paymentReceipt: toDataUrl(expense.paymentReceipt),
        });
      }
    }
  }, [expense, user.id]);

  if (!expense) return null;

  const creatorName =
    expense.createdBy?.name ||
    (expense.logAs === "company" || expense.postedAs === "company" ? company?.name || "Company" : "Staff");
  const creatorEmail = expense.createdBy?.email || "";
  const isCreator = String(expense.createdBy?._id || expense.createdBy) === user.id;

  const lifecycle = expense.lifecycle || "submitted";
  const isApproved = lifecycle === "approved";
  const isSubmitted = lifecycle === "submitted";
  const isRejected = lifecycle === "rejected";
  const isPaid = lifecycle.startsWith("paid") || expense.status === "paid";

  const LIFECYCLE_LABELS = {
    submitted: "Awaiting approval",
    approved: "Approved · unpaid",
    rejected: "Rejected",
    paid_by_admin: "Paid by manager",
    paid_by_person: "Paid by staff",
    paid_by_company: "Paid by company",
    awaiting_confirmation: "Awaiting payer confirmation",
    reimbursed: "Reimbursed",
  };
  const lifecycleLabel = LIFECYCLE_LABELS[lifecycle] || lifecycle.replaceAll("_", " ");
  const lifecycleClass =
    isApproved || isPaid ? "pill-paid" : isRejected ? "pill-outstanding" : "pill-category";

  const isAwaitingPayer = lifecycle === "awaiting_confirmation";
  // the creating manager can always open Edit to switch who paid (me / company), even after payment
  const paidByMe = lifecycle === "paid_by_admin" && String(expense.paidByAdminId?._id || expense.paidByAdminId) === String(user.id);
  const creatorCanSwitchPayer = isAdmin && isCreator && (isApproved || lifecycle === "paid_by_company" || paidByMe);
  const canEdit =
    (isAdmin && !isPaid && !isAwaitingPayer) || (!isAdmin && isSubmitted && isCreator && !isPaid) || creatorCanSwitchPayer;

  // managers can fix receipt images at any status
  const canReplaceReceipts = isAdmin;

  async function replaceReceipt(field, file) {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      showToast("Choose an image file", "error");
      return;
    }
    setUploadingField(field);
    const data = await fileToBase64(file);
    const res = await updateLedgerExpenseReceipts(expense._id, user.id, { [field]: data });
    setUploadingField("");
    if (res.success) {
      setReceipts((current) => ({ ...current, [field]: data }));
      showToast(field === "attachment" ? "Bill receipt updated" : "Payment proof updated");
      onReceiptsUpdated?.();
    } else {
      showToast(res.message || "Failed to update receipt", "error");
    }
  }

  const replaceButton = (field, label) => (
    <label className="btn btn-outline" style={{ fontSize: 12, padding: "6px 12px", opacity: uploadingField ? 0.6 : 1, pointerEvents: uploadingField ? "none" : "auto" }}>
      {uploadingField === field ? "Uploading…" : label}
      <input
        type="file"
        accept="image/*"
        style={{ display: "none" }}
        onChange={(e) => {
          replaceReceipt(field, e.target.files?.[0]);
          e.target.value = "";
        }}
      />
    </label>
  );

  const canDelete =
    (isAdmin && !isPaid) || (!isAdmin && isSubmitted && isCreator);

  const isCompanyPost = expense.logAs === "company" || expense.postedAs === "company";
  const nameOf = (ref, fallback) => (ref && typeof ref === "object" ? ref.name : fallback);
  const fundLabel = expense.fundName || (expense.fundType === "cash" ? (company?.cashAccountName || "InCash") : "");
  const paymentText = [expense.payerMethod, fundLabel].filter(Boolean).join(" · ");
  const hasReceiptSection = canReplaceReceipts || expense.hasAttachment || expense.hasPaymentReceipt || receipts.attachment || receipts.paymentReceipt;
  const run = (fn) => () => {
    fn(expense);
    onClose();
  };

  const rows = [
    ["Expense date", formatDate(expense.date || expense.createdAt)],
    ["Posted by", <span key="by">{creatorName}{creatorEmail && <span style={subValStyle}>{creatorEmail}</span>}</span>],
    ["Posted on", formatDateTime(expense.createdAt)],
    ["Type", isCompanyPost ? "Company expense" : "Personal expense (reimbursable)"],
    ["Company", expense.companyId?.name || company?.name || "Company"],
    expense.approvedBy && ["Approved by", nameOf(expense.approvedBy, "Manager")],
    isPaid && expense.paidByUserId && ["Paid by", nameOf(expense.paidByUserId, "Member")],
    isPaid && paymentText && ["Payment", paymentText],
    expense.payerReference && ["Reference / UTR", <span key="ref" style={{ fontFamily: "monospace" }}>{expense.payerReference}</span>],
    isAdmin && expense.visibleTo && ["Staff visibility", expense.visibleTo.length === 0 ? "All staff" : `${expense.visibleTo.length} selected staff`],
  ].filter(Boolean);

  const primaryAction =
    isAdmin && isSubmitted && onApprove ? (
      <button type="button" className="btn btn-primary" onClick={run(onApprove)}>Approve</button>
    ) : isApproved && onRecordPayment ? (
      <button type="button" className="btn btn-primary" onClick={run(onRecordPayment)}>Record payment</button>
    ) : null;

  return (
    <Modal onClose={onClose} maxWidth={560}>
      {/* Header */}
      <div style={{ paddingRight: 40 }}>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          <span className={`pill ${lifecycleClass}`} style={{ fontSize: 11 }}>{lifecycleLabel}</span>
          <span className="pill pill-category" style={{ fontSize: 11 }}>{expense.category || "General"}</span>
          {expense.verification && (
            <span
              className="pill"
              style={{
                fontSize: 11,
                background: expense.verification === "verified" ? "#E8F5E9" : "#FFF3E0",
                color: expense.verification === "verified" ? "#2E7D32" : "#C2410C",
              }}
            >
              {expense.verification === "verified" ? "✓ Verified" : "Verification pending"}
            </span>
          )}
        </div>
      </div>

      <h2 style={{ margin: "14px 0 2px", fontSize: 21, lineHeight: 1.25, color: "var(--dark-text)", wordBreak: "break-word" }}>
        {expense.description}
      </h2>
      <div style={{ fontFamily: "Fraunces, serif", fontSize: 30, fontWeight: 700, color: "var(--forest)" }}>
        {money(expense.amount)}
      </div>

      {/* Details */}
      <dl style={detailsBoxStyle}>
        {rows.map(([label, value], idx) => (
          <div key={label} style={{ ...detailRowStyle, borderTop: idx === 0 ? "none" : "1px solid var(--slate-border-2)" }}>
            <dt style={labelStyle}>{label}</dt>
            <dd style={valStyle}>{value}</dd>
          </div>
        ))}
      </dl>

      {/* Receipts */}
      {hasReceiptSection && (
        <div style={{ marginBottom: 6 }}>
          <div style={{ ...labelStyle, marginBottom: 8 }}>Receipts</div>
          {loadingReceipts ? (
            <div style={{ color: "var(--muted)", fontSize: 12.5, fontStyle: "italic", padding: "8px 0" }}>Loading receipts…</div>
          ) : (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: 10 }}>
              {[
                ["attachment", "Bill / receipt"],
                ["paymentReceipt", "Payment proof"],
              ]
                .filter(([field]) => receipts[field])
                .map(([field, label]) => (
                  <button
                    key={field}
                    type="button"
                    style={receiptThumbBox}
                    onClick={() => setActiveImageZoom({ url: receipts[field], label })}
                    title="Click to zoom"
                  >
                    <img src={receipts[field]} alt={label} style={receiptImgStyle} />
                    <span style={receiptThumbLabel}>
                      <span>{label}</span>
                      <span style={{ color: "var(--muted)", fontWeight: 600 }}>View ↗</span>
                    </span>
                  </button>
                ))}
            </div>
          )}
          {canReplaceReceipts && !loadingReceipts && (
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 10 }}>
              {replaceButton("attachment", receipts.attachment ? "Replace bill receipt" : "Add bill receipt")}
              {(isPaid || receipts.paymentReceipt) && replaceButton("paymentReceipt", receipts.paymentReceipt ? "Replace payment proof" : "Add payment proof")}
            </div>
          )}
        </div>
      )}

      {/* Actions: destructive on the left, everyday actions on the right, main action last */}
      <div style={actionBarStyle}>
        <div>
          {canDelete && onDelete && (
            <button type="button" className="btn btn-outline-danger" onClick={run(onDelete)}>Delete</button>
          )}
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", justifyContent: "flex-end" }}>
          {isAdmin && onVisibility && (
            <button type="button" className="btn btn-outline" onClick={run(onVisibility)}>Visibility</button>
          )}
          {canEdit && onEdit && (
            <button type="button" className="btn btn-outline" onClick={run(onEdit)}>Edit</button>
          )}
          {isAdmin && isSubmitted && onReject && (
            <button type="button" className="btn btn-outline" onClick={run(onReject)}>Reject</button>
          )}
          {primaryAction}
          {!primaryAction && (
            <button type="button" className="btn btn-dark" onClick={onClose}>Done</button>
          )}
        </div>
      </div>

      {activeImageZoom && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(0,0,0,0.85)",
            zIndex: 9999,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            padding: 20,
          }}
          onClick={() => setActiveImageZoom(null)}
        >
          <div style={{ color: "#fff", marginBottom: 10, fontSize: 14, fontWeight: 600 }}>
            {activeImageZoom.label} (Click anywhere to close)
          </div>
          <img
            src={activeImageZoom.url}
            alt={activeImageZoom.label}
            style={{ maxWidth: "90vw", maxHeight: "80vh", borderRadius: 8, objectFit: "contain" }}
          />
        </div>
      )}
    </Modal>
  );
}

const labelStyle = {
  display: "block",
  fontSize: 11,
  fontWeight: 700,
  letterSpacing: 0.5,
  textTransform: "uppercase",
  color: "var(--muted)",
  margin: 0,
};

const valStyle = {
  margin: 0,
  fontSize: 13.5,
  fontWeight: 600,
  color: "var(--dark-text)",
  wordBreak: "break-word",
  textAlign: "right",
};

const subValStyle = {
  display: "block",
  fontSize: 11.5,
  fontWeight: 500,
  color: "var(--muted)",
};

const detailsBoxStyle = {
  margin: "18px 0",
  padding: "4px 14px",
  background: "var(--slate-bg)",
  border: "1px solid var(--slate-border-2)",
  borderRadius: 12,
};

const detailRowStyle = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "baseline",
  gap: 16,
  padding: "10px 0",
};

const receiptThumbBox = {
  display: "block",
  width: "100%",
  padding: 0,
  textAlign: "left",
  border: "1px solid var(--slate-border)",
  borderRadius: 10,
  overflow: "hidden",
  background: "#fff",
  cursor: "zoom-in",
};

const receiptThumbLabel = {
  display: "flex",
  justifyContent: "space-between",
  padding: "8px 10px",
  fontSize: 12,
  fontWeight: 700,
  color: "var(--forest)",
  borderTop: "1px solid var(--slate-border-2)",
};

const receiptImgStyle = {
  width: "100%",
  height: 140,
  objectFit: "contain",
  background: "var(--slate-bg)",
  display: "block",
};

const actionBarStyle = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "center",
  gap: 10,
  flexWrap: "wrap",
  marginTop: 18,
  paddingTop: 16,
  borderTop: "1px solid var(--slate-border-2)",
};
