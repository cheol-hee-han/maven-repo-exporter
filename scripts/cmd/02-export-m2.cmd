@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
REM =============================================================================
REM 02-export-m2.cmd
REM Export dependencies from local .m2/repository to output\maven_repository
REM =============================================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%..\.."
set "PROJECT_ROOT=%CD%"
popd
cd /d "%PROJECT_ROOT%"

set "LOCAL_M2=%USERPROFILE%\.m2\repository"
set "OUTPUT_DIR=%PROJECT_ROOT%\output\maven_repository"
set "CLEAN_BEFORE=false"
set "MODULES="

:parse_args
if "%~1"=="" goto :args_done
if "%~1"=="--modules" goto :arg_modules
if "%~1"=="--clean" goto :arg_clean
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
set "MODULES=%~1"
shift
goto :parse_args

:missing_modules
echo [오류] --modules 뒤에 값이 필요합니다.
echo   예시: --modules deps/nl2sql-api
exit /b 1

:arg_clean
set "CLEAN_BEFORE=true"
shift
goto :parse_args

:args_done

REM Validate prerequisites
where mvn >nul 2>&1
if errorlevel 1 (
    echo [오류] mvn 명령어를 찾을 수 없습니다. Maven 을 설치하고 PATH 에 추가하세요.
    exit /b 1
)

if not exist "%LOCAL_M2%" (
    echo [오류] 로컬 .m2 레포지토리를 찾을 수 없습니다: %LOCAL_M2%
    echo   먼저 01-resolve-deps.cmd 를 실행하여 의존성을 다운로드하세요.
    exit /b 1
)

REM Determine module list
set "MODULE_COUNT=0"
if not "!MODULES!"=="" (
    for %%m in ("!MODULES:,=" "!") do (
        set "MODULE_LIST[!MODULE_COUNT!]=%%~m"
        set /a MODULE_COUNT+=1
    )
) else (
    for /d %%d in (deps\*) do (
        if exist "%%d\pom.xml" (
            set "MODULE_LIST[!MODULE_COUNT!]=%%d"
            set /a MODULE_COUNT+=1
        )
    )
)

if !MODULE_COUNT! equ 0 (
    echo [오류] 모듈을 찾을 수 없습니다. deps\ 하위에 pom.xml 이 있는 모듈이 있는지 확인하세요.
    exit /b 1
)

set "MODULES_DISPLAY=!MODULES!"
if "!MODULES_DISPLAY!"=="" set "MODULES_DISPLAY=전체 (자동 탐색)"

echo ==============================================
echo   .m2 → output\maven_repository 내보내기
echo   소스   : %LOCAL_M2%
echo   대상   : %OUTPUT_DIR%
echo   모듈   : !MODULES_DISPLAY!
echo ==============================================

if "!CLEAN_BEFORE!"=="true" (
    if exist "%OUTPUT_DIR%" (
        echo.
        echo [Step 0] 기존 output 디렉터리 삭제...
        rmdir /s /q "%OUTPUT_DIR%"
    )
)

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

set "DEPS_LIST_FILE=%PROJECT_ROOT%\output\.deps-list.txt"
type nul > "%DEPS_LIST_FILE%"

echo.
echo [Step 1] 각 모듈의 의존성 목록 수집...

set /a LOOP_END=MODULE_COUNT-1
for /l %%i in (0,1,!LOOP_END!) do (
    set "MODULE=!MODULE_LIST[%%i]!"
    set "POM=%PROJECT_ROOT%\!MODULE!\pom.xml"

    if not exist "!POM!" (
        echo [경고] pom.xml 을 찾을 수 없어 건너뜁니다: !POM!
    ) else (
        echo   → !MODULE!
        call mvn dependency:list -f "!POM!" -DincludeScope=runtime -Dsort=true -DappendOutput=true -DoutputFile="%DEPS_LIST_FILE%" -q
    )
)

echo   수집 완료: %DEPS_LIST_FILE%

echo.
echo [Step 2] 아티팩트를 output 디렉터리로 복사...

set "COPIED=0"
set "SKIPPED=0"

