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
        DEFAULT_PORT=8083
        NAME="T-lite"
        ;;
    yagpt)
        SCRIPT="app_yagpt.py"
        DEFAULT_PORT=8081
        NAME="YandexGPT"
        ;;
    vikhr)
        SCRIPT="app_vikhr.py"
        DEFAULT_PORT=8082
        NAME="Vikhr"
        ;;
    gptoss)
        SCRIPT="app_gptoss.py"
        DEFAULT_PORT=8084
        NAME="GPT-OSS-20B"
        ;;
    deepseek)
        SCRIPT="app_deepseek.py"
        DEFAULT_PORT=8085
        NAME="DeepSeek-R1-Qwen3-8B"
        ;;
    *)
        echo "❌ Неизвестная модель: $MODEL"
        echo "💡 Доступные: tlite, yagpt, vikhr, gptoss, deepseek"
        echo "📝 Использование: bash run.sh [tlite|yagpt|vikhr|gptoss|deepseek]"
        exit 1
        ;;
esac

# Функция проверки свободен ли порт
check_port_free() {
    local port=$1
    
    # Метод 1: через Python (самый надежный)
    if command -v python3 &>/dev/null; then
        python3 -c "
import socket
import sys
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.settimeout(1)
    s.bind(('0.0.0.0', $port))
    s.close()
    sys.exit(0)
except (OSError, socket.error):
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null
        if [ $? -eq 0 ]; then
            return 0
        fi
    fi
    
    # Метод 2: через netcat (nc) если доступен
    if command -v nc &>/dev/null; then
        if ! nc -z localhost $port 2>/dev/null; then
            return 0
        fi
    fi
    
    # Метод 3: через /dev/tcp (встроенный в bash)
    if timeout 1 bash -c "echo > /dev/tcp/localhost/$port" 2>/dev/null; then
        return 1  # Порт занят
    else
        return 0  # Порт свободен
    fi
}

# Функция поиска свободного порта
find_free_port() {
    local start_port=$1
    local max_attempts=50  # Увеличил количество попыток
    
    # Сначала пробуем исходный порт
    if check_port_free $start_port; then
        echo $start_port
        return 0
    fi
    
    echo "   [INFO] Порт $start_port занят, ищу свободный порт..." >&2
    
    # Ищем свободный порт начиная с исходного (пробуем +1, +2, +3...)
    for offset in $(seq 1 $max_attempts); do
        test_port=$((start_port + offset))
        if [ $test_port -le 65535 ]; then
            if check_port_free $test_port; then
                echo "   [INFO] Найден свободный порт: $test_port" >&2
                echo $test_port
                return 0
            fi
        fi
    done
    
    # Если не нашли в диапазоне выше, пробуем ниже (пробуем -1, -2, -3...)
    for offset in $(seq 1 $max_attempts); do
        test_port=$((start_port - offset))
        if [ $test_port -ge 1024 ]; then  # Минимум 1024 (непривилегированные порты)
            if check_port_free $test_port; then
                echo "   [INFO] Найден свободный порт: $test_port" >&2
                echo $test_port
                return 0
            fi
        fi
    done
    
    # Последняя попытка: пробуем случайные порты в диапазоне 8000-9000
    echo "   [INFO] Пробую случайные порты в диапазоне 8000-9000..." >&2
    for i in $(seq 1 20); do
        test_port=$((8000 + RANDOM % 1000))
        if check_port_free $test_port; then
            echo "   [INFO] Найден свободный порт: $test_port" >&2
            echo $test_port
            return 0
        fi
    done
    
    return 1
}

# Проверяем, указан ли порт через переменную окружения
if [ -n "$PORT" ]; then
    echo "ℹ️  Использую порт из переменной окружения: $PORT"
    if ! check_port_free $PORT; then
        echo "❌ Указанный порт $PORT занят!"
        echo "💡 Освободите порт или используйте другой"
        exit 1
    fi
else
    # Находим свободный порт автоматически
    PORT=$(find_free_port $DEFAULT_PORT)
    if [ $? -ne 0 ]; then
    echo "❌ Не удалось найти свободный порт!"
    echo "   [DEBUG] Проверяю доступные методы проверки портов..."
    if command -v python3 &>/dev/null; then
        echo "   [OK] python3 доступен"
    else
        echo "   [WARN] python3 не найден"
    fi
    if command -v nc &>/dev/null; then
        echo "   [OK] nc доступен"
    else
        echo "   [WARN] nc не найден"
    fi
    echo ""
    echo "💡 Попробуйте вручную освободить порты или использовать:"
    echo "   PORT=9001 bash /workspace/run.sh $MODEL"
    exit 1
    fi
fi

if [ "$PORT" != "$DEFAULT_PORT" ]; then
    echo "⚠️  Использую порт $PORT вместо $DEFAULT_PORT (порт $DEFAULT_PORT занят)"
fi

