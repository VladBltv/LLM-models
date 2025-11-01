#!/bin/bash

##############################################
# Быстрый запуск всех сервисов
##############################################

echo "🚀 Запуск LLM сервисов..."

# Создание директории логов
mkdir -p logs

# Запуск моделей (раскомментируй нужные)
echo "Запуск T-lite..."
tmux new -s tlite -d "python app_tlite.py 2>&1 | tee logs/tlite.log"

echo "Запуск YandexGPT..."
tmux new -s yagpt -d "python app_yagpt.py 2>&1 | tee logs/yagpt.log"

echo "Запуск Vikhr..."
tmux new -s vikhr -d "python app_vikhr.py 2>&1 | tee logs/vikhr.log"

# Ожидание загрузки
echo "⏳ Ожидание загрузки моделей (30 сек)..."
sleep 30

# Запуск туннелей
echo "🌐 Создание туннелей..."
tmux new -s tlite-tunnel -d "cloudflared tunnel --url http://localhost:8083 2>&1 | tee logs/tlite-tunnel.log"
tmux new -s yagpt-tunnel -d "cloudflared tunnel --url http://localhost:8081 2>&1 | tee logs/yagpt-tunnel.log"
tmux new -s vikhr-tunnel -d "cloudflared tunnel --url http://localhost:8082 2>&1 | tee logs/vikhr-tunnel.log"

sleep 5

# Вывод URL
echo ""
echo "✅ Сервисы запущены!"
echo ""
echo "📝 Получить URL туннелей:"
echo "   ./get_urls.sh"
echo ""
echo "📊 Посмотреть статус:"
echo "   tmux ls"

