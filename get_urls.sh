#!/bin/bash

##############################################
# Получить URL всех туннелей
##############################################

echo "🌐 Cloudflare Tunnel URLs:"
echo ""

# T-lite
if tmux has-session -t tlite-tunnel 2>/dev/null; then
    URL=$(tmux capture-pane -t tlite-tunnel -p | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
    if [ -n "$URL" ]; then
        echo "T-lite (порт 8083):"
        echo "  URL: $URL"
        echo "  Docs: $URL/docs"
        echo "  Endpoint: POST $URL/generate_tlite"
        echo ""
    fi
fi

# YandexGPT
if tmux has-session -t yagpt-tunnel 2>/dev/null; then
    URL=$(tmux capture-pane -t yagpt-tunnel -p | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
    if [ -n "$URL" ]; then
        echo "YandexGPT (порт 8081):"
        echo "  URL: $URL"
        echo "  Docs: $URL/docs"
        echo "  Endpoint: POST $URL/generate_yagpt"
        echo ""
    fi
fi

# Vikhr
if tmux has-session -t vikhr-tunnel 2>/dev/null; then
    URL=$(tmux capture-pane -t vikhr-tunnel -p | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
    if [ -n "$URL" ]; then
        echo "Vikhr (порт 8082):"
        echo "  URL: $URL"
        echo "  Docs: $URL/docs"
        echo "  Endpoint: POST $URL/generate_vikhr"
        echo ""
    fi
fi

echo "📝 Если URL не показываются - туннели ещё создаются."
echo "   Подожди 10 секунд и запусти снова: ./get_urls.sh"


