import os
import sqlite3
from flask import Flask, jsonify, request
from flask_cors import CORS
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
CORS(app)
PrometheusMetrics(app, path='/metrics', export_defaults=True)
DB_PATH = os.environ.get('DATABASE_PATH', '/tmp/tasks.db')

def connect():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    os.makedirs(os.path.dirname(DB_PATH) or '.', exist_ok=True)
    with connect() as db:
        db.execute('CREATE TABLE IF NOT EXISTS tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0)')
init_db()

def as_task(row):
    return {'id': row['id'], 'title': row['title'], 'completed': bool(row['completed'])}

@app.get('/health')
def health():
    return jsonify({'status': 'ok', 'service': 'student-task-backend'})

@app.get('/api/tasks')
def get_tasks():
    with connect() as db:
        rows = db.execute('SELECT id,title,completed FROM tasks ORDER BY id DESC').fetchall()
    return jsonify([as_task(r) for r in rows])

@app.post('/api/tasks')
def create_task():
    body = request.get_json(silent=True) or {}
    title = str(body.get('title', '')).strip()
    if not title:
        return jsonify({'error': 'title is required'}), 400
    if len(title) > 120:
        return jsonify({'error': 'title must be 120 characters or fewer'}), 400
    with connect() as db:
        cur = db.execute('INSERT INTO tasks(title,completed) VALUES(?,0)', (title,))
        row = db.execute('SELECT id,title,completed FROM tasks WHERE id=?', (cur.lastrowid,)).fetchone()
    return jsonify(as_task(row)), 201

@app.patch('/api/tasks/<int:task_id>')
def update_task(task_id):
    body = request.get_json(silent=True) or {}
    if 'completed' not in body or not isinstance(body['completed'], bool):
        return jsonify({'error': 'completed must be true or false'}), 400
    with connect() as db:
        cur = db.execute('UPDATE tasks SET completed=? WHERE id=?', (int(body['completed']), task_id))
        if cur.rowcount == 0:
            return jsonify({'error': 'task not found'}), 404
        row = db.execute('SELECT id,title,completed FROM tasks WHERE id=?', (task_id,)).fetchone()
    return jsonify(as_task(row))

@app.delete('/api/tasks/<int:task_id>')
def delete_task(task_id):
    with connect() as db:
        cur = db.execute('DELETE FROM tasks WHERE id=?', (task_id,))
    if cur.rowcount == 0:
        return jsonify({'error': 'task not found'}), 404
    return '', 204

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', '5000')))
