export default function Modal({ onClose, children, maxWidth = 480 }) {
  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-sheet" style={{ maxWidth }} onClick={(e) => e.stopPropagation()}>
        {children}
      </div>
    </div>
  );
}
