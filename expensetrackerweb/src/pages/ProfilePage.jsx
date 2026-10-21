import { Link } from "react-router-dom";
import AppLayout from "../components/AppLayout.jsx";
import { useAuth } from "../context/AuthContext.jsx";
import ConfirmDialog from "../components/ConfirmDialog.jsx";
import { useState } from "react";

export default function ProfilePage() {
  const { user, logout } = useAuth();
  const [confirmingLogout, setConfirmingLogout] = useState(false);

  return (
    <AppLayout title="Profile">
      <main className="container" style={{ paddingTop: 48, paddingBottom: 64 }}>
        <div className="eyebrow" style={{ marginBottom: 10 }}>Account</div>
        <h1 style={{ color: "#fff", fontSize: 36, margin: "0 0 10px" }}>Your profile</h1>
        <p style={{ color: "rgba(255,255,255,0.68)", margin: "0 0 28px", maxWidth: 520 }}>
          Your account details.
        </p>

        <section className="card profile-card">
          <div className="profile-avatar" aria-hidden="true">{(user.name || user.email || "U").trim()[0]?.toUpperCase()}</div>
          <div className="profile-detail">
            <span className="field-label">Name</span>
            <strong>{user.name || "—"}</strong>
          </div>
          <div className="profile-detail">
            <span className="field-label">Contact details</span>
            <strong>{user.email || "—"}</strong>
          </div>
          <div className="profile-actions">
            <Link to="/companies" className="btn btn-outline">Back to expenses</Link>
            <button type="button" className="btn btn-primary" onClick={() => setConfirmingLogout(true)}>Log out</button>
          </div>
        </section>
      </main>
      {confirmingLogout && <ConfirmDialog title="Log out?" message="You'll need to sign in again to access your account." confirmLabel="Log out" danger onConfirm={logout} onCancel={() => setConfirmingLogout(false)} />}
    </AppLayout>
  );
}
