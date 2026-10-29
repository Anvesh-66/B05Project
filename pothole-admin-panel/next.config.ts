import type { NextConfig } from "next";

// The browser only ever talks to this app. Requests to /api/* are forwarded to the
// FastAPI backend, so the backend needs no CORS setup and its address stays server-side.
// Exception: /api/send-status-email is handled by Next.js for email notifications.
const backendUrl = process.env.BACKEND_URL ?? "http://127.0.0.1:8000";

const nextConfig: NextConfig = {
  async rewrites() {
    return {
      beforeFiles: [
        // Internal API routes handled by Next.js (not forwarded to backend)
        {
          source: "/api/send-status-email",
          destination: "/api/send-status-email",
        },
      ],
      afterFiles: [
        // All other /api/* routes go to the backend
        { source: "/api/:path*", destination: `${backendUrl}/:path*` },
      ],
    };
  },
};

export default nextConfig;
