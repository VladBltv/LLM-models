#!/bin/bash

##############################################
# Настройки
##############################################

# URL твоего GitHub репозитория (укажи свой!)
GIT_REPO="https://github.com/твой-username/llm-models.git"

# Выбираем модель из аргумента (по умолчанию tlite)
MODEL=${1:-tlite}

# Определяем рабочую директорию
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Если существует /workspace - используем её (RunPod)
if [ -d "/workspace" ]; then
    PROJECT_DIR="/workspace"
elif [ -d "$SCRIPT_DIR/workspace" ]; then
    PROJECT_DIR="$SCRIPT_DIR/workspace"
elif [ -f "$SCRIPT_DIR/app_tlite.py" ]; then
    PROJECT_DIR="$SCRIPT_DIR"
else
    # Создаём workspace если нет
    echo "📁 Создание директории workspace..."
    mkdir -p "$SCRIPT_DIR/workspace"
    PROJECT_DIR="$SCRIPT_DIR/workspace"
fi

echo "📂 Рабочая директория: $PROJECT_DIR"

# Проверяем что директория существует
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Не удалось создать/найти рабочую директорию"
    exit 1
fi

cd "$PROJECT_DIR" || exit 1

# Проверяем есть ли файлы проекта
if [ ! -f "app_tlite.py" ]; then
    echo "⚠️  Файлы проекта не найдены"
    
    # Если указан репозиторий - клонируем
    if [ -n "$GIT_REPO" ] && [ "$GIT_REPO" != "https://github.com/твой-username/llm-models.git" ]; then
        echo "📥 Клонирование из GitHub..."
        echo "   Репозиторий: $GIT_REPO"
        echo ""
        
        # Клонируем во временную папку, потом переносим файлы
        TMP_DIR=$(mktemp -d)
        if git clone "$GIT_REPO" "$TMP_DIR" 2>&1; then
            # Копируем файлы только если их нет
            echo "📋 Копирование файлов проекта..."
            for file in "$TMP_DIR"/*; do
                filename=$(basename "$file")
                if [ ! -e "$PROJECT_DIR/$filename" ]; then
                    cp -r "$file" "$PROJECT_DIR/" 2>/dev/null
                else
                    echo "   ⏩ Пропуск $filename (уже существует)"
                fi
            done
            
            rm -rf "$TMP_DIR"
            echo "✅ Репозиторий склонирован!"
            echo ""
        else
            echo "❌ Не удалось клонировать репозиторий"
            echo "💡 Проверь что URL правильный и репозиторий публичный"
            rm -rf "$TMP_DIR"
            exit 1
        fi
    else
        echo "❌ Укажи URL репозитория в переменной GIT_REPO в начале скрипта"
        echo "💡 Например: GIT_REPO=\"https://github.com/user/repo.git\""
        exit 1
    fi
fi

# Финальная проверка
if [ ! -f "app_tlite.py" ]; then
    echo "❌ app_tlite.py не найден даже после клонирования"
    echo "💡 Проверь что в репозитории есть этот файл"
    exit 1
fi

echo "✅ Файлы проекта найдены"
echo ""

# Проверяем и устанавливаем зависимости
if [ -f "requirements.txt" ]; then
    if ! python -c "import fastapi" 2>/dev/null; then
        echo "📦 Установка зависимостей из requirements.txt..."
        echo "   (используем бинарные пакеты для ускорения)"
        echo ""
        pip install --no-build-isolation --prefer-binary -r requirements.txt
        echo ""
        echo "✅ Зависимости установлены!"
        echo ""
    fi
fi

# Определяем параметры модели
case $MODEL in
    tlite)
        SCRIPT="app_tlite.py"
        PORT=8083
        NAME="T-lite"
        ;;
    yagpt)
        SCRIPT="app_yagpt.py"
        PORT=8081
        NAME="YandexGPT"
        ;;
    vikhr)
        SCRIPT="app_vikhr.py"
        PORT=8082
        NAME="Vikhr"
        ;;
    *)
        echo "❌ Неизвестная модель: $MODEL"
        echo "💡 Доступные: tlite, yagpt, vikhr"
        echo "📝 Использование: bash run.sh [tlite|yagpt|vikhr]"
        exit 1
        ;;
esac

# Убиваем старые процессы
pkill -f $SCRIPT 2>/dev/null
pkill -f cloudflared 2>/dev/null
tmux kill-session -t model 2>/dev/null
tmux kill-session -t tunnel 2>/dev/null

# Проверяем что всё установлено
if ! command -v tmux &>/dev/null; then
    echo "📦 Установка tmux..."
    apt-get update -qq && apt-get install -y -qq tmux
fi

if ! command -v cloudflared &>/dev/null; then
    echo "📦 Установка cloudflared..."
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i cloudflared-linux-amd64.deb >/dev/null 2>&1
    rm -f cloudflared-linux-amd64.deb
fi

# Запускаем модель в фоне
echo "⏳ Запуск $NAME..."
echo ""

# Создаём лог файл
mkdir -p /tmp/llm_logs
LOG_FILE="/tmp/llm_logs/${MODEL}.log"
> "$LOG_FILE"  # Очищаем старый лог

# Отключаем hf_transfer если не установлен
export HF_HUB_ENABLE_HF_TRANSFER=0

# Запускаем через tmux с логированием (без буферизации Python)
echo "🔧 Команда: HOST=0.0.0.0 PORT=$PORT python -u $SCRIPT"
tmux new -s model -d "cd $PROJECT_DIR && export HF_HUB_ENABLE_HF_TRANSFER=0 && export HOST=0.0.0.0 && export PORT=$PORT && python -u $SCRIPT 2>&1 | tee $LOG_FILE"
sleep 3

# Проверяем что tmux сессия запустилась
if ! tmux has-session -t model 2>/dev/null; then
    echo "❌ Не удалось запустить tmux сессию!"
    echo "💡 Попробуй запустить напрямую: python $SCRIPT"
    echo "💡 Или посмотри лог: cat $LOG_FILE"
    exit 1
fi

# Ждём готовности и показываем прогресс
PREV_LINE_COUNT=0
echo "📊 Прогресс загрузки:"
echo ""

MAX_WAIT_ITERATIONS=300  # 10 минут максимум (300 * 2 сек)
WAIT_COUNTER=0
SERVER_READY=0

while [ $WAIT_COUNTER -lt $MAX_WAIT_ITERATIONS ]; do
    # Проверяем доступность сервера
    if curl -s --max-time 5 http://localhost:$PORT/docs >/dev/null 2>&1; then
        SERVER_READY=1
        break
    fi
    
    # Проверяем что процесс еще жив
    if ! tmux has-session -t model 2>/dev/null; then
        echo ""
        echo "❌ Сессия tmux 'model' завершилась!"
        echo "💡 Проверь логи: cat $LOG_FILE"
        exit 1
    fi
    
    # Проверяем что файл существует
    if [ -f "$LOG_FILE" ]; then
        CURRENT_LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
        
        # Если есть новые строки
        if [ "$CURRENT_LINE_COUNT" -gt "$PREV_LINE_COUNT" ]; then
            # Показываем только новые строки
            NEW_LINES=$((CURRENT_LINE_COUNT - PREV_LINE_COUNT))
            tail -n "$NEW_LINES" "$LOG_FILE" | while IFS= read -r line; do
                if [ ${#line} -gt 100 ]; then
                    echo "   ${line:0:97}..."
                else
                    echo "   $line"
                fi
            done
            PREV_LINE_COUNT=$CURRENT_LINE_COUNT
        fi
    else
        echo "   ⏳ Ожидание запуска скрипта..."
    fi
    
    WAIT_COUNTER=$((WAIT_COUNTER + 1))
    sleep 2
done

if [ $SERVER_READY -eq 0 ]; then
    echo ""
    echo "⚠️  Сервер не запустился за 10 минут"
    echo "💡 Проверь логи: cat $LOG_FILE"
    echo "💡 Или: tmux attach -t model"
    echo ""
    echo "💡 Продолжаю запуск туннеля, но сервер может быть не готов"
fi

if [ $SERVER_READY -eq 1 ]; then
    echo ""
    echo "✅ Модель готова!"
else
    echo ""
    echo "⚠️  Модель может быть не готова, но продолжаю..."
fi

# Запускаем туннель в фоне
echo "🌐 Создание URL..."

# Проверяем что сервер действительно доступен на нужном порту
echo "🔍 Проверка доступности сервера на порту $PORT..."
if curl -s --max-time 2 http://localhost:$PORT/docs >/dev/null 2>&1; then
    echo "✅ Сервер доступен на порту $PORT"
    
    # Проверяем что это действительно наш FastAPI сервер
    RESPONSE=$(curl -s --max-time 2 http://localhost:$PORT/docs 2>/dev/null)
    if echo "$RESPONSE" | grep -q "swagger\|fastapi\|openapi" 2>/dev/null; then
        echo "✅ Подтверждено: это FastAPI сервер"
    else
        echo "⚠️  Внимание: ответ на /docs не похож на FastAPI Swagger UI"
        echo "   Возможно, на порту $PORT запущен другой сервис"
    fi
else
    echo "⚠️  Сервер не отвечает на порту $PORT"
    echo "💡 Проверь что модель запущена: tmux attach -t model"
    echo "💡 Или проверь логи: cat $LOG_FILE"
    echo ""
    
    # Проверяем что порт занят каким-то процессом
    if command -v lsof &>/dev/null; then
        PORT_PROCESS=$(lsof -i :$PORT 2>/dev/null | tail -n +2)
        if [ -n "$PORT_PROCESS" ]; then
            echo "ℹ️  На порту $PORT запущен процесс:"
            echo "   $PORT_PROCESS"
        fi
    fi
    
    echo "⚠️  Запускаю туннель, но сервер может быть не готов"
fi

mkdir -p /tmp/llm_logs
echo "🔗 Создание туннеля для http://localhost:$PORT"
tmux new -s tunnel -d "cloudflared tunnel --url http://127.0.0.1:$PORT 2>&1 | tee /tmp/llm_logs/${MODEL}-tunnel.log"

# Ждём URL (до 60 секунд)
echo "⏳ Ожидание Cloudflare туннеля..."
sleep 3  # Даём cloudflared время на запуск

URL=""
COUNTER=0
MAX_TUNNEL_WAIT=30  # 60 секунд максимум

while [ -z "$URL" ] && [ $COUNTER -lt $MAX_TUNNEL_WAIT ]; do
    # Проверяем что туннель еще запущен
    if ! tmux has-session -t tunnel 2>/dev/null; then
        echo ""
        echo "⚠️  Сессия туннеля завершилась!"
        echo "💡 Проверь логи: cat /tmp/llm_logs/${MODEL}-tunnel.log"
        break
    fi
    
    # Пробуем получить из tmux
    URL=$(tmux capture-pane -t tunnel -p 2>/dev/null | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)
    
    # Если не получилось, пробуем из лог-файла
    if [ -z "$URL" ] && [ -f "/tmp/llm_logs/${MODEL}-tunnel.log" ]; then
        URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/llm_logs/${MODEL}-tunnel.log | head -1)
    fi
    
    if [ -z "$URL" ]; then
        echo -n "."
    fi
    COUNTER=$((COUNTER + 1))
    sleep 2
done
echo ""

if [ -z "$URL" ]; then
    echo ""
    echo "⚠️  Не удалось автоматически получить URL"
    echo "💡 Проверь логи: cat /tmp/llm_logs/${MODEL}-tunnel.log | grep https"
    echo "💡 Или: tmux attach -t tunnel"
    echo ""
    # Не выходим, чтобы показать что сервер работает
else
    # Проверяем что URL действительно ведет на наш сервис
    echo ""
    echo "🔍 Проверка доступности через туннель..."
    if curl -s --max-time 10 "$URL/docs" >/dev/null 2>&1; then
        echo "✅ Туннель работает корректно!"
    else
        echo "⚠️  Туннель создан, но не отвечает на /docs"
        echo "💡 Проверь что сервер запущен на порту $PORT"
        echo "💡 Локальная проверка: curl http://localhost:$PORT/docs"
    fi
fi

echo ""
echo "================================"
echo "✅ $NAME ГОТОВ!"
echo "================================"

if [ -n "$URL" ]; then
    echo "🌐 Публичный URL:"
    echo "   $URL"
    echo ""
    echo "📝 Swagger UI (API документация):"
    echo "   $URL/docs"
    echo ""
    echo "🔧 API эндпоинт:"
    case $MODEL in
        yagpt)
            echo "   POST $URL/generate_yagpt"
            ;;
        vikhr)
            echo "   POST $URL/generate_vikhr"
            ;;
        tlite)
            echo "   POST $URL/generate_tlite"
            ;;
    esac
    echo ""
    echo "⚠️  Важно: Если открывается страница RunPod вместо Swagger UI,"
    echo "   проверь что туннель проксирует порт $PORT:"
    echo "   tmux attach -t tunnel"
    echo "   или: cat /tmp/llm_logs/${MODEL}-tunnel.log"
else
    echo "🌐 Локальный URL:"
    echo "   http://localhost:$PORT/docs"
    echo ""
    echo "💡 Для публичного URL проверь:"
    echo "   cat /tmp/llm_logs/${MODEL}-tunnel.log | grep https"
fi

echo "================================"
echo ""
echo "💡 Полезные команды:"
echo "   • Остановить:        bash /workspace/stop.sh"
echo "   • Посмотреть логи:   tmux attach -t model"
echo "   • Получить URL:      cat /tmp/llm_logs/${MODEL}-tunnel.log | grep https"
echo "   • Диагностика:       bash /workspace/check_tunnel.sh $MODEL"
echo ""

