export type ReportStatus = "pending" | "in_review" | "resolved";
export type RiskLevel = "LOW" | "MED" | "HIGH";

export const STATUS_LABELS: Record<ReportStatus, string> = {
  pending: "Pending",
  in_review: "In review",
  resolved: "Resolved",
};

export interface User {
  id: number;
  name: string;
  email: string;
  role: string;
}

export interface Detection {
  class_name: string;
  confidence: number;
  severity: string;
  /** Relative depth below the surrounding road (0 = flat), not centimetres. Null when not measured. */
  depth_index: number | null;
  /** The pothole looks filled with water, so its depth was not measured. */
  has_water: boolean;
}

export interface ReportSummary {
  id: number;
  status: ReportStatus;
  risk: RiskLevel;
  detection_count: number;
  severe_count: number;
  latitude: number | null;
  longitude: number | null;
  created_at: string;
  resolved_at: string | null;
  reporter_name: string;
  reporter_email: string;
}

export interface ReportDetail extends ReportSummary {
  detections: Detection[];
}

export interface Stats {
  total: number;
  pending: number;
  in_review: number;
  resolved: number;
  high_risk: number;
  medium_risk: number;
  low_risk: number;
}

export type ReportOrder = "newest" | "oldest";

export interface ReportFilters {
  status: ReportStatus | "";
  risk: RiskLevel | "";
  /** Report number, or part of the reporter's name or email. */
  search: string;
  order: ReportOrder;
}

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
  ) {
    super(message);
  }
}

export const PAGE_SIZE = 50;

/** Calls the backend through this app's /api proxy (see next.config.ts). */
async function request(path: string, token: string | null, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  if (token) headers.set("Authorization", `Bearer ${token}`);
  if (init.body) headers.set("Content-Type", "application/json");

  let response: Response;
  try {
    response = await fetch(`/api${path}`, { ...init, headers });
  } catch {
    throw new ApiError("Cannot reach the server.", 0);
  }
  if (response.ok) return response;

  let detail = response.status >= 500 ? "The backend is not responding. Is it running?" : response.statusText;
  try {
    const body = await response.json();
    if (typeof body.detail === "string") detail = body.detail;
  } catch {
    // Not JSON; keep the fallback message.
  }
  throw new ApiError(detail, response.status);
}

export async function login(email: string, password: string): Promise<{ token: string; user: User }> {
  const response = await request("/auth/login", null, {
    method: "POST",
    body: JSON.stringify({ email, password }),
  });
  const data = await response.json();
  return { token: data.access_token, user: data.user };
}

export async function fetchMe(token: string): Promise<User> {
  return (await request("/auth/me", token)).json();
}

export async function fetchStats(token: string): Promise<Stats> {
  return (await request("/stats", token)).json();
}

export async function fetchReports(token: string, filters: ReportFilters, offset: number): Promise<ReportSummary[]> {
  const params = new URLSearchParams({ limit: String(PAGE_SIZE), offset: String(offset) });
  if (filters.status) params.set("status", filters.status);
  if (filters.risk) params.set("risk", filters.risk);
  if (filters.search) params.set("q", filters.search);
  params.set("order", filters.order);
  return (await request(`/reports?${params}`, token)).json();
}

const MAP_PAGE_SIZE = 200;
const MAP_MAX_REPORTS = 1000;

/** The newest reports that have coordinates, for the map. */
export async function fetchLocatedReports(token: string): Promise<ReportSummary[]> {
  const located: ReportSummary[] = [];
  while (located.length < MAP_MAX_REPORTS) {
    const params = new URLSearchParams({
      located: "true",
      limit: String(MAP_PAGE_SIZE),
      offset: String(located.length),
    });
    const page: ReportSummary[] = await (await request(`/reports?${params}`, token)).json();
    located.push(...page);
    if (page.length < MAP_PAGE_SIZE) break;
  }
  return located;
}

export async function fetchReport(token: string, id: number): Promise<ReportDetail> {
  return (await request(`/reports/${id}`, token)).json();
}

export async function updateStatus(token: string, id: number, status: ReportStatus): Promise<ReportDetail> {
  const response = await request(`/reports/${id}`, token, {
    method: "PATCH",
    body: JSON.stringify({ status }),
  });
  return response.json();
}

export async function deleteReport(token: string, id: number): Promise<void> {
  await request(`/reports/${id}`, token, { method: "DELETE" });
}

/** Report photos need the auth header, so they are fetched as blobs rather than used as <img src>. */
export async function fetchReportImage(token: string, id: number, kind: "annotated" | "original"): Promise<Blob> {
  return (await request(`/reports/${id}/image?kind=${kind}`, token)).blob();
}

export function formatDate(iso: string | null): string {
  return iso ? new Date(iso).toLocaleString() : "—";
}

export function mapUrl(latitude: number, longitude: number): string {
  return `https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=18/${latitude}/${longitude}`;
}
