# Test Email Configuration for Pothole Detection System
# This script helps verify SMTP settings are working correctly

Write-Host "====================================" -ForegroundColor Cyan
Write-Host "Email Configuration Test" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

# Check if .env file exists
$envFile = ".env"
if (Test-Path $envFile) {
    Write-Host "[OK] Found .env file" -ForegroundColor Green
    
    # Read and display SMTP configuration (without showing passwords)
    $envContent = Get-Content $envFile
    $smtpVars = $envContent | Where-Object { $_ -match "^SMTP_" -and $_ -notmatch "^#" }
    
    if ($smtpVars) {
        Write-Host "`nSMTP Configuration:" -ForegroundColor Yellow
        foreach ($var in $smtpVars) {
            if ($var -match "PASSWORD") {
                $parts = $var -split "=", 2
                Write-Host "  $($parts[0])=********" -ForegroundColor Gray
            } else {
                Write-Host "  $var" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "`n[WARNING] No SMTP variables found in .env" -ForegroundColor Yellow
        Write-Host "Email notifications will NOT be sent." -ForegroundColor Yellow
        Write-Host "`nTo enable emails, add these to .env:" -ForegroundColor Cyan
        Write-Host "  SMTP_HOST=smtp.gmail.com"
        Write-Host "  SMTP_PORT=587"
        Write-Host "  SMTP_USER=your-email@gmail.com"
        Write-Host "  SMTP_PASSWORD=your-app-password"
        Write-Host "  SMTP_FROM_EMAIL=noreply@example.com"
    }
} else {
    Write-Host "[INFO] No .env file found" -ForegroundColor Yellow
    Write-Host "Email notifications will NOT be sent." -ForegroundColor Yellow
    Write-Host "`nTo enable emails:" -ForegroundColor Cyan
    Write-Host "  1. Copy .env.example to .env"
    Write-Host "  2. Edit .env and configure SMTP settings"
    Write-Host "  3. Restart the backend server"
}

Write-Host "`n====================================" -ForegroundColor Cyan
Write-Host "Testing Steps:" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host "1. Start the backend server" -ForegroundColor White
Write-Host "2. Create a test user account" -ForegroundColor White
Write-Host "3. Submit a pothole report" -ForegroundColor White
Write-Host "4. Check email inbox for confirmation" -ForegroundColor White
Write-Host "5. As admin, change report status" -ForegroundColor White
Write-Host "6. Check email for status update" -ForegroundColor White
Write-Host ""
Write-Host "Check server logs for:" -ForegroundColor Yellow
Write-Host "  - 'Email sent to ...' (success)" -ForegroundColor Green
Write-Host "  - 'Email not sent: SMTP not configured' (not configured)" -ForegroundColor Gray
Write-Host "  - 'Failed to send email ...' (error)" -ForegroundColor Red
Write-Host ""

Write-Host "For detailed setup instructions, see:" -ForegroundColor Cyan
Write-Host "  .\scripts\SMTP_SETUP_GUIDE.txt" -ForegroundColor White
Write-Host ""
