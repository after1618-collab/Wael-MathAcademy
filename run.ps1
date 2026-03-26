# ✅ شغّل السيرفر في الخلفية
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd 'D:\wael mcp'; uvicorn mcp_server:app --reload" -WindowStyle Normal

# ✅ استنى ثانيتين عشان السيرفر يبدأ
Start-Sleep -Seconds 3

# ✅ شغّل Flutter
cd "D:\wael mcp"
flutter run -d chrome