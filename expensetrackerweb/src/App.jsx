import { Navigate, Route, Routes } from "react-router-dom";
import { useAuth } from "./context/AuthContext.jsx";
import LoginPage from "./pages/LoginPage.jsx";
import SignupPage from "./pages/SignupPage.jsx";
import CompaniesPage from "./pages/CompaniesPage.jsx";
import DashboardPage from "./pages/DashboardPage.jsx";

function RequireAuth({ children }) {
  const { user } = useAuth();
  if (!user) return <Navigate to="/login" replace />;
  return children;
}

export default function App() {
  const { user } = useAuth();

  return (
    <Routes>
      <Route path="/login" element={user ? <Navigate to="/companies" replace /> : <LoginPage />} />
      <Route path="/signup" element={user ? <Navigate to="/companies" replace /> : <SignupPage />} />
      <Route
        path="/companies"
        element={
          <RequireAuth>
            <CompaniesPage />
          </RequireAuth>
        }
      />
      <Route
        path="/company/:companyId"
        element={
          <RequireAuth>
            <DashboardPage />
          </RequireAuth>
        }
      />
      <Route path="*" element={<Navigate to={user ? "/companies" : "/login"} replace />} />
    </Routes>
  );
}