# Убиваем старые процессы
echo "🔄 Остановка старых процессов..."
pkill -f $SCRIPT 2>/dev/null
pkill -f cloudflared 2>/dev/null
tmux kill-session -t model 2>/dev/null
tmux kill-session -t tunnel 2>/dev/null
sleep 1

echo "✅ Использую порт: $PORT"

# Финальная проверка что порт действительно свободен
if ! check_port_free $PORT; then
    echo "❌ ОШИБКА: Порт $PORT недоступен, хотя должен быть свободен!"
    echo "   [DEBUG] Ищу новый свободный порт..."
    PORT=$(find_free_port $((DEFAULT_PORT + 1)))
    if [ $? -ne 0 ]; then
        echo "❌ Не удалось найти свободный порт"
        exit 1
    fi
    echo "✅ Использую новый порт: $PORT"
fi

echo ""

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
echo "   [DEBUG] Лог файл создан: $LOG_FILE"

# Отключаем hf_transfer если не установлен
export HF_HUB_ENABLE_HF_TRANSFER=0

# Устанавливаем параметры для моделей с большим контекстом
if [ "$MODEL" = "yagpt" ]; then
    export MAX_MODEL_LEN=${MAX_MODEL_LEN:-4096}
    export GPU_MEMORY_UTILIZATION=${GPU_MEMORY_UTILIZATION:-0.75}
    echo "🔧 Параметры для YandexGPT:"
    echo "   MAX_MODEL_LEN=$MAX_MODEL_LEN"
    echo "   GPU_MEMORY_UTILIZATION=$GPU_MEMORY_UTILIZATION"
elif [ "$MODEL" = "gptoss" ]; then
    export MAX_MODEL_LEN=${MAX_MODEL_LEN:-4096}
    export GPU_MEMORY_UTILIZATION=${GPU_MEMORY_UTILIZATION:-0.75}
    echo "🔧 Параметры для GPT-OSS-20B:"
    echo "   MAX_MODEL_LEN=$MAX_MODEL_LEN"
    echo "   GPU_MEMORY_UTILIZATION=$GPU_MEMORY_UTILIZATION"
elif [ "$MODEL" = "deepseek" ]; then
    export MAX_MODEL_LEN=${MAX_MODEL_LEN:-8192}
    export GPU_MEMORY_UTILIZATION=${GPU_MEMORY_UTILIZATION:-0.85}
    echo "🔧 Параметры для DeepSeek-R1-Qwen3-8B:"
    echo "   MAX_MODEL_LEN=$MAX_MODEL_LEN"
    echo "   GPU_MEMORY_UTILIZATION=$GPU_MEMORY_UTILIZATION"
    echo ""
    echo "📦 Проверка и обновление transformers для поддержки qwen3..."
    CURRENT_VERSION=$(pip show transformers 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "неизвестна")
    echo "   Текущая версия transformers: $CURRENT_VERSION"
    echo "   Обновление до последней версии..."
    pip install --upgrade "transformers>=4.40.0" --no-cache-dir 2>&1 | grep -E "(Successfully|Already|ERROR)" || true
    NEW_VERSION=$(pip show transformers 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "неизвестна")
    echo "   Новая версия transformers: $NEW_VERSION"
    echo ""
    echo "📦 Проверка vLLM (может потребоваться обновление)..."
    pip install --upgrade vllm --no-cache-dir 2>&1 | grep -E "(Successfully|Already|ERROR)" || true
    echo "✅ Зависимости проверены"
fi

# Запускаем через tmux с логированием (без буферизации Python)
echo "🔧 Команда: HOST=0.0.0.0 PORT=$PORT python -u $SCRIPT"
ENV_VARS="export HF_HUB_ENABLE_HF_TRANSFER=0 && export HOST=0.0.0.0 && export PORT=$PORT"
if [ "$MODEL" = "yagpt" ] || [ "$MODEL" = "gptoss" ] || [ "$MODEL" = "deepseek" ]; then
    ENV_VARS="$ENV_VARS && export MAX_MODEL_LEN=$MAX_MODEL_LEN && export GPU_MEMORY_UTILIZATION=$GPU_MEMORY_UTILIZATION"
