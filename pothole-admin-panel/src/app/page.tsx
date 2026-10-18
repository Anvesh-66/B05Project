"use client";

import { useCallback, useEffect, useState } from "react";

import Dashboard from "@/components/Dashboard";
import LoginForm from "@/components/LoginForm";
import { fetchMe, type User } from "@/lib/api";

// The token lives in sessionStorage: it survives a page reload but not closing the tab.
const TOKEN_KEY = "pothole_admin_token";

interface Session {
  token: string;
  user: User;
}

export default function Home() {
  const [session, setSession] = useState<Session | null>(null);
  const [restoring, setRestoring] = useState(true);

  const signOut = useCallback(() => {
    sessionStorage.removeItem(TOKEN_KEY);
    setSession(null);
  }, []);

  const signIn = useCallback((token: string, user: User) => {
    sessionStorage.setItem(TOKEN_KEY, token);
    setSession({ token, user });
  }, []);

  // Resume a session from this tab if its token is still valid and belongs to an admin.
  useEffect(() => {
    const token = sessionStorage.getItem(TOKEN_KEY);
    if (!token) {
      setRestoring(false);
      return;
    }
    let cancelled = false;
    fetchMe(token)
      .then((user) => {
        if (cancelled) return;
        if (user.role === "admin") setSession({ token, user });
        else sessionStorage.removeItem(TOKEN_KEY);
      })
      .catch(() => sessionStorage.removeItem(TOKEN_KEY))
      .finally(() => {
        if (!cancelled) setRestoring(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (restoring) return <div className="centered dim">Loading…</div>;
  if (!session) return <LoginForm onSignedIn={signIn} />;
  return <Dashboard token={session.token} user={session.user} onSignOut={signOut} />;
}
