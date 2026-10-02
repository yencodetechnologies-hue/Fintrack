import Modal from "./Modal.jsx";

export default function ConfirmDialog({ title, message, confirmLabel = "Confirm", danger = false, onConfirm, onCancel }) {
  return (
    <Modal onClose={onCancel} maxWidth={380}>
      <h3 style={{ marginTop: 0 }}>{title}</h3>
      <p style={{ color: "var(--muted)", fontSize: 13.5, lineHeight: 1.5 }}>{message}</p>
      <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
        <button className="btn btn-outline" style={{ flex: 1 }} onClick={onCancel}>
          Cancel
        </button>
        <button
          className={`btn ${danger ? "btn-outline-danger" : "btn-primary"}`}
          style={{ flex: 1, background: danger ? "var(--terracotta)" : undefined, color: danger ? "#fff" : undefined, border: "none" }}
          onClick={onConfirm}
        >
          {confirmLabel}
        </button>
      </div>
    </Modal>
  );
}
