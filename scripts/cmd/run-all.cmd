@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
REM =============================================================================
REM run-all.cmd - Run scripts 01 and 03 in order
REM =============================================================================

set "SCRIPT_DIR=%~dp0"

set "ARGS_STEP1="
set "ARGS_STEP3="

:parse_args
if "%~1"=="" goto :args_done
if "%~1"=="--modules" goto :arg_modules
if "%~1"=="--with-sources" goto :arg_sources
if "%~1"=="--with-javadoc" goto :arg_javadoc
if "%~1"=="--clean" goto :arg_clean
if "%~1"=="--format" goto :arg_format
if "%~1"=="--help" goto :show_help
if "%~1"=="-h" goto :show_help
echo [오류] 알 수 없는 옵션: %~1
echo   --help 로 사용법을 확인하세요.
exit /b 1

:arg_modules
shift
if "%~1"=="" goto :missing_modules
set "CHK=%~1"
if "!CHK:~0,2!"=="--" goto :missing_modules
set "ARGS_STEP1=!ARGS_STEP1! --modules %~1"
shift
goto :parse_args

:missing_modules
echo [오류] --modules 뒤에 값이 필요합니다.
echo   예시: --modules deps/nl2sql-api
exit /b 1

:arg_sources
set "ARGS_STEP1=!ARGS_STEP1! --with-sources"
shift
goto :parse_args

:arg_javadoc
set "ARGS_STEP1=!ARGS_STEP1! --with-javadoc"
shift
goto :parse_args

:arg_clean
set "ARGS_STEP1=!ARGS_STEP1! --clean"
shift
goto :parse_args

:arg_format
shift
if "%~1"=="" goto :missing_format
set "ARGS_STEP3=!ARGS_STEP3! --format %~1"
shift
goto :parse_args

:missing_format
echo [오류] --format 뒤에 값이 필요합니다 (zip 또는 tar.gz).
exit /b 1

:args_done

echo.
echo ================================================================
echo   [Step 1/2] 의존성 다운로드 중...
echo ================================================================
call "%SCRIPT_DIR%01-resolve-deps.cmd" !ARGS_STEP1!
if errorlevel 1 (
    echo [오류] Step 1 실패. 중단합니다.
    exit /b 1
)

echo.
echo ================================================================
echo   [Step 2/2] 전송용 패키지 생성 중...
echo ================================================================
call "%SCRIPT_DIR%03-package-for-transfer.cmd" !ARGS_STEP3!
if errorlevel 1 (
    echo [오류] Step 2 실패. 중단합니다.
    exit /b 1
)

echo.
echo ================================================================
echo   모든 단계가 성공적으로 완료되었습니다!
echo ================================================================

endlocal
exit /b 0

:show_help
echo 사용법: scripts\cmd\run-all.cmd [옵션]
echo.
echo 옵션:
echo   --modules 값         빌드할 모듈 지정 (콤마 구분)
echo                        기본값: deps\ 하위 전체 자동 탐색
echo   --with-sources       소스 JAR 도 함께 다운로드
echo   --with-javadoc       JavaDoc JAR 도 함께 다운로드
echo   --clean              다운로드 전 output\maven_repository 초기화
echo   --format 값          압축 형식: zip 또는 tar.gz (기본값: zip)
echo   --help               이 도움말 표시
echo.
echo 예시:
echo   scripts\cmd\run-all.cmd
echo   scripts\cmd\run-all.cmd --modules deps/nl2sql-api --clean
echo   scripts\cmd\run-all.cmd --modules deps/a,deps/b --with-sources --clean
exit /b 0
