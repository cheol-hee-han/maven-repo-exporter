#!/usr/bin/env bash
# =============================================================================
# run-all.sh
# 목적: 01 ~ 03 스크립트를 순서대로 실행
#
# 사용:
#   bash scripts/run-all.sh [옵션]
#
# 옵션:
#   --modules=<모듈,목록>   빌드할 모듈 지정 (콤마 구분, 기본값: 전체)
#   --with-sources          소스 JAR 도 함께 다운로드
#   --with-javadoc          JavaDoc JAR 도 함께 다운로드
#   --clean                 export 전 output 디렉터리 초기화
#   --format=zip|tar.gz     압축 형식 지정 (기본값: tar.gz)
#
# 예시:
#   bash scripts/run-all.sh
#   bash scripts/run-all.sh --modules=deps/spring-boot-web --clean
#   bash scripts/run-all.sh --modules=deps/spring-boot-web,deps/spring-boot-security --clean
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARGS_STEP1=()
ARGS_STEP2=()
ARGS_STEP3=()

for arg in "$@"; do
    case $arg in
        --modules=*)    ARGS_STEP1+=("$arg"); ARGS_STEP2+=("$arg") ;;  # 01, 02 모두 전달
        --with-sources) ARGS_STEP1+=("$arg") ;;
        --with-javadoc) ARGS_STEP1+=("$arg") ;;
        --clean)        ARGS_STEP2+=("$arg") ;;
        --format=*)     ARGS_STEP3+=("$arg") ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# Step 1. 의존성 다운로드 (인터넷 → 로컬 .m2)
bash "$SCRIPT_DIR/01-resolve-deps.sh" "${ARGS_STEP1[@]+"${ARGS_STEP1[@]}"}"

# Step 2. 의존성 추출 (.m2 → output/maven_repository)
bash "$SCRIPT_DIR/02-export-m2.sh" "${ARGS_STEP2[@]+"${ARGS_STEP2[@]}"}"

# Step 3. 전송용 패키지 생성 (output → .tar.gz)
bash "$SCRIPT_DIR/03-package-for-transfer.sh" "${ARGS_STEP3[@]+"${ARGS_STEP3[@]}"}"
