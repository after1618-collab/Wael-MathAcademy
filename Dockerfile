FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# الحل العبقري: تشغيل بايثون مباشرة لقراءة البورت وتشغيل uvicorn
CMD ["python", "-c", "import os, uvicorn; port = int(os.environ.get('PORT', 8000)); uvicorn.run('mcp_server:app', host='0.0.0.0', port=port)"]
