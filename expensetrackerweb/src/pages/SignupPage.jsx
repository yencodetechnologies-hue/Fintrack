import { useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { signup as signupApi } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import AuthLayout from "../components/AuthLayout.jsx";

export default function SignupPage() {
  const [name, setName] = useState("");
  const [searchParams] = useSearchParams();
  const [email, setEmail] = useState(() => searchParams.get("email") || ""); // prefilled from an invite link
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const { showToast } = useToast();
  const navigate = useNavigate();

  async function handleSubmit(e) {
    e.preventDefault();
    if (!name.trim() || !email.trim() || !password || !confirmPassword) {
      showToast("Fill in all fields", "error");
      return;
    }
    if (password !== confirmPassword) {
      showToast("Passwords do not match", "error");
      return;
    }
    setLoading(true);
    const res = await signupApi(name.trim(), email.trim(), password, confirmPassword);
    setLoading(false);
    if (res.success !== false && !res.message?.toLowerCase().includes("already")) {
      showToast("Account created. Please sign in.");
      navigate("/login", { replace: true });
    } else {
      showToast(res.message || "Sign up failed", "error");
    }
  }

  return (
    <AuthLayout>
      <h1 style={{ fontSize: 22, margin: "0 0 4px" }}>Create your account</h1>
      <p style={{ color: "var(--muted)", fontSize: 14, margin: "0 0 24px" }}>
        Join Expense Tracker in a minute.
      </p>

      <form onSubmit={handleSubmit}>
        <label className="field-label">Full name</label>
        <input className="field-input" value={name} onChange={(e) => setName(e.target.value)} placeholder="Your name" />

        <div style={{ height: 14 }} />
        <label className="field-label">Email address</label>
        <input
          className="field-input"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
        />

        <div style={{ height: 14 }} />
        <label className="field-label">Password</label>
        <input
          className="field-input"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Create a password"
        />

        <div style={{ height: 14 }} />
        <label className="field-label">Confirm password</label>
        <input
          className="field-input"
          type="password"
          value={confirmPassword}
          onChange={(e) => setConfirmPassword(e.target.value)}
          placeholder="Re-enter password"
        />

        <button type="submit" className="btn btn-primary btn-block" style={{ marginTop: 22 }} disabled={loading}>
          {loading ? "Creating account..." : "Sign up"}
        </button>

        <p style={{ textAlign: "center", fontSize: 14, color: "var(--muted)", marginTop: 18, marginBottom: 0 }}>
          Already have an account? <Link to="/login" style={{ color: "var(--forest)", fontWeight: 700 }}>Sign in</Link>
        </p>
      </form>
    </AuthLayout>
  );
}
