// "+ Add company or person…" in the borrow pickers: a company needs a name and GSTIN, a person a name (phone optional).
export function NewLenderFields({ kind = "company", onKind, name, onName, gstin, onGstin, phone, onPhone }) {
  const person = kind === "person";
  return (
    <>
      <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
        {["company", "person"].map((k) => (
          <button key={k} type="button" className={`btn btn-sm ${kind === k ? "btn-dark" : "btn-outline"}`} style={{ flex: 1 }} onClick={() => onKind(k)}>
            {k === "company" ? "Company" : "Person"}
          </button>
        ))}
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginTop: 8 }}>
        <input className="field-input" placeholder={person ? "Person's name *" : "Company name *"} value={name || ""} onChange={(e) => onName(e.target.value)} />
        {person ? (
          <input className="field-input" placeholder="Phone (optional)" inputMode="tel" value={phone || ""} onChange={(e) => onPhone(e.target.value)} />
        ) : (
          <input className="field-input" placeholder="GSTIN *" value={gstin || ""} onChange={(e) => onGstin(e.target.value.toUpperCase())} />
        )}
      </div>
    </>
  );
}

// what to send as `newCompany`, or the message to show when something required is missing
export function newLenderPayload(kind, name, gstin, phone) {
  if (kind === "person") {
    if (!String(name || "").trim()) return { error: "Enter the person's name" };
    return { newCompany: { kind: "person", name: name.trim(), phone: String(phone || "").trim() } };
  }
  if (!String(name || "").trim() || !String(gstin || "").trim()) return { error: "Enter the new company's name and GSTIN" };
  return { newCompany: { name: name.trim(), gstin: gstin.trim().toUpperCase() } };
}
