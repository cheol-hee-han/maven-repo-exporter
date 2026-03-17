@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
REM =============================================================================
REM 01-resolve-deps.cmd
REM 목적: 지정한 모듈(또는 전체 모듈)의 의존성을 output\maven_repository 로 직접 다운로드
REM       -Dmaven.repo.local 을 사용하여 BOM/부모 pom 포함 모든 아티팩트를 수집
REM
REM 사용:
REM   scripts\cmd\01-resolve-deps.cmd [옵션]
REM
REM 옵션:
REM   --modules 값           빌드할 모듈 지정 (콤마 구분, 기본값: deps\ 전체 자동 탐색)
REM   --with-sources         소스 JAR 도 함께 다운로드
REM   --with-javadoc         JavaDoc JAR 도 함께 다운로드
REM   --clean                다운로드 전 output\maven_repository 초기화
REM
REM 예시:
REM   scripts\cmd\01-resolve-deps.cmd
REM   scripts\cmd\01-resolve-deps.cmd --modules deps/spring-boot-web
REM   scripts\cmd\01-resolve-deps.cmd --modules deps/a,deps/b --with-sources --clean
REM =============================================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%..\.."
set "PROJECT_ROOT=%CD%"
popd
cd /d "%PROJECT_ROOT%"

set "INCLUDE_SOURCES=false"
set "INCLUDE_JAVADOC=false"
set "CLEAN_BEFORE=false"
set "MODULES="
set "OUTPUT_DIR=%PROJECT_ROOT%\output\maven_repository"

:parse_args
if "%~1"=="" goto :args_done
if "%~1"=="--modules" goto :arg_modules
if "%~1"=="--with-sources" goto :arg_sources
if "%~1"=="--with-javadoc" goto :arg_javadoc
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

:arg_sources
set "INCLUDE_SOURCES=true"
shift
goto :parse_args

:arg_javadoc
set "INCLUDE_JAVADOC=true"
shift
goto :parse_args

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
echo   Maven 의존성 다운로드
echo   프로젝트  : %PROJECT_ROOT%
echo   대상 모듈 : !MODULES_DISPLAY!
echo   출력 경로 : %OUTPUT_DIR%
echo   소스 포함 : %INCLUDE_SOURCES%
echo   JavaDoc   : %INCLUDE_JAVADOC%
echo ==============================================

if "!CLEAN_BEFORE!"=="true" (
    if exist "%OUTPUT_DIR%" (
        echo.
        echo 기존 output 디렉터리 삭제...
        rmdir /s /q "%OUTPUT_DIR%"
    )
)

if not exist "%PROJECT_ROOT%\output" mkdir "%PROJECT_ROOT%\output"
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

set "TOTAL_COUNT=0"
set "LOG_FILE=%PROJECT_ROOT%\output\resolve-deps.log"
type nul > "%LOG_FILE%"

set "FAILED=0"
set /a LOOP_END=MODULE_COUNT-1
for /l %%i in (0,1,!LOOP_END!) do (
    set "MODULE=!MODULE_LIST[%%i]!"
    set "POM=%PROJECT_ROOT%\!MODULE!\pom.xml"

    if not exist "!POM!" (
        echo [경고] pom.xml 을 찾을 수 없어 건너뜁니다: !POM!
    ) else (
        echo.
        echo --------------------------------------------------------------
        echo   [!MODULE!]
        echo --------------------------------------------------------------

        set "TEMP_LIST=%PROJECT_ROOT%\output\.resolve-temp.txt"
        type nul > "!TEMP_LIST!"
        call mvn dependency:list -f "!POM!" -DincludeScope=runtime -Dsort=true -DoutputFile="!TEMP_LIST!" -Dmaven.repo.local="%OUTPUT_DIR%" -q

        set "MODULE_LINE_COUNT=0"
        echo. >> "%LOG_FILE%"
        echo [!MODULE!] >> "%LOG_FILE%"

        for /f "usebackq delims=" %%L in ("!TEMP_LIST!") do (
            set "LINE=%%L"
            for /f "tokens=* delims= " %%a in ("!LINE!") do set "LINE=%%a"
            if not "!LINE!"=="" if not "!LINE:~0,3!"=="The" if not "!LINE!"=="none" (
                echo   !LINE!
                echo   !LINE! >> "%LOG_FILE%"
                set /a MODULE_LINE_COUNT+=1
            )
        )

        echo   총 !MODULE_LINE_COUNT!개
        echo   총 !MODULE_LINE_COUNT!개 >> "%LOG_FILE%"
        set /a TOTAL_COUNT+=MODULE_LINE_COUNT

        call mvn dependency:resolve -f "!POM!" -Dmaven.repo.local="%OUTPUT_DIR%" --fail-at-end -T 4 -q
        if errorlevel 1 set /a FAILED+=1

        if "!INCLUDE_SOURCES!"=="true" (
            call mvn dependency:resolve-sources -f "!POM!" -Dmaven.repo.local="%OUTPUT_DIR%" --fail-at-end -T 4 -q
        )

        if "!INCLUDE_JAVADOC!"=="true" (
            call mvn dependency:resolve -Dclassifier=javadoc -f "!POM!" -Dmaven.repo.local="%OUTPUT_DIR%" --fail-at-end -T 4 -q
        )

        call mvn dependency:go-offline -f "!POM!" -Dmaven.repo.local="%OUTPUT_DIR%" --fail-at-end -q
        if errorlevel 1 set /a FAILED+=1

        echo   완료: !MODULE!
    )
)

REM _remote.repositories 메타데이터 정리
echo.
echo 메타데이터 정리 중...
for /r "%OUTPUT_DIR%" %%f in (_remote.repositories) do (
    if exist "%%f" del "%%f" 2>nul
)

set "FILE_COUNT=0"
for /r "%OUTPUT_DIR%" %%f in (*) do set /a FILE_COUNT+=1

echo.
echo ==============================================
echo   완료! 의존성이 output 디렉터리에 저장되었습니다.
echo   경로      : %OUTPUT_DIR%
echo   총 의존성 : !TOTAL_COUNT!개
echo   총 파일 수: !FILE_COUNT!
echo   로그      : %LOG_FILE%
if !FAILED! gtr 0 echo   [경고] !FAILED!개 Maven 단계에서 오류가 발생했습니다.
echo ==============================================

if !FAILED! gtr 0 exit /b 1
endlocal
exit /b 0

:show_help
echo 사용법: scripts\cmd\01-resolve-deps.cmd [옵션]
echo.
echo 옵션:
echo   --modules 값         빌드할 모듈 지정 (콤마 구분)
echo                        기본값: deps\ 하위 전체 자동 탐색
echo   --with-sources       소스 JAR 도 함께 다운로드
echo   --with-javadoc       JavaDoc JAR 도 함께 다운로드
echo   --clean              다운로드 전 output\maven_repository 초기화
echo   --help               이 도움말 표시
echo.
echo 예시:
echo   scripts\cmd\01-resolve-deps.cmd
echo   scripts\cmd\01-resolve-deps.cmd --modules deps/spring-boot-web
echo   scripts\cmd\01-resolve-deps.cmd --modules deps/a,deps/b --with-sources --clean
exit /b 0
