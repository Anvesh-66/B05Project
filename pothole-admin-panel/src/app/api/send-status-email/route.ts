import { NextRequest, NextResponse } from "next/server";
import { sendStatusChangeEmail } from "@/lib/email";
import type { ReportDetail, ReportStatus } from "@/lib/api";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { toEmail, userName, report, oldStatus, newStatus } = body as {
      toEmail: string;
      userName: string;
      report: ReportDetail;
      oldStatus: ReportStatus;
      newStatus: ReportStatus;
    };

    if (!toEmail || !userName || !report || !oldStatus || !newStatus) {
      return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
    }

    const success = await sendStatusChangeEmail(toEmail, userName, report, oldStatus, newStatus);

    return NextResponse.json({ success });
  } catch (error) {
    console.error("Error sending email:", error);
    return NextResponse.json({ error: "Failed to send email" }, { status: 500 });
  }
}
