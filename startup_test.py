import subprocess, time, sys, os

VENV_PY = r'd:\wael mcp\venv\Scripts\python.exe'
CWD = r'd:\wael mcp'
LOG = r'd:\wael mcp\startup_test.log'

with open(LOG, 'w') as f:
    proc = subprocess.Popen(
        [VENV_PY, '-m', 'uvicorn', 'mcp_server:app', '--host', '127.0.0.1', '--port', '8011'],
        cwd=CWD, stdout=f, stderr=subprocess.STDOUT, text=True
    )
    time.sleep(12)
    try:
        with open(LOG, 'r', encoding='utf-8', errors='replace') as rf:
            content = rf.read()
    except Exception as e:
        content = f'LOG READ ERR {e}'
    print('=== STARTUP LOG (tail) ===')
    print(content[-2500:])
    alive = proc.poll() is None
    print('=== PROCESS ALIVE:', alive, '===')
    # check for success markers
    print('MARKER startup_complete:', 'Application startup complete' in content)
    print('MARKER uvicorn_running:', 'Uvicorn running on' in content)
    print('MARKER traceback:', 'Traceback' in content)
    print('MARKER error:', ('Error' in content) and ('Application startup complete' not in content))
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
    print('TERMINATED')
