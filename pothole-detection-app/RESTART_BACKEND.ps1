# Restart Backend with Email Support
# Run this script after modifying .env file

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Restarting Backend with Email Notifications           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if .env exists
if (Test-Path ".env") {
    Write-Host "✅ Found .env file" -ForegroundColor Green
    
    # Check if SMTP variables are set
    $envContent = Get-Content ".env" -Raw
    if ($envContent -match "SMTP_HOST=\S+" -and $envContent -match "SMTP_USER=\S+" -and $envContent -match "SMTP_PASSWORD=\S+") {
        Write-Host "✅ SMTP variables configured" -ForegroundColor Green
    } else {
        Write-Host "⚠️  SMTP variables may not be properly configured" -ForegroundColor Yellow
        Write-Host "   Make sure .env has SMTP_HOST, SMTP_USER, SMTP_PASSWORD, SMTP_FROM_EMAIL" -ForegroundColor Yellow
    }
} else {
    Write-Host "❌ .env file not found!" -ForegroundColor Red
    Write-Host "   Create it from .env.example and add SMTP configuration" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

Write-Host ""
Write-Host "Starting backend server..." -ForegroundColor Green
Write-Host "Watch for 'Email sent' messages when reports are submitted" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Cyan
Write-Host ""

# Activate virtual environment and start server
& .\.venv\Scripts\Activate.ps1
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
