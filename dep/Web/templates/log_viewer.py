import os
from flask import Flask, render_template, jsonify, abort
import subprocess

# --- Configuração ---
LOG_FILE_PATH = '/var/log/nftables.log'
# Por segurança, defina uma lista de logs que podem ser visualizados.
# Isso evita que alguém tente ler outros arquivos do sistema.
ALLOWED_LOGS = {
    'nftables': '/var/log/nftables.log',
    'syslog': '/var/log/syslog', # Exemplo de outro log permitido
}
DEFAULT_LINES = 100 # Número de linhas a serem exibidas por padrão

# --- Aplicação Flask ---
app = Flask(__name__)

# Rota principal que carrega a página HTML
@app.route('/')
def index():
    # O 'render_template' procura por arquivos na pasta 'templates'
    return render_template('index.html')

# API que retorna o conteúdo do log em formato JSON
@app.route('/api/logs/<log_name>')
def get_logs(log_name):
    if log_name not in ALLOWED_LOGS:
        # Se o log solicitado não estiver na lista permitida, retorna um erro.
        abort(404, description="Log file not found or not allowed.")

    log_path = ALLOWED_LOGS[log_name]

    # Verifica se o arquivo de log existe
    if not os.path.exists(log_path):
        return jsonify({"error": f"Log file not found at {log_path}"}), 404

    try:
        # Usamos 'tail' que é otimizado para ler o final de arquivos grandes.
        # É muito mais eficiente que ler o arquivo inteiro em Python.
        # O subprocesso é executado com 'sudo' pois /var/log geralmente requer privilégios.
        # IMPORTANTE: Veja a nota sobre permissões abaixo!
        command = ['sudo', 'tail', '-n', str(DEFAULT_LINES), log_path]
        
        # Executa o comando e captura a saída
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=True # Lança uma exceção se o comando falhar
        )
        
        # Retorna o conteúdo do log
        return jsonify({"log_name": log_name, "content": result.stdout})

    except subprocess.CalledProcessError as e:
        # Se o comando 'tail' falhar (ex: problema de permissão)
        return jsonify({"error": "Failed to read log file.", "details": e.stderr}), 500
    except Exception as e:
        return jsonify({"error": "An unexpected error occurred.", "details": str(e)}), 500

if __name__ == '__main__':
    # Roda o servidor. 'host="0.0.0.0"' o torna acessível na sua rede local.
    # Não use 'debug=True' em produção.
    app.run(host='0.0.0.0', port=5000)