#!/usr/bin/env bash
# =============================================================================
# 02-export-m2.sh
# 목적: 로컬 .m2/repository 에서 지정 모듈의 의존성만 추출하여
#       output/maven_repository 디렉터리에 복사
#
# 사용:
#   bash scripts/02-export-m2.sh [옵션]
#
# 옵션:
#   --modules=<모듈,목록>   대상 모듈 지정 (콤마 구분, 기본값: deps/ 전체 자동 탐색)
#   --clean                 output 디렉터리 초기화 후 복사
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

LOCAL_M2="$HOME/.m2/repository"
OUTPUT_DIR="$PROJECT_ROOT/output/maven_repository"
CLEAN_BEFORE=false
MODULES=""

for arg in "$@"; do
    case $arg in
        --modules=*) MODULES="${arg#*=}" ;;
        --clean) CLEAN_BEFORE=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# 모듈 목록 결정
if [ -n "$MODULES" ]; then
    IFS=',' read -ra MODULE_LIST <<< "$MODULES"
else
    MODULE_LIST=()
    for pom in deps/*/pom.xml; do
        MODULE_LIST+=("$(dirname "$pom")")
    done
fi

echo "=============================================="
echo "  .m2 → output/maven_repository 내보내기 시작"
echo "  소스: $LOCAL_M2"
echo "  대상: $OUTPUT_DIR"
echo "  대상 모듈: ${MODULES:-전체 (자동 탐색)}"
echo "=============================================="

if [ "$CLEAN_BEFORE" = true ] && [ -d "$OUTPUT_DIR" ]; then
    echo ""
    echo "[Step 0] 기존 output 디렉터리 삭제..."
    rm -rf "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"

DEPS_LIST_FILE="$PROJECT_ROOT/output/.deps-list.txt"
> "$DEPS_LIST_FILE"

# -----------------------------------------------------------------------
# Step 1. 각 모듈에서 GAV 목록 수집
#   dependency:list 출력 형식:
#     groupId:artifactId:type:version:scope             (classifier 없음)
#     groupId:artifactId:type:classifier:version:scope  (classifier 있음)
# -----------------------------------------------------------------------
echo ""
echo "[Step 1] 각 모듈의 의존성 목록 수집..."

for module in "${MODULE_LIST[@]}"; do
    POM="$PROJECT_ROOT/$module/pom.xml"

    if [ ! -f "$POM" ]; then
        echo "WARNING: pom.xml 을 찾을 수 없어 건너뜁니다 → $POM"
        continue
    fi

    echo "  → $module"
    mvn dependency:list \
        -f "$POM" \
        -DincludeScope=runtime \
        -Dsort=true \
        -DappendOutput=true \
        -DoutputFile="$DEPS_LIST_FILE" \
        -q
done

echo "  수집 완료: $DEPS_LIST_FILE"

# -----------------------------------------------------------------------
# Step 2. GAV 좌표에서 .m2 경로를 직접 재구성하여 복사
#   Windows 경로의 콜론(:) 문제를 피하기 위해
#   절대 경로 대신 GAV 파싱 방식 사용
# -----------------------------------------------------------------------
echo ""
echo "[Step 2] 아티팩트를 output 디렉터리로 복사..."

COPIED=0
SKIPPED=0

copy_with_meta() {
    local SRC="$1"
    local DEST="$2"

    if [ ! -f "$SRC" ]; then
        return 1
    fi

    mkdir -p "$(dirname "$DEST")"
    cp -p "$SRC" "$DEST"

    # .pom, .sha1, .md5 메타파일도 함께 복사
    local BASE="${SRC%.*}"
    local EXT="${SRC##*.}"
    for META_EXT in pom "pom.sha1" "pom.md5" "${EXT}.sha1" "${EXT}.md5"; do
        local META="$BASE.$META_EXT"
        # pom 파일 자체는 별도로 처리
        if [[ "$META_EXT" == "pom" ]]; then
            META="${BASE%%-*}"
            # 재구성: artifactId-version.pom
            local DIR
            DIR="$(dirname "$SRC")"
            local FNAME
            FNAME="$(basename "$SRC")"
            local POM_FILE="$DIR/${FNAME%.*}.pom"
            if [ -f "$POM_FILE" ]; then
                cp -p "$POM_FILE" "$(dirname "$DEST")/${FNAME%.*}.pom" 2>/dev/null || true
            fi
            continue
        fi
        if [ -f "$META" ]; then
            cp -p "$META" "$(dirname "$DEST")/$(basename "$META")" 2>/dev/null || true
        fi
    done
    return 0
}

while IFS= read -r line; do
    # 앞뒤 공백 제거
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # 빈 줄 또는 헤더 텍스트 건너뜀
    [[ -z "$line" || "$line" == The* || "$line" == none ]] && continue

    # 콜론으로 분리
    IFS=':' read -ra PARTS <<< "$line"

    GROUP_ID=""
    ARTIFACT_ID=""
    TYPE=""
    CLASSIFIER=""
    VERSION=""

    if [ "${#PARTS[@]}" -eq 5 ]; then
        # groupId:artifactId:type:version:scope
        GROUP_ID="${PARTS[0]}"
        ARTIFACT_ID="${PARTS[1]}"
        TYPE="${PARTS[2]}"
        VERSION="${PARTS[3]}"
        FILENAME="${ARTIFACT_ID}-${VERSION}.${TYPE}"

    elif [ "${#PARTS[@]}" -eq 6 ]; then
        # groupId:artifactId:type:classifier:version:scope
        GROUP_ID="${PARTS[0]}"
        ARTIFACT_ID="${PARTS[1]}"
        TYPE="${PARTS[2]}"
        CLASSIFIER="${PARTS[3]}"
        VERSION="${PARTS[4]}"
        FILENAME="${ARTIFACT_ID}-${VERSION}-${CLASSIFIER}.${TYPE}"
    else
        continue
    fi

    # groupId 의 . 을 / 로 변환하여 디렉터리 경로 구성
    GROUP_PATH="${GROUP_ID//.//}"
    ARTIFACT_DIR="$LOCAL_M2/$GROUP_PATH/$ARTIFACT_ID/$VERSION"
    SRC="$ARTIFACT_DIR/$FILENAME"

    DEST_DIR="$OUTPUT_DIR/$GROUP_PATH/$ARTIFACT_ID/$VERSION"
    DEST="$DEST_DIR/$FILENAME"

    if copy_with_meta "$SRC" "$DEST"; then
        COPIED=$((COPIED + 1))
    else
        SKIPPED=$((SKIPPED + 1))
    fi

done < "$DEPS_LIST_FILE"

echo "  복사: ${COPIED}개 / 건너뜀: ${SKIPPED}개"

echo ""
echo "[Step 3] 결과 확인..."
FILE_COUNT=$(find "$OUTPUT_DIR" -type f | wc -l)
SIZE=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
echo "  총 파일 수: $FILE_COUNT"
echo "  총 용량   : $SIZE"

echo ""
echo "=============================================="
echo "  완료! 내보내기 경로: $OUTPUT_DIR"
echo "  다음 단계: bash scripts/03-package-for-transfer.sh"
echo "=============================================="
