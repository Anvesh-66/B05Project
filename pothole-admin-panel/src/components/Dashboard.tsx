"use client";

import { type CSSProperties, type ReactNode, useCallback, useEffect, useRef, useState } from "react";

import {
  AlertIcon,
  CheckIcon,
  ClipboardIcon,
  ClockIcon,
  LogoutIcon,
  RefreshIcon,
  RoadIcon,
  SearchIcon,
} from "@/components/Icons";
import ReportDialog from "@/components/ReportDialog";
import ReportsMap from "@/components/ReportsMap";
import ReportsTable from "@/components/ReportsTable";
import {
  ApiError,
  fetchReports,
  fetchStats,
  PAGE_SIZE,
  type ReportFilters,
  type ReportOrder,
  type ReportStatus,
  type ReportSummary,
  type RiskLevel,
  type Stats,
  STATUS_LABELS,
  updateStatus,
  type User,
} from "@/lib/api";
import { initials } from "@/lib/labels";

interface Props {
  token: string;
  user: User;
  onSignOut: () => void;
}

const EMPTY_STATS: Stats = {
  total: 0,
  pending: 0,
  in_review: 0,
  resolved: 0,
  high_risk: 0,
  medium_risk: 0,
  low_risk: 0,
};

const SEARCH_DELAY_MS = 300;

