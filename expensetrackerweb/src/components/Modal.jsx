import { useEffect, useRef } from "react";

// Open popups, newest last: Escape closes only the one on top (e.g. a confirm over Add Expense).
const openModals = [];

// Every popup gets a ✕ in the top-right corner; Escape and clicking outside also close it.
export default function Modal({ onClose, children, maxWidth = 480 }) {
  const id = useRef(Symbol("modal"));
  const closeRef = useRef(onClose);
  useEffect(() => {
    closeRef.current = onClose;
  }, [onClose]);

  useEffect(() => {
    const me = id.current;
    openModals.push(me);
    const onKey = (e) => {
      if (e.key === "Escape" && openModals[openModals.length - 1] === me) closeRef.current?.();
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
      openModals.splice(openModals.indexOf(me), 1);
    };
  }, []);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-sheet" role="dialog" aria-modal="true" style={{ maxWidth }} onClick={(e) => e.stopPropagation()}>
        <button type="button" className="modal-close" aria-label="Close" title="Close" onClick={onClose}>
          ✕
        </button>
        {children}
      </div>
    </div>
  );
}
