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
echo "🔧 Команда: python -u $SCRIPT"
tmux new -s model -d "cd $PROJECT_DIR && export HF_HUB_ENABLE_HF_TRANSFER=0 && python -u $SCRIPT 2>&1 | tee $LOG_FILE"
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

while ! curl -s http://localhost:$PORT/docs >/dev/null 2>&1; do
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
    
    sleep 2
done

echo ""
echo "✅ Модель готова!"

# Запускаем туннель в фоне
echo "🌐 Создание URL..."
tmux new -s tunnel -d "cloudflared tunnel --url http://localhost:$PORT"
sleep 3

# Получаем и выводим URL
URL=$(tmux capture-pane -t tunnel -p | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
echo ""
echo "================================"
echo "✅ $NAME ГОТОВ!"
echo "================================"
echo "🌐 Swagger UI:"
echo "   $URL/docs"
echo "================================"
echo ""

