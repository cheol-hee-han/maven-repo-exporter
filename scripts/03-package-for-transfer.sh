#!/usr/bin/env bash
# =============================================================================
# 03-package-for-transfer.sh
# 목적: output/maven_repository 를 압축하여 폐쇄망 서버 전송용 패키지 생성
# 사용: bash scripts/03-package-for-transfer.sh [--format tar.gz|zip]
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

OUTPUT_DIR="$PROJECT_ROOT/output/maven_repository"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FORMAT="tar.gz"   # 기본: tar.gz (zip 도 가능)

for arg in "$@"; do
    case $arg in
        --format=*) FORMAT="${arg#*=}" ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: $OUTPUT_DIR 가 없습니다. 먼저 02-export-m2.sh 를 실행하세요."
    exit 1
fi

ARCHIVE_BASE="$PROJECT_ROOT/output/maven_repository_${TIMESTAMP}"

echo "=============================================="
echo "  전송용 패키지 생성"
echo "  소스: $OUTPUT_DIR"
echo "  형식: $FORMAT"
echo "=============================================="

case "$FORMAT" in
    tar.gz)
        ARCHIVE="${ARCHIVE_BASE}.tar.gz"
        echo ""
        echo "압축 중... (tar.gz)"
        tar -czf "$ARCHIVE" -C "$PROJECT_ROOT/output" maven_repository
        ;;
    zip)
        ARCHIVE="${ARCHIVE_BASE}.zip"
        echo ""
        echo "압축 중... (zip)"
        if ! command -v zip &>/dev/null; then
            echo "ERROR: zip 명령어를 찾을 수 없습니다."
            exit 1
        fi
        cd "$PROJECT_ROOT/output"
        zip -r "$ARCHIVE" maven_repository
        cd "$PROJECT_ROOT"
        ;;
    *)
        echo "ERROR: 지원하지 않는 형식입니다: $FORMAT (tar.gz 또는 zip 사용)"
        exit 1
        ;;
esac

SIZE=$(du -sh "$ARCHIVE" 2>/dev/null | cut -f1)

echo ""
echo "=============================================="
echo "  완료!"
echo "  생성 파일: $ARCHIVE"
echo "  파일 크기: $SIZE"
echo ""
echo "  [폐쇄망 서버 배포 방법]"
echo "  1. 위 아카이브를 USB/물리매체로 폐쇄망 서버에 전달"
echo "  2. 서버에서 압축 해제:"
echo "     tar -xzf $(basename "$ARCHIVE") -C /경로/maven_repository"
echo "  3. 서버 settings.xml 에 localRepository 경로 설정"
echo "=============================================="