for /f "usebackq delims=" %%L in ("%DEPS_LIST_FILE%") do (
    set "LINE=%%L"
    for /f "tokens=* delims= " %%a in ("!LINE!") do set "LINE=%%a"

    if not "!LINE!"=="" if not "!LINE:~0,3!"=="The" if not "!LINE!"=="none" (
        call :process_dep "!LINE!"
    )
)

echo   복사: !COPIED!개 / 건너뜀: !SKIPPED!개

echo.
echo [Step 3] 결과 확인...

set "FILE_COUNT=0"
for /r "%OUTPUT_DIR%" %%f in (*) do set /a FILE_COUNT+=1
echo   총 파일 수: !FILE_COUNT!

if !COPIED! equ 0 (
    echo   [경고] 복사된 아티팩트가 없습니다. .m2 캐시에 의존성이 없을 수 있습니다.
    echo   먼저 01-resolve-deps.cmd 를 실행하세요.
)

echo.
echo ==============================================
echo   완료! 내보내기 경로: %OUTPUT_DIR%
echo   다음 단계: scripts\cmd\03-package-for-transfer.cmd
echo ==============================================

endlocal
exit /b 0

:process_dep
set "DEP_LINE=%~1"

set "FIELD_IDX=0"
for %%p in ("!DEP_LINE::=" "!") do (
    set "PART[!FIELD_IDX!]=%%~p"
    set /a FIELD_IDX+=1
)

set "GROUP_ID="
set "ARTIFACT_ID="
set "TYPE="
set "CLASSIFIER="
set "VERSION="
set "FILENAME="

if !FIELD_IDX! equ 5 (
    set "GROUP_ID=!PART[0]!"
    set "ARTIFACT_ID=!PART[1]!"
    set "TYPE=!PART[2]!"
    set "VERSION=!PART[3]!"
    set "FILENAME=!PART[1]!-!PART[3]!.!PART[2]!"
) else if !FIELD_IDX! equ 6 (
    set "GROUP_ID=!PART[0]!"
    set "ARTIFACT_ID=!PART[1]!"
    set "TYPE=!PART[2]!"
    set "CLASSIFIER=!PART[3]!"
    set "VERSION=!PART[4]!"
    set "FILENAME=!PART[1]!-!PART[4]!-!PART[3]!.!PART[2]!"
) else (
    exit /b 0
)

set "GROUP_PATH=!GROUP_ID:.=\!"
set "ARTIFACT_DIR=%LOCAL_M2%\!GROUP_PATH!\!ARTIFACT_ID!\!VERSION!"
set "SRC=!ARTIFACT_DIR!\!FILENAME!"

set "DEST_DIR=%OUTPUT_DIR%\!GROUP_PATH!\!ARTIFACT_ID!\!VERSION!"
set "DEST=!DEST_DIR!\!FILENAME!"

if not exist "!SRC!" (
    set /a SKIPPED+=1
    exit /b 0
)

if not exist "!DEST_DIR!" mkdir "!DEST_DIR!"
copy /y "!SRC!" "!DEST!" >nul 2>&1

set "POM_NAME=!ARTIFACT_ID!-!VERSION!.pom"
if exist "!ARTIFACT_DIR!\!POM_NAME!" (
    copy /y "!ARTIFACT_DIR!\!POM_NAME!" "!DEST_DIR!\!POM_NAME!" >nul 2>&1
)

for %%e in (sha1 md5) do (
    if exist "!SRC!.%%e" (
        copy /y "!SRC!.%%e" "!DEST!.%%e" >nul 2>&1
    )
    if exist "!ARTIFACT_DIR!\!POM_NAME!.%%e" (
        copy /y "!ARTIFACT_DIR!\!POM_NAME!.%%e" "!DEST_DIR!\!POM_NAME!.%%e" >nul 2>&1
    )
)

set /a COPIED+=1
exit /b 0

:show_help
echo 사용법: scripts\cmd\02-export-m2.cmd [옵션]
echo.
echo 옵션:
echo   --modules 값       대상 모듈 지정 (콤마 구분)
echo                      기본값: deps\ 하위 전체 자동 탐색
echo   --clean            output 디렉터리 초기화 후 복사
echo   --help             이 도움말 표시
echo.
echo 예시:
echo   scripts\cmd\02-export-m2.cmd
echo   scripts\cmd\02-export-m2.cmd --modules deps/nl2sql-api --clean
exit /b 0
