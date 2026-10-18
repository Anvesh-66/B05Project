"use client";

import { type FormEvent, useState } from "react";

import { AlertIcon, RoadIcon } from "@/components/Icons";
import { login, type User } from "@/lib/api";

interface Props {
  onSignedIn: (token: string, user: User) => void;
}

export default function LoginForm({ onSignedIn }: Props) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    setBusy(true);
    try {
      const { token, user } = await login(email, password);
      if (user.role !== "admin") {
        setError("This account is not an admin.");
        return;
      }
      onSignedIn(token, user);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="centered">
      <form className="login-card" onSubmit={submit}>
        <div className="logo">
          <RoadIcon width={26} height={26} />
        </div>
        <h1>Pothole Admin</h1>
        <p>Sign in with an admin account to review reports.</p>
        <label className="field">
          Email
          <input
            type="email"
            autoComplete="username"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </label>
        <label className="field">
          Password
          <input
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </label>
        {error && (
          <div className="alert" role="alert">
            <AlertIcon />
            <span>{error}</span>
          </div>
        )}
        <button className="btn btn-primary" type="submit" disabled={busy}>
          {busy ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </div>
  );
}
