#!/bin/bash

##############################################
# Остановка всех сервисов
##############################################

echo "🛑 Остановка всех сервисов..."

# Остановка моделей
tmux kill-session -t tlite 2>/dev/null && echo "✓ T-lite остановлен"
tmux kill-session -t yagpt 2>/dev/null && echo "✓ YandexGPT остановлен"
tmux kill-session -t vikhr 2>/dev/null && echo "✓ Vikhr остановлен"

# Остановка туннелей
tmux kill-session -t tlite-tunnel 2>/dev/null && echo "✓ T-lite tunnel остановлен"
tmux kill-session -t yagpt-tunnel 2>/dev/null && echo "✓ YandexGPT tunnel остановлен"
tmux kill-session -t vikhr-tunnel 2>/dev/null && echo "✓ Vikhr tunnel остановлен"

echo ""
echo "✅ Все сервисы остановлены!"

