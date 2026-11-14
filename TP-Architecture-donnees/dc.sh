#!/bin/bash
# Wrapper : docker compose via Windows (bind mounts OK)
set -e
DIR='C:\Users\Utilisateur\Desktop\TP-Architecture-donnees'
cmd.exe /c "cd /d $DIR && docker compose $*"
