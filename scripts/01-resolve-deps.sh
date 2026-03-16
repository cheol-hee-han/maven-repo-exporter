#!/usr/bin/env bash
# =============================================================================
# 01-resolve-deps.sh
# 목적: 지정한 모듈(또는 전체 모듈)의 의존성을 로컬 .m2 레포지토리로 다운로드
#       각 deps 는 독립 pom.xml 이므로 -f 옵션으로 개별 실행
#
# 사용:
#   bash scripts/01-resolve-deps.sh [옵션]
#
# 옵션:
#   --modules=<모듈,목록>   빌드할 모듈 지정 (콤마 구분, 기본값: deps/ 전체 자동 탐색)
#   --with-sources          소스 JAR 도 함께 다운로드
#   --with-javadoc          JavaDoc JAR 도 함께 다운로드
#
# 예시:
#   bash scripts/01-resolve-deps.sh
#   bash scripts/01-resolve-deps.sh --modules=deps/spring-boot-web
#   bash scripts/01-resolve-deps.sh --modules=deps/spring-boot-web,deps/spring-boot-security
#   bash scripts/01-resolve-deps.sh --modules=deps/spring-boot-web --with-sources
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

INCLUDE_SOURCES=false
INCLUDE_JAVADOC=false
MODULES=""

for arg in "$@"; do
    case $arg in
        --modules=*) MODULES="${arg#*=}" ;;
        --with-sources) INCLUDE_SOURCES=true ;;
        --with-javadoc) INCLUDE_JAVADOC=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# 모듈 목록 결정: 지정되지 않으면 deps/ 하위 전체 자동 탐색
if [ -n "$MODULES" ]; then
    IFS=',' read -ra MODULE_LIST <<< "$MODULES"
else
    MODULE_LIST=()
    for pom in deps/*/pom.xml; do
        MODULE_LIST+=("$(dirname "$pom")")
    done
fi

echo "=============================================="
echo "  Maven 의존성 다운로드 시작"
echo "  프로젝트  : $PROJECT_ROOT"
echo "  대상 모듈 : ${MODULES:-전체 (자동 탐색)}"
echo "  소스 포함 : $INCLUDE_SOURCES"
echo "  JavaDoc 포함: $INCLUDE_JAVADOC"
echo "=============================================="

TOTAL_COUNT=0
LOG_FILE="$PROJECT_ROOT/output/resolve-deps.log"
mkdir -p "$PROJECT_ROOT/output"
> "$LOG_FILE"

for module in "${MODULE_LIST[@]}"; do
    POM="$PROJECT_ROOT/$module/pom.xml"

    if [ ! -f "$POM" ]; then
        echo "WARNING: pom.xml 을 찾을 수 없어 건너뜁니다 → $POM"
        continue
    fi

    echo ""
    echo "--------------------------------------------------------------"
    echo "  [$module]"
    echo "--------------------------------------------------------------"

    # 의존성 목록을 임시 파일로 수집 (로그용)
    TEMP_LIST="$PROJECT_ROOT/output/.resolve-temp.txt"
    > "$TEMP_LIST"
    mvn dependency:list \
        -f "$POM" \
        -DincludeScope=runtime \
        -Dsort=true \
        -DoutputFile="$TEMP_LIST" \
        -q

    # 패키지 목록 파싱 및 출력
    MODULE_COUNT=0
    echo "" >> "$LOG_FILE"
    echo "[$module]" >> "$LOG_FILE"

    while IFS= read -r line; do
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$line" || "$line" == The* || "$line" == none ]] && continue
        echo "  $line"
        echo "  $line" >> "$LOG_FILE"
        MODULE_COUNT=$((MODULE_COUNT + 1))
    done < "$TEMP_LIST"

    echo "  → 총 ${MODULE_COUNT}개"
    echo "  → 총 ${MODULE_COUNT}개" >> "$LOG_FILE"
    TOTAL_COUNT=$((TOTAL_COUNT + MODULE_COUNT))

    # Step 1) 의존성 resolve
    mvn dependency:resolve -f "$POM" --fail-at-end -T 4 -q

    # Step 2) 소스 다운로드 (선택)
    if [ "$INCLUDE_SOURCES" = true ]; then
        mvn dependency:resolve-sources -f "$POM" --fail-at-end -T 4 -q
    fi

    # Step 3) JavaDoc 다운로드 (선택)
    if [ "$INCLUDE_JAVADOC" = true ]; then
        mvn dependency:resolve -Dclassifier=javadoc -f "$POM" --fail-at-end -T 4 -q
    fi

    # Step 4) go-offline (플러그인 포함)
    mvn dependency:go-offline -f "$POM" --fail-at-end -q

    echo "  완료: $module"
done

echo ""
echo "=============================================="
echo "  완료! 로컬 .m2 레포지토리에 저장되었습니다."
echo "  경로  : $HOME/.m2/repository"
echo "  총 의존성: ${TOTAL_COUNT}개"
echo "  로그  : $LOG_FILE"
echo "=============================================="
