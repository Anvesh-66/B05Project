# Pothole Admin Panel

Next.js web app for admins to review pothole reports:

- Sign in with an admin account
- Counts of total, pending, in-review, resolved and high-risk reports
- Bar chart of reports by risk level
- Reports table with search (report number, reporter name or email), filters by status and risk, and newest/oldest sorting
- Map of every report that has a location, coloured by status and sized by risk; click a dot to open the report
- Change a report's status
- Open a report to see the annotated or original photo, its detections and a map link
- Delete a report

It has no database of its own. All data comes from the backend in `../pothole-detection-app/`.

## Setup

Needs Node.js 20 or newer.

```powershell
cd pothole-admin-panel
npm install
```

## Run

1. Start the backend and create an admin account (see `../pothole-detection-app/README.md`).
2. Start the panel:

   ```powershell
   npm run dev
   ```

3. Open <http://localhost:3000> and sign in.

For a production build: `npm run build`, then `npm start`.

## Backend address

The browser only talks to this app. Requests to `/api/*` are forwarded to the backend
(see `next.config.ts`), which is why the backend needs no CORS configuration.

The backend address defaults to `http://127.0.0.1:8000`. To change it, copy `.env.example`
to `.env.local` and edit `BACKEND_URL`. It is read when the app is built or started in dev
mode, so restart (or rebuild) after changing it.

## Layout

```
next.config.ts              /api proxy to the backend
src/app/layout.tsx          Page shell and metadata
src/app/page.tsx            Restores the session; shows login or the dashboard
src/app/globals.css         Styles
src/components/LoginForm.tsx
src/components/Dashboard.tsx      Stats, filters, loading and status changes
src/components/ReportsTable.tsx
src/components/ReportDialog.tsx   Photo, details, delete
src/lib/api.ts              Backend calls and types
```

## Notes

- The sign-in token is kept in the browser tab's session storage, so closing the tab signs you out.
- Accounts created in the mobile app are normal users and cannot sign in here.
