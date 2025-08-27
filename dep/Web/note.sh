#!/bin/bash

apt-get install python3 python3-pip python3-venv

mkdir web-gui && cd web-gui
python3 -m venv venv
source venv/bin/activate
pip3 install Flask Flask-Login Flask-Session

python3 app.py