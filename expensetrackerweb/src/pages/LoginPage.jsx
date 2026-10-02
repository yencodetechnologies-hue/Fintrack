import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { login as loginApi } from "../api.js";
import { useAuth } from "../context/AuthContext.jsx";
import { useToast } from "../context/ToastContext.jsx";
import AuthLayout from "../components/AuthLayout.jsx";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const { login } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();

  async function handleSubmit(e) {
    e.preventDefault();
    if (!email.trim() || !password) {
      showToast("Enter your email and password", "error");
      return;
    }
    setLoading(true);
    const res = await loginApi(email.trim(), password);
    setLoading(false);
    if (res.success && res.user) {
      login(res.user);
      navigate("/companies", { replace: true });
    } else {
      showToast(res.message || "Login failed", "error");
    }
  }

  return (
    <AuthLayout>
      <h1 style={{ fontSize: 24, margin: "0 0 4px" }}>Sign in</h1>
      <p style={{ color: "var(--muted)", fontSize: 13.5, margin: "0 0 24px" }}>
        Welcome back. Enter your details to continue.
      </p>

      <form onSubmit={handleSubmit}>
        <label className="field-label">Email address</label>
        <input
          className="field-input"
          type="email"
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
        />

        <div style={{ height: 14 }} />

        <label className="field-label">Password</label>
        <div style={{ position: "relative" }}>
          <input
            className="field-input"
            type={showPassword ? "text" : "password"}
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Your password"
            style={{ paddingRight: 56 }}
          />
          <button
            type="button"
            onClick={() => setShowPassword((v) => !v)}
            style={{
              position: "absolute",
              right: 10,
              top: "50%",
              transform: "translateY(-50%)",
              background: "none",
              border: "none",
              color: "var(--forest)",
              fontSize: 11.5,
              fontWeight: 700,
            }}
          >
            {showPassword ? "HIDE" : "SHOW"}
          </button>
        </div>

        <button type="submit" className="btn btn-primary btn-block" style={{ marginTop: 22 }} disabled={loading}>
          {loading ? "Signing in..." : "Sign in"}
        </button>

        <p style={{ textAlign: "center", fontSize: 13.5, color: "var(--muted)", marginTop: 18, marginBottom: 0 }}>
          New here? <Link to="/signup" style={{ color: "var(--forest)", fontWeight: 700 }}>Create an account</Link>
        </p>
      </form>
    </AuthLayout>
  );
}