fi
tmux new -s model -d "cd $PROJECT_DIR && $ENV_VARS && python -u $SCRIPT 2>&1 | tee $LOG_FILE"
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
    # Проверяем что процесс еще жив (ПЕРЕД проверкой сервера!)
    if ! tmux has-session -t model 2>/dev/null; then
        echo ""
        echo "❌ Сессия tmux 'model' завершилась!"
        echo "💡 Проверь логи: cat $LOG_FILE"
        exit 1
    fi
    
    # Проверяем доступность сервера
    if curl -s --max-time 5 http://localhost:$PORT/docs >/dev/null 2>&1; then
        # Дополнительная проверка: убеждаемся что сервер стабилен
        # Проверяем несколько раз подряд
        STABLE_COUNT=0
        for i in 1 2 3; do
            if curl -s --max-time 2 http://localhost:$PORT/docs >/dev/null 2>&1; then
                STABLE_COUNT=$((STABLE_COUNT + 1))
            fi
            sleep 1
        done
        
        # Если сервер отвечает стабильно и сессия еще жива
        if [ $STABLE_COUNT -eq 3 ] && tmux has-session -t model 2>/dev/null; then
            # Проверяем что это действительно FastAPI с правильным ответом
            RESPONSE=$(curl -s --max-time 2 http://localhost:$PORT/docs 2>/dev/null)
            if echo "$RESPONSE" | grep -q "swagger\|fastapi\|openapi" 2>/dev/null; then
                SERVER_READY=1
                break
            fi
        fi
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
    echo "✅ Сервер ответил, проверяю стабильность..."
else
    echo ""
    echo "⚠️  Сервер не ответил в течение ожидания"
    echo "💡 Проверь логи: cat $LOG_FILE"
    echo "💡 Или: tmux attach -t model"
echo ""
    echo "❌ Туннель не будет создан, так как сервер не готов"
    exit 1
fi

# Запускаем туннель в фоне
echo "🌐 Создание URL..."

# Финальная проверка: убеждаемся что сессия model все еще работает
if ! tmux has-session -t model 2>/dev/null; then
    echo ""
    echo "❌ КРИТИЧНО: Сессия tmux 'model' завершилась!"
    echo "💡 Проверь логи: cat $LOG_FILE"
    echo "💡 Модель упала, туннель не будет создан"
    exit 1
fi

# Проверяем что сервер действительно доступен на нужном порту
echo "🔍 Финальная проверка доступности сервера на порту $PORT..."
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
echo "🔗 Создание туннеля для http://127.0.0.1:$PORT"
tmux new -s tunnel -d "cloudflared tunnel --url http://127.0.0.1:$PORT 2>&1 | tee /tmp/llm_logs/${MODEL}-tunnel.log"

# Ждём URL (до 60 секунд)
echo "⏳ Ожидание Cloudflare туннеля..."
sleep 3  # Даём cloudflared время на запуск

# Проверяем что сессия model все еще работает после создания туннеля
if ! tmux has-session -t model 2>/dev/null; then
    echo ""
    echo "❌ КРИТИЧНО: Сессия tmux 'model' завершилась после создания туннеля!"
    echo "💡 Проверь логи: cat $LOG_FILE"
    echo "💡 Туннель создан, но сервер не работает"
fi

URL=""
COUNTER=0
MAX_TUNNEL_WAIT=30  # 60 секунд максимум

while [ -z "$URL" ] && [ $COUNTER -lt $MAX_TUNNEL_WAIT ]; do
    # Проверяем что сессия model все еще работает
    if ! tmux has-session -t model 2>/dev/null; then
        echo ""
        echo "❌ КРИТИЧНО: Сессия tmux 'model' завершилась!"
        echo "💡 Проверь логи: cat $LOG_FILE"
        echo "💡 Туннель продолжит работать, но сервер не доступен"
        break
    fi
    
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

# Финальная проверка статуса перед выводом информации
if ! tmux has-session -t model 2>/dev/null; then
    echo "❌ ВНИМАНИЕ: Сессия tmux 'model' завершилась!"
    echo "💡 Проверь логи: cat $LOG_FILE"
    echo "💡 Туннель может быть создан, но сервер не работает"
    echo ""
elif curl -s --max-time 2 http://localhost:$PORT/docs >/dev/null 2>&1; then
    echo "✅ $NAME ГОТОВ И РАБОТАЕТ!"
else
    echo "⚠️  $NAME - сервер не отвечает на порту $PORT"
    echo "💡 Проверь: tmux attach -t model"
fi

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
        gptoss)
            echo "   POST $URL/generate_gptoss"
            ;;
        deepseek)
            echo "   POST $URL/generate_deepseek"
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
    LSOF_ERROR=$?
    echo "   [DEBUG] lsof вернул код: $LSOF_ERROR"
    
    if [ -n "$PORT_PIDS" ]; then
        echo "⚠️  Порт $PORT занят процессами: $PORT_PIDS"
        echo "   [DEBUG] Найдено процессов: $(echo $PORT_PIDS | wc -w)"
        echo "   [DEBUG] Детальная информация о процессах:"
        lsof -i :$PORT 2>/dev/null | while read line; do
            echo "      $line"
        done
        
        for pid in $PORT_PIDS; do
            echo "   [DEBUG] Завершаю процесс PID=$pid..."
            echo "   [DEBUG] Информация о процессе перед завершением:"
            ps -p $pid -o pid,ppid,cmd,etime 2>/dev/null || echo "      Процесс уже не существует"
            
            kill -9 $pid 2>/dev/null
            KILL_ERROR=$?
            echo "   [DEBUG] kill -9 $pid вернул код: $KILL_ERROR"
            
            sleep 0.5
            if ps -p $pid &>/dev/null; then
                echo "   [WARN] Процесс $pid все еще работает после kill -9"
            else
                echo "   [OK] Процесс $pid успешно завершен"
            fi
        done
        sleep 2
    else
        echo "   [DEBUG] Порт $PORT не занят (по lsof)"
    fi
else
    echo "   [DEBUG] lsof не доступен"
fi

# Метод 2: через fuser (более агрессивный)
if command -v fuser &>/dev/null; then
    echo "   [DEBUG] fuser доступен, проверяю порт $PORT..."
    FUSER_CHECK=$(fuser $PORT/tcp 2>&1)
    FUSER_ERROR=$?
    echo "   [DEBUG] fuser вернул код: $FUSER_ERROR"
    echo "   [DEBUG] Вывод fuser: $FUSER_CHECK"
    
    if [ $FUSER_ERROR -eq 0 ] || echo "$FUSER_CHECK" | grep -q "$PORT"; then
        echo "⚠️  Порт $PORT занят (fuser), освобождаю..."
        echo "   [DEBUG] Запускаю fuser -k $PORT/tcp..."
        fuser -k $PORT/tcp 2>&1
        FUSER_KILL_ERROR=$?
        echo "   [DEBUG] fuser -k вернул код: $FUSER_KILL_ERROR"
        sleep 2
        
        # Проверяем результат
        FUSER_CHECK_AFTER=$(fuser $PORT/tcp 2>&1)
        if [ $? -eq 0 ] || echo "$FUSER_CHECK_AFTER" | grep -q "$PORT"; then
            echo "   [WARN] Порт все еще занят после fuser -k"
        else
            echo "   [OK] Порт освобожден (fuser)"
        fi
    else
        echo "   [DEBUG] Порт $PORT не занят (по fuser)"
    fi
else
    echo "   [DEBUG] fuser не доступен"
fi

# Метод 3: через ss
if command -v ss &>/dev/null; then
    echo "   [DEBUG] ss доступен, проверяю порт $PORT..."
    SS_OUTPUT=$(ss -tlnp 2>/dev/null | grep ":$PORT ")
    SS_ERROR=$?
    echo "   [DEBUG] ss вернул код: $SS_ERROR"
    
    if [ -n "$SS_OUTPUT" ]; then
        echo "⚠️  Порт $PORT занят (ss), ищу процессы..."
        echo "   [DEBUG] Вывод ss:"
        echo "$SS_OUTPUT" | while read line; do
            echo "      $line"
        done
        
        # Пробуем извлечь PID из вывода ss
        PORT_PIDS=$(echo "$SS_OUTPUT" | grep -oP 'pid=\K[0-9]+' | sort -u)
        echo "   [DEBUG] Найдено PID через ss: $PORT_PIDS"
        
        if [ -n "$PORT_PIDS" ]; then
            for pid in $PORT_PIDS; do
                echo "   [DEBUG] Завершаю процесс PID=$pid (найден через ss)..."
                echo "   [DEBUG] Информация о процессе:"
                ps -p $pid -o pid,ppid,cmd,etime 2>/dev/null || echo "      Процесс не найден"
                
                kill -9 $pid 2>/dev/null
                KILL_ERROR=$?
                echo "   [DEBUG] kill -9 $pid вернул код: $KILL_ERROR"
                
                sleep 0.5
                if ps -p $pid &>/dev/null; then
                    echo "   [WARN] Процесс $pid все еще работает"
                else
                    echo "   [OK] Процесс $pid завершен"
                fi
            done
            sleep 2
        fi
    else
        echo "   [DEBUG] Порт $PORT не занят (по ss)"
    fi
else
    echo "   [DEBUG] ss не доступен"
fi

# Метод 4: через netstat (fallback)
if command -v netstat &>/dev/null; then
    echo "   [DEBUG] netstat доступен, проверяю порт $PORT..."
    NETSTAT_OUTPUT=$(netstat -tlnp 2>/dev/null | grep ":$PORT ")
    NETSTAT_ERROR=$?
    echo "   [DEBUG] netstat вернул код: $NETSTAT_ERROR"
    
    if [ -n "$NETSTAT_OUTPUT" ]; then
        echo "⚠️  Порт $PORT занят (netstat), ищу процессы..."
        echo "   [DEBUG] Вывод netstat:"
        echo "$NETSTAT_OUTPUT" | while read line; do
            echo "      $line"
        done
        
        PORT_PIDS=$(echo "$NETSTAT_OUTPUT" | awk '{print $7}' | cut -d'/' -f1 | grep -E '^[0-9]+$' | sort -u)
        echo "   [DEBUG] Найдено PID через netstat: $PORT_PIDS"
        
        if [ -n "$PORT_PIDS" ]; then
            for pid in $PORT_PIDS; do
                echo "   [DEBUG] Завершаю процесс PID=$pid (найден через netstat)..."
                echo "   [DEBUG] Информация о процессе:"
                ps -p $pid -o pid,ppid,cmd,etime 2>/dev/null || echo "      Процесс не найден"
                
                kill -9 $pid 2>/dev/null
                KILL_ERROR=$?
                echo "   [DEBUG] kill -9 $pid вернул код: $KILL_ERROR"
                
                sleep 0.5
                if ps -p $pid &>/dev/null; then
                    echo "   [WARN] Процесс $pid все еще работает"
                else
                    echo "   [OK] Процесс $pid завершен"
                fi
            done
            sleep 2
        fi
    else
        echo "   [DEBUG] Порт $PORT не занят (по netstat)"
    fi
else
    echo "   [DEBUG] netstat не доступен"
fi

# Финальная проверка и агрессивное освобождение
echo "   [DEBUG] Начинаю финальную проверку порта (3 попытки)..."
for i in 1 2 3; do
    echo "   [DEBUG] Попытка $i из 3..."
    PORT_FREE=true
    
    if command -v lsof &>/dev/null; then
        echo "   [DEBUG] Проверка через lsof (попытка $i)..."
        LSOF_PIDS=$(lsof -ti :$PORT 2>/dev/null)
        LSOF_CHECK_ERROR=$?
        echo "   [DEBUG] lsof -ti :$PORT вернул код: $LSOF_CHECK_ERROR"
        echo "   [DEBUG] Найдено PID: $LSOF_PIDS"
        
        if [ -n "$LSOF_PIDS" ]; then
            PORT_FREE=false
            echo "⚠️  Попытка $i: Порт $PORT все еще занят, агрессивное освобождение..."
            echo "   [DEBUG] Завершаю все процессы на порту $PORT..."
            echo "$LSOF_PIDS" | xargs -r -n 1 sh -c 'echo "      [DEBUG] Убиваю PID: $1"; kill -9 "$1" 2>&1; echo "      [DEBUG] kill вернул код: $?"' _ 2>/dev/null
            sleep 1
        else
            echo "   [DEBUG] Порт свободен (lsof, попытка $i)"
        fi
    fi
    
    if command -v fuser &>/dev/null; then
        echo "   [DEBUG] Проверка через fuser (попытка $i)..."
        FUSER_CHECK=$(fuser $PORT/tcp 2>&1)
        FUSER_CHECK_ERROR=$?
        echo "   [DEBUG] fuser вернул код: $FUSER_CHECK_ERROR"
        
        if [ $FUSER_CHECK_ERROR -eq 0 ] || echo "$FUSER_CHECK" | grep -q "$PORT"; then
            PORT_FREE=false
            echo "   [DEBUG] Запускаю fuser -k (попытка $i)..."
            fuser -k $PORT/tcp 2>&1
            FUSER_KILL_ERROR=$?
            echo "   [DEBUG] fuser -k вернул код: $FUSER_KILL_ERROR"
            sleep 1
        else
            echo "   [DEBUG] Порт свободен (fuser, попытка $i)"
        fi
    fi
    
    # Финальная проверка после попытки
    echo "   [DEBUG] Проверка результата после попытки $i..."
    FINAL_CHECK=false
    if command -v lsof &>/dev/null; then
        FINAL_PIDS=$(lsof -ti :$PORT 2>/dev/null)
        if [ -n "$FINAL_PIDS" ]; then
            FINAL_CHECK=true
            echo "   [DEBUG] Порт все еще занят процессами: $FINAL_PIDS"
        fi
    fi
    
    if [ "$PORT_FREE" = true ] && [ "$FINAL_CHECK" = false ]; then
        echo "✅ Порт $PORT свободен (попытка $i)"
        break
    else
        echo "   [DEBUG] Порт все еще занят, жду перед следующей попыткой..."
        sleep 2
    fi
done

# Последняя проверка со всеми методами
echo "   [DEBUG] Последняя комплексная проверка порта..."
FINAL_PORT_STATUS="unknown"
FINAL_PORT_PIDS=""

if command -v lsof &>/dev/null; then
    FINAL_LSOF=$(lsof -i :$PORT 2>/dev/null)
    FINAL_LSOF_PIDS=$(lsof -ti :$PORT 2>/dev/null)
    if [ -n "$FINAL_LSOF" ]; then
        FINAL_PORT_STATUS="occupied"
        FINAL_PORT_PIDS="$FINAL_LSOF_PIDS"
        echo "   [DEBUG] lsof показывает что порт занят:"
        echo "$FINAL_LSOF" | while read line; do
            echo "      $line"
        done
    else
        echo "   [DEBUG] lsof: порт свободен"
    fi
fi

if command -v ss &>/dev/null; then
    FINAL_SS=$(ss -tlnp 2>/dev/null | grep ":$PORT ")
    if [ -n "$FINAL_SS" ]; then
        FINAL_PORT_STATUS="occupied"
        echo "   [DEBUG] ss показывает что порт занят:"
        echo "$FINAL_SS" | while read line; do
            echo "      $line"
        done
    else
        echo "   [DEBUG] ss: порт свободен"
    fi
fi

if command -v fuser &>/dev/null; then
    FINAL_FUSER=$(fuser $PORT/tcp 2>&1)
    if [ $? -eq 0 ] || echo "$FINAL_FUSER" | grep -q "$PORT"; then
        FINAL_PORT_STATUS="occupied"
        echo "   [DEBUG] fuser показывает что порт занят: $FINAL_FUSER"
    else
        echo "   [DEBUG] fuser: порт свободен"
    fi
fi

# Финальный вывод
if [ "$FINAL_PORT_STATUS" = "occupied" ]; then
    echo ""
    echo "❌ ВНИМАНИЕ: Порт $PORT все еще занят после всех попыток!"
    echo "   [DEBUG] Найденные PID: $FINAL_PORT_PIDS"
    echo ""
    echo "💡 Попробуйте вручную:"
    echo "   lsof -ti :$PORT | xargs kill -9"
    echo "   или"
    echo "   fuser -k $PORT/tcp"
    echo ""
    echo "💡 Или используйте другой порт через переменную PORT:"
    echo "   PORT=8089 bash /workspace/run.sh yagpt"
    echo ""
    echo "   [DEBUG] Все процессы Python:"
    ps aux | grep python | grep -v grep | head -5
    echo ""
    echo "   [DEBUG] Все процессы на портах 8080-8090:"
    for p in 8080 8081 8082 8083 8084 8085 8086 8087 8088 8089 8090; do
        if command -v lsof &>/dev/null; then
            PORT_P=$(lsof -ti :$p 2>/dev/null)
            if [ -n "$PORT_P" ]; then
                echo "      Порт $p: PID=$PORT_P"
            fi
        fi
    done
else
    echo "✅ Порт $PORT готов к использованию"
    echo "   [DEBUG] Все проверки пройдены успешно"
fi

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

# Финальная проверка порта перед запуском
echo ""
echo "   [DEBUG] Финальная проверка порта $PORT перед запуском модели..."
FINAL_PORT_CHECK=false

