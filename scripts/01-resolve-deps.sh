#!/usr/bin/env bash
# =============================================================================
# 01-resolve-deps.sh
# 목적: 지정한 모듈(또는 전체 모듈)의 의존성을 output/maven_repository 로 직접 다운로드
#       -Dmaven.repo.local 을 사용하여 BOM/부모 pom 포함 모든 아티팩트를 수집
#
# 사용:
#   bash scripts/01-resolve-deps.sh [옵션]
#
# 옵션:
#   --modules=<모듈,목록>   빌드할 모듈 지정 (콤마 구분, 기본값: deps/ 전체 자동 탐색)
#   --with-sources          소스 JAR 도 함께 다운로드
#   --with-javadoc          JavaDoc JAR 도 함께 다운로드
#   --clean                 다운로드 전 output/maven_repository 초기화
#
# 예시:
#   bash scripts/01-resolve-deps.sh
#   bash scripts/01-resolve-deps.sh --modules=deps/spring-boot-web
#   bash scripts/01-resolve-deps.sh --modules=deps/spring-boot-web,deps/spring-boot-security
#   bash scripts/01-resolve-deps.sh --modules=deps/spring-boot-web --with-sources --clean
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

INCLUDE_SOURCES=false
INCLUDE_JAVADOC=false
CLEAN_BEFORE=false
MODULES=""
OUTPUT_DIR="$PROJECT_ROOT/output/maven_repository"

for arg in "$@"; do
    case $arg in
        --modules=*) MODULES="${arg#*=}" ;;
        --with-sources) INCLUDE_SOURCES=true ;;
        --with-javadoc) INCLUDE_JAVADOC=true ;;
        --clean) CLEAN_BEFORE=true ;;
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
echo "  Maven 의존성 다운로드"
echo "  프로젝트  : $PROJECT_ROOT"
echo "  대상 모듈 : ${MODULES:-전체 (자동 탐색)}"
echo "  출력 경로 : $OUTPUT_DIR"
echo "  소스 포함 : $INCLUDE_SOURCES"
echo "  JavaDoc   : $INCLUDE_JAVADOC"
echo "=============================================="

if [ "$CLEAN_BEFORE" = true ] && [ -d "$OUTPUT_DIR" ]; then
    echo ""
    echo "기존 output 디렉터리 삭제..."
    rm -rf "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"

TOTAL_COUNT=0
LOG_FILE="$PROJECT_ROOT/output/resolve-deps.log"
> "$LOG_FILE"

FAILED=0

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
        -Dmaven.repo.local="$OUTPUT_DIR" \
        -q || true

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

    # 의존성 resolve (BOM, 부모 pom 포함 모든 아티팩트 다운로드)
    mvn dependency:resolve \
        -f "$POM" \
        -Dmaven.repo.local="$OUTPUT_DIR" \
        --fail-at-end -T 4 -q || FAILED=$((FAILED + 1))

    # 소스 다운로드 (선택)
    if [ "$INCLUDE_SOURCES" = true ]; then
        mvn dependency:resolve-sources \
            -f "$POM" \
            -Dmaven.repo.local="$OUTPUT_DIR" \
            --fail-at-end -T 4 -q || true
    fi

    # JavaDoc 다운로드 (선택)
    if [ "$INCLUDE_JAVADOC" = true ]; then
        mvn dependency:resolve -Dclassifier=javadoc \
            -f "$POM" \
            -Dmaven.repo.local="$OUTPUT_DIR" \
            --fail-at-end -T 4 -q || true
    fi

    # go-offline (플러그인 포함 전체 오프라인 준비)
    mvn dependency:go-offline \
        -f "$POM" \
        -Dmaven.repo.local="$OUTPUT_DIR" \
        --fail-at-end -q || FAILED=$((FAILED + 1))

    echo "  완료: $module"
done

# _remote.repositories 메타데이터 정리
echo ""
echo "메타데이터 정리 중..."
find "$OUTPUT_DIR" -name "_remote.repositories" -delete 2>/dev/null || true

FILE_COUNT=$(find "$OUTPUT_DIR" -type f | wc -l)
SIZE=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)

echo ""
echo "=============================================="
echo "  완료! 의존성이 output 디렉터리에 저장되었습니다."
echo "  경로      : $OUTPUT_DIR"
echo "  총 의존성 : ${TOTAL_COUNT}개"
echo "  총 파일 수: ${FILE_COUNT}"
echo "  총 용량   : ${SIZE}"
echo "  로그      : $LOG_FILE"
if [ $FAILED -gt 0 ]; then
    echo "  [경고] ${FAILED}개 Maven 단계에서 오류가 발생했습니다."
fi
echo "=============================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi
