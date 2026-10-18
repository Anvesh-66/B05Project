import { InboxIcon, PinIcon } from "@/components/Icons";
import { formatDate, mapUrl, type ReportStatus, type ReportSummary, STATUS_LABELS } from "@/lib/api";
import { type Level, LEVEL_LABELS, riskLevel } from "@/lib/labels";

interface Props {
  reports: ReportSummary[];
  loading: boolean;
  /** True when a filter or search is active; changes the empty message. */
  filtered: boolean;
  onChangeStatus: (id: number, status: ReportStatus) => void;
  onView: (id: number) => void;
}

const SKELETON_ROWS = 4;

export default function ReportsTable({ reports, loading, filtered, onChangeStatus, onView }: Props) {
  if (reports.length === 0 && !loading) {
    return (
      <div className="empty">
        <InboxIcon />
        <b>{filtered ? "No reports match" : "No reports yet"}</b>
        <span>
          {filtered
            ? "Try a different search, status or risk level."
            : "Reports submitted from the mobile app will appear here."}
        </span>
      </div>
    );
  }

  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Reported</th>
            <th>Reporter</th>
            <th>Potholes</th>
            <th>Risk</th>
            <th>Location</th>
            <th>Status</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {reports.length === 0
            ? Array.from({ length: SKELETON_ROWS }, (_, i) => (
                <tr key={i} aria-hidden="true">
                  {[30, 120, 150, 60, 70, 110, 90, 50].map((width, j) => (
                    <td key={j}>
                      <span className="skeleton" style={{ width }} />
                    </td>
                  ))}
                </tr>
              ))
            : reports.map((report) => (
                <tr key={report.id}>
                  <td className="id" data-label="Report">
                    #{report.id}
                  </td>
                  <td className="nowrap" data-label="Reported">
                    {formatDate(report.created_at)}
                  </td>
                  <td className="reporter wide" data-label="Reporter">
                    <b>{report.reporter_name}</b>
                    <span>{report.reporter_email}</span>
                  </td>
                  <td className="num" data-label="Potholes">
                    {report.detection_count}
                    <span className="dim"> · {report.severe_count} high</span>
                  </td>
                  <td data-label="Risk">
                    <LevelBadge level={riskLevel(report.risk)} />
                  </td>
                  <td className="wide" data-label="Location">
                    <LocationLink latitude={report.latitude} longitude={report.longitude} />
                  </td>
                  <td className="wide" data-label="Status">
                    <select
                      className="status-select"
                      data-status={report.status}
                      aria-label={`Status of report ${report.id}`}
                      value={report.status}
                      onChange={(e) => onChangeStatus(report.id, e.target.value as ReportStatus)}
                    >
                      {Object.entries(STATUS_LABELS).map(([value, label]) => (
                        <option key={value} value={value}>
                          {label}
                        </option>
                      ))}
                    </select>
                  </td>
                  <td className="actions">
                    <button className="btn" type="button" onClick={() => onView(report.id)}>
                      View
                    </button>
                  </td>
                </tr>
              ))}
        </tbody>
      </table>
    </div>
  );
}

/** Low / Medium / High pill, for report risk and for pothole severity. */
export function LevelBadge({ level, suffix }: { level: Level; suffix?: string }) {
  return (
    <span className={`level level-${level}`}>
      {LEVEL_LABELS[level]}
      {suffix ? ` ${suffix}` : ""}
    </span>
  );
}

export function LocationLink({ latitude, longitude }: { latitude: number | null; longitude: number | null }) {
  if (latitude === null || longitude === null) return <span className="dim">Not attached</span>;
  return (
    <a
      className="location"
      href={mapUrl(latitude, longitude)}
      target="_blank"
      rel="noopener noreferrer"
      title="Open in OpenStreetMap"
    >
      <PinIcon width={15} height={15} />
      {latitude.toFixed(5)}, {longitude.toFixed(5)}
    </a>
  );
}
