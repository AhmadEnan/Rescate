#!/bin/bash

# Flutter Llama Test Runner
# Удобный скрипт для запуска всех тестов

set -e

echo "🧪 Flutter Llama Test Runner"
echo "=============================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if flutter is installed
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter не найден. Установите Flutter сначала.${NC}"
    exit 1
fi

# Function to print section header
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Parse arguments
RUN_UNIT=false
RUN_INTEGRATION=false
RUN_COVERAGE=false
INSTALL_DEPS=false

if [ $# -eq 0 ]; then
    RUN_UNIT=true
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            --unit|-u)
                RUN_UNIT=true
                shift
                ;;
            --integration|-i)
                RUN_INTEGRATION=true
                shift
                ;;
            --coverage|-c)
                RUN_COVERAGE=true
                RUN_UNIT=true
                shift
                ;;
            --install|-d)
                INSTALL_DEPS=true
                shift
                ;;
            --all|-a)
                RUN_UNIT=true
                RUN_INTEGRATION=true
                shift
                ;;
            --help|-h)
                echo "Использование: ./run_tests.sh [опции]"
                echo ""
                echo "Опции:"
                echo "  --unit, -u          Запустить unit тесты"
                echo "  --integration, -i   Запустить integration тесты"
                echo "  --coverage, -c      Запустить с coverage"
                echo "  --install, -d       Установить зависимости"
                echo "  --all, -a           Запустить все тесты"
                echo "  --help, -h          Показать эту справку"
                echo ""
                echo "По умолчанию (без аргументов): запускаются unit тесты"
                exit 0
                ;;
            *)
                echo -e "${RED}Неизвестная опция: $1${NC}"
                echo "Используйте --help для справки"
                exit 1
                ;;
        esac
    done
fi

# Install dependencies
if [ "$INSTALL_DEPS" = true ]; then
    print_header "📦 Установка зависимостей"
    flutter pub get
    cd example && flutter pub get && cd ..
    echo -e "${GREEN}✅ Зависимости установлены${NC}"
    echo ""
fi

# Run unit tests
if [ "$RUN_UNIT" = true ]; then
    print_header "🧪 Запуск Unit тестов"
    
    if [ "$RUN_COVERAGE" = true ]; then
        echo -e "${YELLOW}Запуск с coverage...${NC}"
        flutter test --coverage
        echo ""
        echo -e "${GREEN}✅ Unit тесты завершены с coverage${NC}"
        echo -e "${BLUE}📊 Coverage report: coverage/lcov.info${NC}"
        
        # Generate HTML report if genhtml is available
        if command -v genhtml &> /dev/null; then
            echo -e "${YELLOW}Генерация HTML отчета...${NC}"
            genhtml coverage/lcov.info -o coverage/html
            echo -e "${GREEN}✅ HTML отчет: coverage/html/index.html${NC}"
        else
            echo -e "${YELLOW}⚠️  genhtml не найден. Установите lcov для HTML отчета${NC}"
        fi
    else
        flutter test --reporter expanded
        echo -e "${GREEN}✅ Unit тесты завершены${NC}"
    fi
    echo ""
fi

# Run integration tests
if [ "$RUN_INTEGRATION" = true ]; then
    print_header "🔗 Запуск Integration тестов"
    
    # Check if Ollama is installed
    if ! command -v ollama &> /dev/null; then
        echo -e "${YELLOW}⚠️  Ollama не найден.${NC}"
        echo -e "${YELLOW}   Установите Ollama для тестов с динамической загрузкой моделей:${NC}"
        echo -e "${YELLOW}   brew install ollama${NC}"
        echo ""
    else
        echo -e "${GREEN}✅ Ollama найден${NC}"
        
        # Check if model is available
        if ollama list | grep -q "braindler"; then
            echo -e "${GREEN}✅ Модель Braindler найдена${NC}"
        else
            echo -e "${YELLOW}⚠️  Модель Braindler не найдена${NC}"
            echo -e "${YELLOW}   Загрузка модели q2_k (72MB)...${NC}"
            ollama pull nativemind/braindler:q2_k
        fi
    fi
    
    echo ""
    echo -e "${BLUE}Запуск integration тестов...${NC}"
    cd example
    
    # Check if device is connected
    DEVICES=$(flutter devices --machine | grep -c '"id"')
    if [ "$DEVICES" -eq 0 ]; then
        echo -e "${RED}❌ Устройство не найдено. Подключите устройство или запустите эмулятор.${NC}"
        cd ..
        exit 1
    fi
    
    echo -e "${GREEN}✅ Найдено устройств: $DEVICES${NC}"
    echo ""
    
    # Run basic integration tests
    echo -e "${BLUE}Запуск базовых integration тестов...${NC}"
    flutter test integration_test/plugin_integration_test.dart
    
    # Run Ollama integration tests if available
    if command -v ollama &> /dev/null && ollama list | grep -q "braindler"; then
        echo ""
        echo -e "${BLUE}Запуск Ollama integration тестов...${NC}"
        flutter test integration_test/ollama_integration_test.dart
    fi
    
    cd ..
    echo -e "${GREEN}✅ Integration тесты завершены${NC}"
    echo ""
fi

# Summary
print_header "📊 Итоги"
if [ "$RUN_UNIT" = true ]; then
    echo -e "${GREEN}✅ Unit тесты: PASSED${NC}"
fi
if [ "$RUN_INTEGRATION" = true ]; then
    echo -e "${GREEN}✅ Integration тесты: PASSED${NC}"
fi
if [ "$RUN_COVERAGE" = true ]; then
    echo -e "${GREEN}✅ Coverage: Сгенерирован${NC}"
fi
echo ""
echo -e "${BLUE}🎉 Все тесты успешно завершены!${NC}"