# Проверяем через ss - это может показать порт в состоянии LISTEN без PID
if command -v ss &>/dev/null; then
    FINAL_SS_CHECK=$(ss -tlnp 2>/dev/null | grep ":$PORT ")
    if [ -n "$FINAL_SS_CHECK" ]; then
        echo "   [DEBUG] ss показывает порт занятым:"
        echo "   $FINAL_SS_CHECK"
        
        # Извлекаем inode если есть
        SS_INODE=$(echo "$FINAL_SS_CHECK" | grep -oP 'ino:\K[0-9]+' | head -1)
        if [ -n "$SS_INODE" ]; then
            echo "   [DEBUG] Найден inode: $SS_INODE"
            # Пробуем найти процесс по inode
            INODE_PID=$(find /proc/*/fd -lname "socket:\[$SS_INODE\]" 2>/dev/null | cut -d'/' -f3 | head -1)
            if [ -n "$INODE_PID" ]; then
                echo "   [DEBUG] Найден PID по inode: $INODE_PID"
                echo "   [DEBUG] Информация о процессе:"
                ps -p $INODE_PID -o pid,ppid,cmd,etime 2>/dev/null || echo "      Процесс не найден"
                echo "   [DEBUG] Завершаю процесс $INODE_PID..."
                kill -9 $INODE_PID 2>/dev/null
                sleep 2
            fi
        fi
        
        # Пробуем принудительно закрыть через ss -K
        echo "   [DEBUG] Пробую принудительно закрыть соединение через ss -K..."
        ss -K dst ":$PORT" 2>&1
        SS_K_ERROR=$?
        echo "   [DEBUG] ss -K вернул код: $SS_K_ERROR"
        sleep 2
        
        # Проверяем снова
        FINAL_SS_CHECK_AFTER=$(ss -tlnp 2>/dev/null | grep ":$PORT ")
        if [ -n "$FINAL_SS_CHECK_AFTER" ]; then
            echo "   [WARN] Порт все еще занят после ss -K"
            FINAL_PORT_CHECK=true
        else
            echo "   [OK] Порт освобожден после ss -K"
        fi
    else
        echo "   [OK] Порт $PORT свободен (ss)"
    fi
fi

# Проверяем через lsof
if command -v lsof &>/dev/null; then
    FINAL_CHECK_PIDS=$(lsof -ti :$PORT 2>/dev/null)
    if [ -n "$FINAL_CHECK_PIDS" ]; then
        echo "   [ERROR] Порт $PORT все еще занят перед запуском! PID: $FINAL_CHECK_PIDS"
        echo "   [DEBUG] Детальная информация:"
        lsof -i :$PORT 2>/dev/null
        FINAL_PORT_CHECK=true
    else
        echo "   [OK] Порт $PORT свободен (lsof)"
    fi
fi

# Если порт все еще занят, пробуем тестовый bind
if [ "$FINAL_PORT_CHECK" = true ]; then
    echo "   [DEBUG] Пробую тестовый bind на порт $PORT..."
    # Используем Python для проверки можно ли забиндить порт
    python3 -c "
import socket
import sys
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('0.0.0.0', $PORT))
    s.close()
    print('   [OK] Порт доступен для bind')
    sys.exit(0)
except Exception as e:
    print(f'   [ERROR] Не удалось забиндить порт: {e}')
    sys.exit(1)
" 2>&1
    BIND_TEST=$?
    
    if [ $BIND_TEST -eq 0 ]; then
        echo "   [OK] Порт доступен для bind, продолжаю запуск..."
        FINAL_PORT_CHECK=false
    else
        echo ""
        echo "❌ КРИТИЧЕСКАЯ ОШИБКА: Порт $PORT занят и не может быть освобожден!"
        echo "   [DEBUG] Попробуйте вручную:"
        echo "   ss -K dst :$PORT"
        echo "   или"
        echo "   lsof -ti :$PORT | xargs kill -9"
        echo ""
        echo "   Или используйте другой порт: PORT=8089 bash /workspace/run.sh $MODEL"
        exit 1
    fi
fi

echo "   [OK] Порт $PORT готов, запускаю модель..."
echo ""

# Запускаем модель в фоне
echo "⏳ Запуск $NAME..."
echo ""

# Создаём лог файл
mkdir -p /tmp/llm_logs
LOG_FILE="/tmp/llm_logs/${MODEL}.log"
> "$LOG_FILE"  # Очищаем старый лог
echo "   [DEBUG] Лог файл создан: $LOG_FILE"

# Отключаем hf_transfer если не установлен
export HF_HUB_ENABLE_HF_TRANSFER=0

# Устанавливаем параметры для моделей с большим контекстом
if [ "$MODEL" = "yagpt" ]; then
    export MAX_MODEL_LEN=${MAX_MODEL_LEN:-4096}
    export GPU_MEMORY_UTILIZATION=${GPU_MEMORY_UTILIZATION:-0.75}
    echo "🔧 Параметры для YandexGPT:"
    echo "   MAX_MODEL_LEN=$MAX_MODEL_LEN"
    echo "   GPU_MEMORY_UTILIZATION=$GPU_MEMORY_UTILIZATION"
elif [ "$MODEL" = "gptoss" ]; then
    export MAX_MODEL_LEN=${MAX_MODEL_LEN:-4096}
    export GPU_MEMORY_UTILIZATION=${GPU_MEMORY_UTILIZATION:-0.75}
    echo "🔧 Параметры для GPT-OSS-20B:"
    echo "   MAX_MODEL_LEN=$MAX_MODEL_LEN"
    echo "   GPU_MEMORY_UTILIZATION=$GPU_MEMORY_UTILIZATION"
elif [ "$MODEL" = "deepseek" ]; then
    export MAX_MODEL_LEN=${MAX_MODEL_LEN:-8192}
    export GPU_MEMORY_UTILIZATION=${GPU_MEMORY_UTILIZATION:-0.85}
    echo "🔧 Параметры для DeepSeek-R1-Qwen3-8B:"
    echo "   MAX_MODEL_LEN=$MAX_MODEL_LEN"
    echo "   GPU_MEMORY_UTILIZATION=$GPU_MEMORY_UTILIZATION"
    echo ""
    echo "📦 Проверка и обновление transformers для поддержки qwen3..."
    CURRENT_VERSION=$(pip show transformers 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "неизвестна")
    echo "   Текущая версия transformers: $CURRENT_VERSION"
    echo "   Обновление до последней версии..."
    pip install --upgrade "transformers>=4.40.0" --no-cache-dir 2>&1 | grep -E "(Successfully|Already|ERROR)" || true
    NEW_VERSION=$(pip show transformers 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "неизвестна")
    echo "   Новая версия transformers: $NEW_VERSION"
    echo ""
    echo "📦 Проверка vLLM (может потребоваться обновление)..."
    pip install --upgrade vllm --no-cache-dir 2>&1 | grep -E "(Successfully|Already|ERROR)" || true
    echo "✅ Зависимости проверены"
fi

# Запускаем через tmux с логированием (без буферизации Python)
echo "🔧 Команда: HOST=0.0.0.0 PORT=$PORT python -u $SCRIPT"
ENV_VARS="export HF_HUB_ENABLE_HF_TRANSFER=0 && export HOST=0.0.0.0 && export PORT=$PORT"
if [ "$MODEL" = "yagpt" ] || [ "$MODEL" = "gptoss" ] || [ "$MODEL" = "deepseek" ]; then
    ENV_VARS="$ENV_VARS && export MAX_MODEL_LEN=$MAX_MODEL_LEN && export GPU_MEMORY_UTILIZATION=$GPU_MEMORY_UTILIZATION"
fi
tmux new -s model -d "cd $PROJECT_DIR && $ENV_VARS && python -u $SCRIPT 2>&1 | tee $LOG_FILE"
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
    # Проверяем что процесс еще жив (ПЕРЕД проверкой сервера!)
    if ! tmux has-session -t model 2>/dev/null; then
        echo ""
        echo "❌ Сессия tmux 'model' завершилась!"
        echo "💡 Проверь логи: cat $LOG_FILE"
        exit 1
    fi
    
    # Проверяем доступность сервера
    if curl -s --max-time 5 http://localhost:$PORT/docs >/dev/null 2>&1; then
        # Дополнительная проверка: убеждаемся что сервер стабилен
        # Проверяем несколько раз подряд
        STABLE_COUNT=0
        for i in 1 2 3; do
            if curl -s --max-time 2 http://localhost:$PORT/docs >/dev/null 2>&1; then
                STABLE_COUNT=$((STABLE_COUNT + 1))
            fi
            sleep 1
        done
        
        # Если сервер отвечает стабильно и сессия еще жива
        if [ $STABLE_COUNT -eq 3 ] && tmux has-session -t model 2>/dev/null; then
            # Проверяем что это действительно FastAPI с правильным ответом
            RESPONSE=$(curl -s --max-time 2 http://localhost:$PORT/docs 2>/dev/null)
            if echo "$RESPONSE" | grep -q "swagger\|fastapi\|openapi" 2>/dev/null; then
                SERVER_READY=1
                break
            fi
        fi
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
    echo "✅ Сервер ответил, проверяю стабильность..."
else
    echo ""
    echo "⚠️  Сервер не ответил в течение ожидания"
    echo "💡 Проверь логи: cat $LOG_FILE"
    echo "💡 Или: tmux attach -t model"
    echo ""
    echo "❌ Туннель не будет создан, так как сервер не готов"
    exit 1
fi

# Запускаем туннель в фоне
echo "🌐 Создание URL..."

# Финальная проверка: убеждаемся что сессия model все еще работает
if ! tmux has-session -t model 2>/dev/null; then
    echo ""
    echo "❌ КРИТИЧНО: Сессия tmux 'model' завершилась!"
    echo "💡 Проверь логи: cat $LOG_FILE"
    echo "💡 Модель упала, туннель не будет создан"
    exit 1
fi

# Проверяем что сервер действительно доступен на нужном порту
echo "🔍 Финальная проверка доступности сервера на порту $PORT..."
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
echo "🔗 Создание туннеля для http://127.0.0.1:$PORT"
tmux new -s tunnel -d "cloudflared tunnel --url http://127.0.0.1:$PORT 2>&1 | tee /tmp/llm_logs/${MODEL}-tunnel.log"

# Ждём URL (до 60 секунд)
echo "⏳ Ожидание Cloudflare туннеля..."
sleep 3  # Даём cloudflared время на запуск

# Проверяем что сессия model все еще работает после создания туннеля
if ! tmux has-session -t model 2>/dev/null; then
    echo ""
    echo "❌ КРИТИЧНО: Сессия tmux 'model' завершилась после создания туннеля!"
    echo "💡 Проверь логи: cat $LOG_FILE"
    echo "💡 Туннель создан, но сервер не работает"
fi

URL=""
COUNTER=0
MAX_TUNNEL_WAIT=30  # 60 секунд максимум

while [ -z "$URL" ] && [ $COUNTER -lt $MAX_TUNNEL_WAIT ]; do
    # Проверяем что сессия model все еще работает
    if ! tmux has-session -t model 2>/dev/null; then
        echo ""
        echo "❌ КРИТИЧНО: Сессия tmux 'model' завершилась!"
        echo "💡 Проверь логи: cat $LOG_FILE"
        echo "💡 Туннель продолжит работать, но сервер не доступен"
        break
    fi
    
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

# Финальная проверка статуса перед выводом информации
if ! tmux has-session -t model 2>/dev/null; then
    echo "❌ ВНИМАНИЕ: Сессия tmux 'model' завершилась!"
    echo "💡 Проверь логи: cat $LOG_FILE"
    echo "💡 Туннель может быть создан, но сервер не работает"
    echo ""
elif curl -s --max-time 2 http://localhost:$PORT/docs >/dev/null 2>&1; then
    echo "✅ $NAME ГОТОВ И РАБОТАЕТ!"
else
    echo "⚠️  $NAME - сервер не отвечает на порту $PORT"
    echo "💡 Проверь: tmux attach -t model"
fi

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
        gptoss)
            echo "   POST $URL/generate_gptoss"
            ;;
        deepseek)
            echo "   POST $URL/generate_deepseek"
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

