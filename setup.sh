#!/bin/bash

##############################################
# LLM Services Auto Setup Script
# Устанавливает и запускает T-lite, Vikhr, YandexGPT
##############################################

set -e  # Остановка при ошибке

echo "🚀 ===== LLM Services Setup ====="
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Функция логирования
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

##############################################
# 1. Проверка GPU
##############################################
log_info "Проверка GPU..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
else
    log_error "NVIDIA GPU не найдена! Скрипт для GPU серверов."
    exit 1
fi

##############################################
# 2. Установка системных зависимостей
##############################################
log_info "Установка системных пакетов..."
apt-get update -qq
apt-get install -y -qq tmux wget curl > /dev/null 2>&1

##############################################
# 3. Установка Python зависимостей
##############################################
log_info "Установка Python библиотек (это может занять 5-10 минут)..."
pip install -q --upgrade pip
pip install -q -r requirements.txt

log_info "Установка cloudflared для удалённого доступа..."
if [ ! -f /usr/bin/cloudflared ]; then
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i cloudflared-linux-amd64.deb > /dev/null 2>&1
    rm cloudflared-linux-amd64.deb
fi

##############################################
# 4. Создание директории для логов
##############################################
mkdir -p logs

##############################################
# 5. Определение какие модели запускать
##############################################
echo ""
log_info "Какие модели запустить?"
echo "1) Только T-lite (3B, ~8GB VRAM)"
echo "2) Только YandexGPT (8B, ~16GB VRAM)"
echo "3) Только Vikhr (12B, ~24GB VRAM)"
echo "4) T-lite + YandexGPT (~20GB VRAM)"
echo "5) Все три (требуется 40GB+ VRAM или 8-bit)"
read -p "Выбери вариант (1-5): " CHOICE

MODELS=()
case $CHOICE in
    1)
        MODELS=("tlite")
        ;;
    2)
        MODELS=("yagpt")
        ;;
    3)
        MODELS=("vikhr")
        ;;
    4)
        MODELS=("tlite" "yagpt")
        ;;
    5)
        MODELS=("tlite" "yagpt" "vikhr")
        ;;
    *)
        log_error "Неверный выбор!"
        exit 1
        ;;
esac

##############################################
# 6. Запуск моделей
##############################################
echo ""
log_info "Запуск выбранных моделей..."

for MODEL in "${MODELS[@]}"; do
    case $MODEL in
        tlite)
            log_info "Запуск T-lite на порту 8083..."
            tmux new -s tlite -d "python app_tlite.py 2>&1 | tee logs/tlite.log"
            ;;
        yagpt)
            log_info "Запуск YandexGPT на порту 8081..."
            tmux new -s yagpt -d "python app_yagpt.py 2>&1 | tee logs/yagpt.log"
            ;;
        vikhr)
            log_info "Запуск Vikhr на порту 8082..."
            tmux new -s vikhr -d "python app_vikhr.py 2>&1 | tee logs/vikhr.log"
            ;;
    esac
done

##############################################
# 7. Ожидание загрузки моделей
##############################################
log_info "Ожидание загрузки моделей (30-60 секунд)..."
sleep 30

##############################################
# 8. Запуск cloudflare туннелей
##############################################
echo ""
log_info "Настройка удалённого доступа..."

TUNNELS=()
for MODEL in "${MODELS[@]}"; do
    case $MODEL in
        tlite)
            PORT=8083
            NAME="tlite-tunnel"
            ;;
        yagpt)
            PORT=8081
            NAME="yagpt-tunnel"
            ;;
        vikhr)
            PORT=8082
            NAME="vikhr-tunnel"
            ;;
    esac
    
    log_info "Создание туннеля для $MODEL (порт $PORT)..."
    tmux new -s "$NAME" -d "cloudflared tunnel --url http://localhost:$PORT 2>&1 | tee logs/${MODEL}-tunnel.log"
    TUNNELS+=("$NAME")
    sleep 2
done

##############################################
# 9. Вывод URL
##############################################
sleep 5
echo ""
echo "======================================"
log_info "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo "======================================"
echo ""

for i in "${!MODELS[@]}"; do
    MODEL="${MODELS[$i]}"
    TUNNEL="${TUNNELS[$i]}"
    
    case $MODEL in
        tlite)
            PORT=8083
            ENDPOINT="/generate_tlite"
            ;;
        yagpt)
            PORT=8081
            ENDPOINT="/generate_yagpt"
            ;;
        vikhr)
            PORT=8082
            ENDPOINT="/generate_vikhr"
            ;;
    esac
    
    log_info "🌐 $MODEL:"
    URL=$(tmux capture-pane -t "$TUNNEL" -p | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
    
    if [ -n "$URL" ]; then
        echo "   URL: $URL"
        echo "   Docs: $URL/docs"
        echo "   Endpoint: POST $URL$ENDPOINT"
    else
        log_warn "   Туннель ещё создаётся, подожди 10 секунд и проверь: tmux attach -t $TUNNEL"
    fi
    echo ""
done

echo "======================================"
echo ""
log_info "📝 Полезные команды:"
echo "   • Посмотреть логи модели: tmux attach -t tlite (или yagpt/vikhr)"
echo "   • Посмотреть URL туннеля: tmux attach -t tlite-tunnel"
echo "   • Список всех сессий: tmux ls"
echo "   • Выйти из tmux: Ctrl+B, потом D"
echo "   • Остановить всё: ./stop.sh"
echo "   • Перезапустить: ./restart.sh"
echo ""
log_info "🎉 Готово! Используй URL выше для доступа к API!"

