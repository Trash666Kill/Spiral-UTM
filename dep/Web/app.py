import os
import json
import subprocess
from flask import Flask, jsonify, render_template, request, redirect, url_for, flash
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from flask_session import Session

# --- Configuração da Aplicação ---
app = Flask(__name__)
app.config['SECRET_KEY'] = 'uma-chave-secreta-muito-dificil-de-adivinhar'

# --- Configuração de Sessões de Servidor ---
app.config['SESSION_TYPE'] = 'filesystem'
app.config['SESSION_PERMANENT'] = False
app.config['SESSION_USE_SIGNER'] = True
app.config['SESSION_FILE_DIR'] = './flask_session'
Session(app)

# --- Arquivo de Configuração de Usuário ---
CONFIG_FILE = 'config.json'
users_db = {}

def load_config():
    global users_db
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            users_db = json.load(f)
    else:
        users_db = {}

def save_config():
    with open(CONFIG_FILE, 'w') as f:
        json.dump(users_db, f, indent=4)

# --- Gerenciamento de Login ---
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'
login_manager.login_message = "Por favor, faça o login para acessar esta página."

class User(UserMixin):
    def __init__(self, id, name):
        self.id = id
        self.name = name

@login_manager.user_loader
def load_user(user_id):
    if user_id in users_db:
        return User(id=user_id, name=users_db[user_id]['name'])
    return None

# --- Verificação de Setup Inicial ---
@app.before_request
def check_for_setup():
    if request.endpoint == 'setup' or request.endpoint == 'static':
        return
    if not os.path.exists(CONFIG_FILE):
        return redirect(url_for('setup'))

# --- Rotas da Aplicação ---

@app.route('/setup', methods=['GET', 'POST'])
def setup():
    if os.path.exists(CONFIG_FILE):
        return redirect(url_for('login'))

    if request.method == 'POST':
        password = request.form['password']
        confirm_password = request.form['confirm_password']

        if not password or len(password) < 8:
            flash('A senha deve ter pelo menos 8 caracteres.', 'error')
            return render_template('setup.html')
        if password != confirm_password:
            flash('As senhas não coincidem.', 'error')
            return render_template('setup.html')
        
        users_db['admin'] = {
            'password_hash': generate_password_hash(password),
            'name': 'Administrador'
        }
        save_config()
        
        flash('Senha do administrador configurada com sucesso! Por favor, faça o login.', 'success')
        return redirect(url_for('login'))

    return render_template('setup.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        user_data = users_db.get(username)

        if user_data and check_password_hash(user_data['password_hash'], password):
            user = User(id=username, name=user_data['name'])
            login_user(user)
            return redirect(url_for('dashboard'))
        else:
            flash('Usuário ou senha inválidos.', 'error')

    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('login'))

@app.route('/')
@login_required
def dashboard():
    return render_template('index.html', allowed_logs=ALLOWED_LOGS.keys())

# --- API de Logs ---
ALLOWED_LOGS = {
    'nftables': '/var/log/nftables.log',
    'syslog': '/var/log/syslog',
    'auth': '/var/log/auth.log',
}
DEFAULT_LINES = 150

@app.route('/api/logs/<log_name>')
@login_required
def get_logs(log_name):
    if log_name not in ALLOWED_LOGS:
        return jsonify({"error": "Log file not allowed."}), 404
    
    log_path = ALLOWED_LOGS[log_name]
    if not os.path.exists(log_path):
        return jsonify({"error": f"Log file not found at {log_path}"}), 404

    try:
        command = ['sudo', 'tail', '-n', str(DEFAULT_LINES), log_path]
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        return jsonify({"log_name": log_name, "content": result.stdout})
    except Exception as e:
        return jsonify({"error": "Failed to read log file.", "details": str(e)}), 500

# --- Ponto de Entrada ---
if __name__ == '__main__':
    load_config()
    app.run(host='0.0.0.0', port=5000)