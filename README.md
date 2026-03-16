# Maven Repository Exporter

로컬 `.m2` 레포지토리로 Maven 의존성을 수집하고, 폐쇄망 서버의 `maven_repository`로 내보내기 위한 프로젝트입니다.

---

## 목차

- [개요](#개요)
- [프로젝트 구조](#프로젝트-구조)
- [사전 요구사항](#사전-요구사항)
- [의존성 세트 구성](#의존성-세트-구성)
- [**빠른 시작**](#빠른-시작)
- [사용 방법](#사용-방법)
  - [Step 1. 의존성 다운로드](#step-1-의존성-다운로드)
  - [Step 2. 의존성 추출](#step-2-의존성-추출)
  - [Step 3. 전송용 패키지 생성](#step-3-전송용-패키지-생성)
- [폐쇄망 서버 배포](#폐쇄망-서버-배포)
- [새 의존성 세트 추가](#새-의존성-세트-추가)
- [자주 묻는 질문](#자주-묻는-질문)

---

## 개요

```
[인터넷 연결 환경]                        [폐쇄망 환경]

  pom.xml 정의                            압축 해제
      ↓                                       ↓
  mvn dependency                        /opt/maven_repository
  :go-offline           USB/매체              ↓
      ↓           ──────────────────→   settings-offline.xml
  ~/.m2/repository                           ↓
      ↓                                  mvn package --offline
  output/maven_repository
      ↓
  maven_repository_YYYYMMDD.tar.gz
```

**동작 흐름:**

1. `deps/` 하위 모듈에 필요한 의존성을 선언합니다.
2. 스크립트를 실행하여 인터넷이 연결된 환경에서 로컬 `.m2`로 다운로드합니다.
3. 사용된 의존성만 `output/maven_repository`로 추출합니다.
4. 압축 후 물리 매체(USB 등)로 폐쇄망 서버에 전달합니다.
5. 폐쇄망 서버에서 압축 해제 후 오프라인 Maven 빌드에 활용합니다.

---

## 프로젝트 구조

```
maven-repo-exporter/
├── pom.xml                           # 루트 Parent POM
├── deps/                             # 의존성 세트 모듈
│   ├── spring-boot-web/
│   │   └── pom.xml                  # Spring Web MVC 관련 의존성
│   ├── spring-boot-data-jpa/
│   │   └── pom.xml                  # Spring Data JPA 관련 의존성
│   ├── spring-boot-security/
│   │   └── pom.xml                  # Spring Security / JWT 관련 의존성
│   └── spring-boot-batch/
│       └── pom.xml                  # Spring Batch 관련 의존성
├── scripts/
│   ├── 01-resolve-deps.sh           # 의존성 → 로컬 .m2 다운로드
│   ├── 02-export-m2.sh              # .m2 → output/maven_repository 추출
│   └── 03-package-for-transfer.sh  # output → 전송용 압축 파일 생성
├── settings-offline.xml             # 폐쇄망 서버용 Maven settings 템플릿
├── output/                          # 생성 결과물 (.gitignore 처리됨)
└── README.md
```

---

## 사전 요구사항

| 항목 | 버전 | 비고 |
|------|------|------|
| JDK | 17 이상 | `java -version` 으로 확인 |
| Apache Maven | 3.8 이상 | `mvn -version` 으로 확인 |
| Spring Boot | 3.4.5 | 루트 `pom.xml`에서 관리 |
| OS | Linux / macOS / Windows(Git Bash) | 스크립트는 bash 기준 |

---

## 의존성 세트 구성

각 모듈에 포함된 주요 의존성은 다음과 같습니다.

### `deps/spring-boot-web`

Spring Web MVC 기반 REST API 프로젝트에 필요한 의존성 세트입니다.

| 의존성 | 설명 |
|--------|------|
| `spring-boot-starter-web` | Spring MVC + 내장 Tomcat |
| `spring-boot-starter-validation` | Bean Validation (JSR-380) |
| `spring-boot-starter-actuator` | 애플리케이션 모니터링 엔드포인트 |
| `spring-boot-devtools` | 개발 편의 도구 (hot reload 등) |
| `lombok` | 보일러플레이트 코드 제거 |

### `deps/spring-boot-data-jpa`

관계형 DB 연동 및 ORM에 필요한 의존성 세트입니다.

| 의존성 | 설명 |
|--------|------|
| `spring-boot-starter-data-jpa` | Spring Data JPA + Hibernate |
| `h2` | 인메모리 DB (개발/테스트용) |
| `mysql-connector-j` | MySQL 드라이버 |
| `postgresql` | PostgreSQL 드라이버 |
| `flyway-core` | DB 스키마 버전 관리 |
| `querydsl-jpa` | 타입 안전한 동적 쿼리 |
| `lombok` | 보일러플레이트 코드 제거 |

### `deps/spring-boot-security`

인증/인가 처리에 필요한 의존성 세트입니다.

| 의존성 | 버전 | 설명 |
|--------|------|------|
| `spring-boot-starter-security` | (BOM 관리) | Spring Security 코어 |
| `spring-boot-starter-web` | (BOM 관리) | Security 필터 체인 기반 |
| `spring-security-test` | (BOM 관리) | Security 테스트 지원 |
| `jjwt-api` / `jjwt-impl` / `jjwt-jackson` | `0.12.6` | JWT 생성 및 검증 |
| `spring-boot-starter-oauth2-client` | (BOM 관리) | OAuth2 / OpenID Connect |
| `lombok` | (BOM 관리) | 보일러플레이트 코드 제거 |

### `deps/spring-boot-batch`

배치 처리에 필요한 의존성 세트입니다.

| 의존성 | 설명 |
|--------|------|
| `spring-boot-starter-batch` | Spring Batch 코어 |
| `spring-boot-starter-data-jpa` | Batch JobRepository DB 연동 |
| `h2` | Batch 메타 테이블 인메모리 저장 |
| `mysql-connector-j` | MySQL 드라이버 |
| `spring-boot-starter-quartz` | Batch 스케줄링 |
| `lombok` | 보일러플레이트 코드 제거 |

---

## 빠른 시작

> 가장 기본적인 사용법입니다. 처음 실행하거나 결과를 새로 만들 때 사용하세요.

```bash
bash scripts/run-all.sh --modules=deps/<의존성폴더> --clean
```

**예시:**

```bash
# Spring Web 의존성만 수집
bash scripts/run-all.sh --modules=deps/spring-boot-web --clean

# 여러 모듈 동시 수집
bash scripts/run-all.sh --modules=deps/spring-boot-web,deps/spring-boot-security --clean
```

| 옵션 | 설명 |
|------|------|
| `--modules=deps/<폴더>` | 수집할 의존성 모듈 지정. 콤마로 여러 개 지정 가능 |
| `--clean` | 기존 `output/` 을 초기화하고 새로 생성 |

> 옵션을 생략하면 `deps/` 하위 **전체 모듈**을 대상으로 실행됩니다.
> ```bash
> bash scripts/run-all.sh
> ```

---

## 사용 방법

> **주의:** Step 1 ~ Step 3은 모두 **인터넷이 연결된 환경**에서 실행합니다.

### Step 1. 의존성 다운로드

모든 모듈의 의존성을 로컬 `~/.m2/repository`로 다운로드합니다.

```bash
# 기본 (JAR만 다운로드)
bash scripts/01-resolve-deps.sh

# 소스 JAR 포함
bash scripts/01-resolve-deps.sh --with-sources

# 소스 + JavaDoc 모두 포함
bash scripts/01-resolve-deps.sh --with-sources --with-javadoc
```

내부적으로 다음 Maven goal을 순서대로 실행합니다.

1. `mvn dependency:resolve` — 컴파일/런타임 의존성 다운로드
2. `mvn dependency:resolve-sources` — 소스 JAR 다운로드 (선택)
3. `mvn dependency:go-offline` — 플러그인 포함 전체 오프라인 준비

### Step 2. 의존성 추출

로컬 `.m2`에서 이 프로젝트에서 선언된 의존성만 골라 `output/maven_repository`로 복사합니다.

```bash
# 증분 복사 (기존 output 유지)
bash scripts/02-export-m2.sh

# 전체 초기화 후 복사
bash scripts/02-export-m2.sh --clean
```

실행이 완료되면 아래 경로에 결과가 생성됩니다.

```
output/
└── maven_repository/      ← Maven 레포지토리 디렉터리 구조 그대로 복사됨
    ├── org/
    ├── com/
    └── ...
```

### Step 3. 전송용 패키지 생성

`output/maven_repository`를 압축하여 폐쇄망 서버 전달용 파일을 만듭니다.

```bash
# tar.gz 형식 (기본)
bash scripts/03-package-for-transfer.sh

# zip 형식
bash scripts/03-package-for-transfer.sh --format=zip
```

생성 파일 예시:

```
output/maven_repository_20250316_143022.tar.gz
```

---

## 폐쇄망 서버 배포

### 1. 압축 파일 전달

생성된 `.tar.gz` (또는 `.zip`) 파일을 USB 등 물리 매체로 폐쇄망 서버에 복사합니다.

### 2. 압축 해제

```bash
# 예: /opt/maven_repository 에 풀기
tar -xzf maven_repository_20250316_143022.tar.gz -C /opt/maven_repository
```

### 3. Maven settings.xml 배포

`settings-offline.xml`을 서버에 복사한 뒤 경로를 실제 환경에 맞게 수정합니다.

```xml
<!-- settings-offline.xml 수정 예시 -->
<localRepository>/opt/maven_repository</localRepository>

<repository>
    <url>file:///opt/maven_repository</url>
    ...
</repository>
```

수정 완료 후 다음 위치 중 하나에 배치합니다.

| 적용 범위 | 파일 위치 |
|-----------|-----------|
| 특정 사용자만 | `~/.m2/settings.xml` |
| 서버 전체 | `${MAVEN_HOME}/conf/settings.xml` |

### 4. 오프라인 빌드 실행

```bash
# settings.xml 이 ~/.m2/settings.xml 인 경우
mvn package --offline

# settings.xml 을 직접 지정하는 경우
mvn package --offline -s /path/to/settings-offline.xml
```

---

## 새 의존성 세트 추가

필요한 의존성 조합이 기존 모듈에 없다면 아래 절차로 새 모듈을 추가합니다.

### 1. 모듈 디렉터리 생성

```bash
mkdir -p deps/spring-boot-redis
```

### 2. `pom.xml` 작성

```xml
<!-- deps/spring-boot-redis/pom.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" ...>
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>com.example</groupId>
        <artifactId>maven-repo-exporter</artifactId>
        <version>1.0.0</version>
        <relativePath>../../pom.xml</relativePath>
    </parent>

    <artifactId>deps-spring-boot-redis</artifactId>
    <packaging>jar</packaging>
    <name>Deps :: Spring Boot Redis</name>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-redis</artifactId>
        </dependency>
    </dependencies>
</project>
```

### 3. 루트 `pom.xml`에 모듈 등록

```xml
<!-- pom.xml -->
<modules>
    <module>deps/spring-boot-web</module>
    <module>deps/spring-boot-data-jpa</module>
    <module>deps/spring-boot-security</module>
    <module>deps/spring-boot-batch</module>
    <module>deps/spring-boot-redis</module>  <!-- 추가 -->
</modules>
```

### 4. 스크립트 재실행

```bash
bash scripts/01-resolve-deps.sh
bash scripts/02-export-m2.sh --clean
bash scripts/03-package-for-transfer.sh
```

---

## 자주 묻는 질문

**Q. Spring Boot BOM 에 포함되지 않은 라이브러리의 버전은 어떻게 관리하나요?**

모듈 `pom.xml`의 `<properties>` 또는 `<dependencyManagement>` 에 직접 버전을 명시합니다.
예시: `spring-boot-security/pom.xml` 의 `<jjwt.version>0.12.6</jjwt.version>`

---

**Q. `dependency:go-offline` 실행 중 일부 아티팩트가 실패합니다.**

SNAPSHOT 버전 또는 특정 레포지토리 전용 아티팩트가 원인인 경우가 많습니다.
`--fail-at-end` 플래그가 설정되어 있으므로 오류 로그를 확인하고 해당 의존성의 버전 또는 레포지토리 설정을 점검하세요.

---

**Q. `output/maven_repository`의 용량이 너무 큽니다.**

`02-export-m2.sh`는 `runtime` 스코프 이하의 의존성만 복사합니다.
`--with-sources`, `--with-javadoc` 옵션을 사용하지 않았는지 확인하고, 실제로 필요한 모듈만 루트 `pom.xml` `<modules>`에 포함시키세요.

---

**Q. 폐쇄망 서버에서 `Could not find artifact` 오류가 발생합니다.**

아래 사항을 순서대로 확인하세요.

1. `settings-offline.xml`의 `<localRepository>` 경로가 실제 압축 해제 경로와 일치하는지 확인
2. `<repository>` 의 `<url>` 이 동일한 경로를 가리키는지 확인 (`file:///` 접두사 포함)
3. 인터넷 환경에서 `01-resolve-deps.sh`가 오류 없이 완료되었는지 확인
4. 해당 아티팩트가 `output/maven_repository` 안에 실제로 존재하는지 확인
