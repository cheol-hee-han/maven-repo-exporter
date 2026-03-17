@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
REM =============================================================================
REM 03-package-for-transfer.cmd
REM 목적: output\maven_repository 를 압축하여 폐쇄망 서버 전송용 패키지 생성
REM
REM 사용:
REM   scripts\cmd\03-package-for-transfer.cmd [옵션]
REM
REM 옵션:
REM   --format 값            압축 형식: zip 또는 tar.gz (기본값: zip)
REM
REM 예시:
REM   scripts\cmd\03-package-for-transfer.cmd
REM   scripts\cmd\03-package-for-transfer.cmd --format tar.gz
REM =============================================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%..\.."
set "PROJECT_ROOT=%CD%"
popd
cd /d "%PROJECT_ROOT%"

set "OUTPUT_DIR=%PROJECT_ROOT%\output\maven_repository"
set "FORMAT=zip"

:parse_args
if "%~1"=="" goto :args_done
if "%~1"=="--format" goto :arg_format
if "%~1"=="--help" goto :show_help
if "%~1"=="-h" goto :show_help
echo [오류] 알 수 없는 옵션: %~1
echo   --help 로 사용법을 확인하세요.
exit /b 1

:arg_format
shift
if "%~1"=="" goto :missing_format
set "FORMAT=%~1"
if not "%FORMAT%"=="zip" if not "%FORMAT%"=="tar.gz" (
    echo [오류] 지원하지 않는 형식입니다: %FORMAT% - zip 또는 tar.gz 를 사용하세요.
    exit /b 1
)
shift
goto :parse_args

:missing_format
echo [오류] --format 뒤에 값이 필요합니다 (zip 또는 tar.gz).
exit /b 1

:args_done

if not exist "%OUTPUT_DIR%" (
    echo [오류] %OUTPUT_DIR% 가 없습니다.
    echo   먼저 01-resolve-deps.cmd 를 실행하여 의존성을 다운로드하세요.
    exit /b 1
)

REM Validate file count before packaging
set "PRE_COUNT=0"
for /r "%OUTPUT_DIR%" %%f in (*) do set /a PRE_COUNT+=1
if !PRE_COUNT! equ 0 (
    echo [오류] %OUTPUT_DIR% 가 비어 있습니다. 패키징할 파일이 없습니다.
    exit /b 1
)

REM Generate timestamp
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TIMESTAMP=%%a"
if "!TIMESTAMP!"=="" (
    echo [오류] 타임스탬프 생성에 실패했습니다. PowerShell 을 사용할 수 없습니다.
    exit /b 1
)

set "ARCHIVE_BASE=%PROJECT_ROOT%\output\maven_repository_%TIMESTAMP%"

echo ==============================================
echo   전송용 패키지 생성
echo   소스   : %OUTPUT_DIR%
echo   형식   : %FORMAT%
echo   파일 수: !PRE_COUNT!
echo ==============================================

if "%FORMAT%"=="tar.gz" goto :do_targz
if "%FORMAT%"=="zip" goto :do_zip

:do_targz
where tar >nul 2>&1
if errorlevel 1 (
    echo [오류] tar 명령어를 찾을 수 없습니다. Windows 10 1803 이상이 필요합니다.
    exit /b 1
)
set "ARCHIVE=%ARCHIVE_BASE%.tar.gz"
echo.
echo 압축 중... (tar.gz)
tar -czf "!ARCHIVE!" -C "%PROJECT_ROOT%\output" maven_repository
if errorlevel 1 (
    echo [오류] tar 압축에 실패했습니다.
    exit /b 1
)
goto :archive_done

:do_zip
set "ARCHIVE=%ARCHIVE_BASE%.zip"
echo.
echo 압축 중... (zip)
powershell -NoProfile -Command "Compress-Archive -Path '%OUTPUT_DIR%' -DestinationPath '!ARCHIVE!' -Force"
if errorlevel 1 (
    echo [오류] zip 압축에 실패했습니다.
    exit /b 1
)
goto :archive_done

:archive_done
if not exist "!ARCHIVE!" (
    echo [오류] 아카이브 파일이 생성되지 않았습니다.
    exit /b 1
)

for %%f in ("!ARCHIVE!") do set "SIZE=%%~zf"
set /a SIZE_MB=SIZE/1024/1024

echo.
echo ==============================================
echo   완료!
echo   생성 파일 : !ARCHIVE!
echo   파일 크기 : !SIZE_MB! MB
echo.
echo   [폐쇄망 서버 배포 방법]
echo   1. 위 아카이브를 USB/물리매체로 폐쇄망 서버에 전달
echo   2. 서버에서 압축 해제
echo   3. 서버 settings.xml 에 localRepository 경로 설정
echo ==============================================

endlocal
exit /b 0

:show_help
echo 사용법: scripts\cmd\03-package-for-transfer.cmd [옵션]
echo.
echo 옵션:
echo   --format 값        압축 형식: zip 또는 tar.gz (기본값: zip)
echo   --help             이 도움말 표시
echo.
echo 예시:
echo   scripts\cmd\03-package-for-transfer.cmd
echo   scripts\cmd\03-package-for-transfer.cmd --format tar.gz
exit /b 0
