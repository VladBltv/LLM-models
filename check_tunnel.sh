#!/bin/bash

# Скрипт для диагностики проблемы с туннелем

MODEL=${1:-yagpt}

case $MODEL in
    tlite)
        PORT=8083
        ;;
    yagpt)
        PORT=8081
        ;;
    vikhr)
        PORT=8082
        ;;
    *)
        echo "❌ Неизвестная модель: $MODEL"
        exit 1
        ;;
esac

echo "=========================================="
echo "🔍 Диагностика для модели: $MODEL"
echo "=========================================="
echo ""

echo "1️⃣ Проверка порта $PORT:"
if lsof -i :$PORT 2>/dev/null | grep -q LISTEN; then
    echo "✅ Порт $PORT занят:"
    lsof -i :$PORT 2>/dev/null
else
    echo "❌ Порт $PORT не занят"
fi
echo ""

echo "2️⃣ Проверка локального сервера:"
if curl -s --max-time 2 http://localhost:$PORT/docs >/dev/null 2>&1; then
    echo "✅ Сервер отвечает на http://localhost:$PORT/docs"
    RESPONSE=$(curl -s http://localhost:$PORT/docs 2>/dev/null)
    if echo "$RESPONSE" | grep -q "swagger\|fastapi\|openapi" 2>/dev/null; then
        echo "✅ Это FastAPI Swagger UI"
    else
        echo "⚠️  Ответ не похож на FastAPI Swagger UI"
        echo "   Первые 200 символов ответа:"
        echo "$RESPONSE" | head -c 200
        echo ""
    fi
else
    echo "❌ Сервер не отвечает на http://localhost:$PORT/docs"
fi
echo ""

echo "3️⃣ Проверка tmux сессий:"
if tmux has-session -t model 2>/dev/null; then
    echo "✅ Сессия 'model' запущена"
else
    echo "❌ Сессия 'model' не найдена"
fi

if tmux has-session -t tunnel 2>/dev/null; then
    echo "✅ Сессия 'tunnel' запущена"
    echo ""
    echo "   Последние строки из туннеля:"
    tmux capture-pane -t tunnel -p | tail -5
else
    echo "❌ Сессия 'tunnel' не найдена"
fi
echo ""

echo "4️⃣ Проверка логов туннеля:"
if [ -f "/tmp/llm_logs/${MODEL}-tunnel.log" ]; then
    echo "✅ Лог файл найден"
    echo ""
    echo "   URL из лога:"
    grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/llm_logs/${MODEL}-tunnel.log | head -1
    echo ""
    echo "   Последние строки лога:"
    tail -10 /tmp/llm_logs/${MODEL}-tunnel.log
else
    echo "❌ Лог файл не найден: /tmp/llm_logs/${MODEL}-tunnel.log"
fi
echo ""

echo "5️⃣ Проверка публичного URL:"
URL=$(tmux capture-pane -t tunnel -p 2>/dev/null | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)
if [ -z "$URL" ] && [ -f "/tmp/llm_logs/${MODEL}-tunnel.log" ]; then
    URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/llm_logs/${MODEL}-tunnel.log | head -1)
fi

if [ -n "$URL" ]; then
    echo "✅ Найден URL: $URL"
    echo ""
    echo "   Проверка доступности /docs:"
    if curl -s --max-time 10 "$URL/docs" >/dev/null 2>&1; then
        echo "✅ URL доступен"
        RESPONSE=$(curl -s "$URL/docs" 2>/dev/null)
        if echo "$RESPONSE" | grep -q "swagger\|fastapi\|openapi" 2>/dev/null; then
            echo "✅ Это FastAPI Swagger UI"
        else
            echo "⚠️  Ответ не похож на FastAPI Swagger UI"
            echo "   Первые 200 символов ответа:"
            echo "$RESPONSE" | head -c 200
            echo ""
            echo "   Это может быть проблема - туннель проксирует не тот сервис"
        fi
    else
        echo "❌ URL не доступен"
    fi
else
    echo "❌ URL не найден"
fi
echo ""

echo "=========================================="
echo "💡 Команды для дальнейшей диагностики:"
echo "   tmux attach -t model    # Логи модели"
echo "   tmux attach -t tunnel   # Логи туннеля"
echo "   cat /tmp/llm_logs/${MODEL}.log | tail -50"
echo "=========================================="

