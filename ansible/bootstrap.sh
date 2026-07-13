#!/bin/bash
set -euo pipefail

echo "==> Iniciando bootstrap del entorno..."

if [ ! -d "venv" ]; then
    echo "--> Creando entorno virtual Python..."
    python3 -m venv venv
fi

echo "--> Activando entorno virtual e instalando dependencias de Python..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "--> Instalando colecciones de Ansible Galaxy..."
ansible-galaxy install -r requirements.yml

echo "==> Bootstrap completado con éxito. Ejecuta 'source venv/bin/activate' para comenzar."