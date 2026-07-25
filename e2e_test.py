import subprocess, time, sys, os, json
from dotenv import load_dotenv
load_dotenv(r'd:\wael mcp\.env')
from supabase import create_client

ADMIN_API_KEY = os.getenv('ADMIN_API_KEY')
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_SERVICE_KEY = os.getenv('SUPABASE_SERVICE_KEY')
VENV_PY = r'd:\wael mcp\venv\Scripts\python.exe'
CWD = r'd:\wael mcp'
LOG = r'd:\wael mcp\e2e_test.log'

proc = subprocess.Popen([VENV_PY, '-m', 'uvicorn', 'mcp_server:app', '--host', '127.0.0.1', '--port', '8012'],
                        cwd=CWD, stdout=open(LOG, 'w'), stderr=subprocess.STDOUT, text=True)
time.sleep(12)

import urllib.request, urllib.error
base = 'http://127.0.0.1:8012'

# get a course_id that has lessons (read-only)
sb = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
cid = sb.table('lessons').select('course_id').limit(1).execute().data[0]['course_id']
print('COURSE_ID:', cid)

# call admin endpoint (read-only GET)
req = urllib.request.Request(f'{base}/admin/courses/{cid}/lessons', headers={'x-api-key': ADMIN_API_KEY})
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        code = resp.status
        body = json.loads(resp.read().decode())
    print('HTTP STATUS:', code)
    lessons = body.get('lessons', [])
    print('LESSONS RETURNED:', len(lessons))
    for L in lessons[:3]:
        print('  id=%s type=%s video_path=%s video_url=%s' % (
            L.get('id'), L.get('video_type'), L.get('video_path'), (L.get('video_url') or '')[:55]))
    all_have_url = all(L.get('video_url') for L in lessons)
    all_path_null = all(L.get('video_path') in (None, '') for L in lessons)
    print('ALL_HAVE_LEGACY_VIDEO_URL:', all_have_url)
    print('ALL_VIDEO_PATH_NULL:', all_path_null)
    print('READ_LOGIC_OK (returns legacy url, path null):', all_have_url and all_path_null)
except urllib.error.HTTPError as e:
    print('HTTP ERROR:', e.code, e.read().decode()[:300])
except Exception as e:
    print('ERR:', str(e)[:300])
finally:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except Exception:
        proc.kill()
    print('TERMINATED')
