"""
Vercel Serverless Function Entry Point for WAEL MCP Backend
------------------------------------------------------------
هذا الملف هو نقطة الدخول لـ Vercel فقط.
لا يحتوي على أي منطق - فقط يستورد app من mcp_server.py الأصلي.
لا تعدّل mcp_server.py بسببه.
"""
import sys
import os

# أضف مسار الجذر (المستوى الأعلى من هذا الملف) إلى Python path
# حتى يتمكن Python من العثور على mcp_server.py في المجلد الأصلي
root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, root_dir)

# استيراد تطبيق FastAPI من الملف الأصلي — لا تعديل في mcp_server.py
from mcp_server import app  # noqa: F401, E402