export default function Dashboard({ token, user, onSignOut }: Props) {
  const [stats, setStats] = useState<Stats>(EMPTY_STATS);
  const [reports, setReports] = useState<ReportSummary[]>([]);
  const [filters, setFilters] = useState<ReportFilters>({ status: "", risk: "", search: "", order: "newest" });
  const [searchText, setSearchText] = useState("");
  const [view, setView] = useState<"reports" | "map">("reports");
  // Bumped when a report changes, so the map reloads its points.
  const [mapVersion, setMapVersion] = useState(0);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [openReportId, setOpenReportId] = useState<number | null>(null);

  // Only the newest list request may update the table; older ones are dropped.
  const latestRequest = useRef(0);

  const handleError = useCallback(
    (e: unknown) => {
      if (e instanceof ApiError && e.status === 401) {
        onSignOut();
        return;
      }
      setError(e instanceof Error ? e.message : String(e));
    },
    [onSignOut],
  );

  const refresh = useCallback(async () => {
    const requestId = ++latestRequest.current;
    setLoading(true);
    setError("");
    try {
      const [newStats, firstPage] = await Promise.all([fetchStats(token), fetchReports(token, filters, 0)]);
      if (requestId !== latestRequest.current) return;
      setStats(newStats);
      setReports(firstPage);
      setHasMore(firstPage.length === PAGE_SIZE);
    } catch (e) {
      if (requestId === latestRequest.current) handleError(e);
    } finally {
      if (requestId === latestRequest.current) setLoading(false);
    }
  }, [token, filters, handleError]);

  // Runs on first render and again whenever a filter changes.
  useEffect(() => {
    refresh();
  }, [refresh]);

  // Search as the admin types, but wait for a pause so each keystroke is not a request.
  useEffect(() => {
    const timer = setTimeout(() => {
      const search = searchText.trim();
      setFilters((current) => (current.search === search ? current : { ...current, search }));
    }, SEARCH_DELAY_MS);
    return () => clearTimeout(timer);
  }, [searchText]);

  // Stable identities, so the dialog's effects don't re-run on every dashboard render.
  const closeReport = useCallback(() => setOpenReportId(null), []);
  const reportDeleted = useCallback(() => {
    setOpenReportId(null);
    setMapVersion((v) => v + 1);
    refresh();
  }, [refresh]);

  async function loadMore() {
    const requestId = ++latestRequest.current;
    try {
      const nextPage = await fetchReports(token, filters, reports.length);
      if (requestId !== latestRequest.current) return;
      setReports((current) => [...current, ...nextPage]);
      setHasMore(nextPage.length === PAGE_SIZE);
    } catch (e) {
      handleError(e);
    }
  }

  async function changeStatus(id: number, status: ReportStatus) {
    setError("");
    try {
      const updated = await updateStatus(token, id, status);
      setReports((current) =>
        current.map((r) => (r.id === id ? { ...r, status: updated.status, resolved_at: updated.resolved_at } : r)),
      );
      setStats(await fetchStats(token));
      setMapVersion((v) => v + 1);
    } catch (e) {
      handleError(e);
    }
  }

  return (
    <>
      <header className="topbar">
        <div className="logo">
          <RoadIcon />
        </div>
        <div className="topbar-title">
          <h1>Pothole Admin</h1>
          <span>Road safety reports</span>
        </div>
        <div className="user-chip" title={user.email}>
          <div className="avatar">{initials(user.name)}</div>
          <span>{user.email}</span>
        </div>
        <button className="btn" type="button" onClick={onSignOut}>
          <LogoutIcon />
          Sign out
        </button>
      </header>

      <main className="content">
        <div className="page-head">
          <div>
            <h2>Reports overview</h2>
            <p>Review reported potholes, track their status and mark them resolved.</p>
          </div>
          <div className="segmented" role="group" aria-label="View">
            <button type="button" aria-pressed={view === "reports"} onClick={() => setView("reports")}>
              Reports
            </button>
            <button type="button" aria-pressed={view === "map"} onClick={() => setView("map")}>
              Map
            </button>
          </div>
        </div>

        <div className="stats">
          <StatCard value={stats.total} label="Total reports" accent="var(--blue-light)" icon={<ClipboardIcon />} />
          <StatCard value={stats.pending} label="Pending" accent="var(--medium)" icon={<ClockIcon />} />
          <StatCard value={stats.in_review} label="In review" accent="var(--blue-light)" icon={<SearchIcon />} />
          <StatCard value={stats.resolved} label="Resolved" accent="var(--low)" icon={<CheckIcon />} />
          <StatCard value={stats.high_risk} label="High risk" accent="var(--high)" icon={<AlertIcon />} />
        </div>

        {error && (
          <div className="alert" role="alert">
            <AlertIcon />
            <span>{error}</span>
          </div>
        )}

        <RiskOverview stats={stats} />

        {view === "map" && (
          <ReportsMap token={token} version={mapVersion} onView={setOpenReportId} onError={handleError} />
        )}

        <section className="panel" hidden={view !== "reports"}>
          <div className="toolbar">
            <h3>Reports</h3>
            <div className="search">
              <SearchIcon />
              <input
                type="search"
                placeholder="Search number, name or email"
                aria-label="Search reports"
                value={searchText}
                onChange={(e) => setSearchText(e.target.value)}
              />
            </div>
            <label>
              Status
              <select
                value={filters.status}
                onChange={(e) => setFilters({ ...filters, status: e.target.value as ReportStatus | "" })}
              >
                <option value="">All</option>
                {Object.entries(STATUS_LABELS).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Risk
              <select
                value={filters.risk}
                onChange={(e) => setFilters({ ...filters, risk: e.target.value as RiskLevel | "" })}
              >
                <option value="">All</option>
                <option value="HIGH">High</option>
                <option value="MED">Medium</option>
                <option value="LOW">Low</option>
              </select>
            </label>
            <label>
              Sort
              <select
                value={filters.order}
                onChange={(e) => setFilters({ ...filters, order: e.target.value as ReportOrder })}
              >
                <option value="newest">Newest first</option>
                <option value="oldest">Oldest first</option>
              </select>
            </label>
            <button className="btn" type="button" onClick={refresh} disabled={loading}>
              <RefreshIcon className={loading ? "spin" : undefined} />
              {loading ? "Loading…" : "Refresh"}
            </button>
          </div>

          <ReportsTable
            reports={reports}
            loading={loading}
            filtered={filters.status !== "" || filters.risk !== "" || filters.search !== ""}
            onChangeStatus={changeStatus}
            onView={setOpenReportId}
          />

          {hasMore && (
            <div className="table-foot">
              <button className="btn" type="button" onClick={loadMore}>
                Load more
              </button>
            </div>
          )}
        </section>
      </main>

      {openReportId !== null && (
        <ReportDialog
          key={openReportId}
          token={token}
          reportId={openReportId}
          onClose={closeReport}
          onDeleted={reportDeleted}
          onError={handleError}
        />
      )}
    </>
  );
}

/** How the reports split across risk levels, as one bar per level. */
function RiskOverview({ stats }: { stats: Stats }) {
  const rows = [
    { label: "High", count: stats.high_risk, color: "var(--high)" },
    { label: "Medium", count: stats.medium_risk, color: "var(--medium)" },
    { label: "Low", count: stats.low_risk, color: "var(--low)" },
  ];
  return (
    <section className="panel risk-overview" aria-label="Reports by risk">
      <h3>Reports by risk</h3>
      {rows.map((row) => (
        <div className="risk-row" key={row.label}>
          <span>{row.label}</span>
          <div className="bar">
            <i style={{ width: `${stats.total ? (row.count / stats.total) * 100 : 0}%`, background: row.color }} />
          </div>
          <b>{row.count}</b>
        </div>
      ))}
    </section>
  );
}

function StatCard({ value, label, accent, icon }: { value: number; label: string; accent: string; icon: ReactNode }) {
  return (
    <div className="stat" style={{ "--accent": accent } as CSSProperties}>
      <div className="stat-icon">{icon}</div>
      <div>
        <b>{value}</b>
        <span>{label}</span>
      </div>
    </div>
  );
}
