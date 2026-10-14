import os
import tempfile
import pytest

@pytest.fixture()
def client(monkeypatch):
    fd, path = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    monkeypatch.setenv('DATABASE_PATH', path)
    import app as app_module
    app_module.DB_PATH = path
    app_module.init_db()
    app_module.app.config['TESTING'] = True
    with app_module.app.test_client() as client:
        yield client
    os.unlink(path)

def test_health(client):
    response = client.get('/health')
    assert response.status_code == 200
    assert response.json['status'] == 'ok'

def test_create_list_complete_delete(client):
    created = client.post('/api/tasks', json={'title': 'Learn Kubernetes'})
    assert created.status_code == 201
    task = created.json
    assert task['title'] == 'Learn Kubernetes'
    task_id = task['id']
    assert len(client.get('/api/tasks').json) == 1
    updated = client.patch(f'/api/tasks/{task_id}', json={'completed': True})
    assert updated.status_code == 200 and updated.json['completed'] is True
    assert client.delete(f'/api/tasks/{task_id}').status_code == 204
    assert client.get('/api/tasks').json == []

def test_reject_empty_title(client):
    assert client.post('/api/tasks', json={'title': ' '}).status_code == 400
