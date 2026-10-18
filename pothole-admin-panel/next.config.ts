import type { NextConfig } from "next";

// The browser only ever talks to this app. Requests to /api/* are forwarded to the
// FastAPI backend, so the backend needs no CORS setup and its address stays server-side.
const backendUrl = process.env.BACKEND_URL ?? "http://127.0.0.1:8000";

const nextConfig: NextConfig = {
  async rewrites() {
    return [{ source: "/api/:path*", destination: `${backendUrl}/:path*` }];
  },
};

export default nextConfig;
