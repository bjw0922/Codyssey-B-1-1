# 시스템 관제 자동화 스크립트 개발 수행 내역서

## 0. 제출 파일

```text
agent-monitor-practice/
├── README.md
├── app/
│   ├── agent-app-linux-x86
│   └── agent-app-linux-arm64
└── scripts/
    ├── setup_agent.sh
    ├── run_agent.sh
    ├── monitor.sh
    ├── report.sh
    └── log_retention.sh
```

제출 대상은 `README.md`와 `scripts/monitor.sh`가 핵심이다. 보너스 수행 시 `scripts/report.sh`, `scripts/log_retention.sh`도 함께 제출한다.

---

## 1. 과제 목표

이 과제는 Ubuntu Linux 환경에서 다음 항목을 직접 구성하는 것이 목표다.

1. SSH 포트 변경 및 root 원격 접속 차단
2. 방화벽에서 필요한 포트만 허용
3. 운영/개발/테스트 계정과 그룹 구성
4. 공유 디렉토리와 보안 디렉토리 권한 분리
5. 제공 앱 실행 환경 구성
6. `monitor.sh`로 프로세스, 포트, 리소스 상태 점검
7. `monitor.log` 누적 기록 및 용량 관리
8. `cron`으로 매분 관제 실행
9. 보너스: `report.sh` 요약 리포트, 시간 기반 로그 보존 정책

---

## 2. 최종 결과물 요약

| 구분 | 구현 내용 | 제출 증거 |
|---|---|---|
| SSH | 포트 `20022`, `PermitRootLogin no` | `grep`, `ss` 결과 |
| 방화벽 | `20022/tcp`, `15034/tcp` 허용 | `ufw status` 결과 |
| 계정/그룹 | `agent-admin`, `agent-dev`, `agent-test`, `agent-common`, `agent-core` | `id` 결과 |
| 권한 | `upload_files`, `api_keys`, `/var/log/agent-app` 권한 분리 | `ls -ld`, `getfacl` 결과 |
| 앱 실행 | 일반 계정 실행, `Agent READY` 출력 | 앱 실행 화면 |
| monitor.sh | 프로세스/포트/CPU/MEM/DISK 점검 | 실행 결과 |
| 로그 | `/var/log/agent-app/monitor.log` 누적 | `tail` 결과 |
| cron | `agent-admin` 계정 매분 실행 | `crontab`, 1분 후 로그 증가 |
| 로그 용량 | 10MB 초과 시 최대 10개 회전 | 스크립트 코드/동작 설명 |
| 보너스 | `report.sh`, `log_retention.sh` | 실행 결과 |

---

## 3. 실습 환경

권장 환경은 Ubuntu 22.04 LTS 또는 동등한 Linux 환경이다.

Mac에서 실습할 경우 Mac 터미널에서는 `apt`, `ufw`, `systemctl` 명령어가 동작하지 않는다. 해당 명령어는 Docker/OrbStack 안의 Ubuntu 터미널에서 실행한다.

Docker로 진행할 경우 방화벽과 SSH 서비스 확인이 제한될 수 있다. 최종 평가 증거까지 완성하려면 Ubuntu VM 또는 privileged Docker 컨테이너가 더 적합하다.

---

## 4. Mac 터미널에서 실습 폴더 준비

아래 명령어는 Mac 터미널에서 입력한다.

```bash
# 실습 폴더 생성
mkdir -p ~/agent-monitor-work
cd ~/agent-monitor-work

# 받은 압축 파일을 이 폴더에 풀기
unzip agent-monitor-practice.zip
cd agent-monitor-practice
```

Docker Ubuntu 컨테이너를 새로 만들 경우 Mac 터미널에서 입력한다.

```bash
# Ubuntu 22.04 컨테이너 실행
# -p 20022:20022 : SSH 포트 연결
# -p 15034:15034 : 앱 포트 연결
# --privileged   : UFW/SSH 확인 가능성을 높이기 위한 옵션
docker run -it \
  --name agent-mission \
  --privileged \
  -p 20022:20022 \
  -p 15034:15034 \
  -v "$PWD":/work \
  ubuntu:22.04 bash
```

이미 만든 컨테이너에 다시 들어갈 경우 Mac 터미널에서 입력한다.

```bash
docker start agent-mission
docker exec -it agent-mission bash
```

---

## 5. Ubuntu 터미널에서 패키지 설치

아래 명령어는 Ubuntu/Docker 터미널에서 입력한다.

```bash
# 패키지 목록 갱신
apt update

# 과제 수행에 필요한 명령어 설치
apt install -y sudo openssh-server ufw cron acl procps net-tools iproute2 gzip unzip
```

명령어 역할은 다음과 같다.

| 명령어/패키지 | 역할 |
|---|---|
| `sudo` | 일반 계정에서 필요한 관리 명령 실행 |
| `openssh-server` | SSH 서버 설정 및 포트 확인 |
| `ufw` | 방화벽 설정 |
| `cron` | 매분 `monitor.sh` 실행 |
| `acl` | `getfacl`, `setfacl` 권한 확인/설정 |
| `procps` | `ps`, `free`, `pgrep` 사용 |
| `net-tools` | `netstat` 대체 확인용 |
| `iproute2` | `ss` 명령어 사용 |
| `gzip` | 로그 압축 |
| `unzip` | 압축 해제 |

---

## 6. 서버 설정 적용

아래 명령어는 Ubuntu/Docker 터미널에서 입력한다.

```bash
cd /work/agent-monitor-practice
bash scripts/setup_agent.sh
```

`setup_agent.sh`가 적용하는 내용은 다음과 같다.

| 항목 | 설정값 |
|---|---|
| SSH 포트 | `20022` |
| Root SSH 접속 | `PermitRootLogin no` |
| 앱 포트 | `15034` |
| AGENT_HOME | `/home/agent-admin/agent-app` |
| AGENT_UPLOAD_DIR | `/home/agent-admin/agent-app/upload_files` |
| AGENT_KEY_PATH | `/home/agent-admin/agent-app/api_keys/t_secret.key` |
| AGENT_LOG_DIR | `/var/log/agent-app` |
| 키 파일 내용 | `agent_api_key_test` |
| monitor.sh 경로 | `/home/agent-admin/agent-app/bin/monitor.sh` |
| report.sh 경로 | `/home/agent-admin/agent-app/bin/report.sh` |
| log_retention.sh 경로 | `/home/agent-admin/agent-app/bin/log_retention.sh` |

---

## 7. 앱 실행

아래 명령어는 Ubuntu/Docker 터미널 1번에서 입력한다.

```bash
# agent-admin 계정으로 전환
sudo -iu agent-admin

# 제공 앱 실행
/home/agent-admin/agent-app/bin/run_agent.sh
```

성공 시 필요한 결과는 아래 형태다.

```text
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
[2/5] Verifying Environment Variables     [OK]
[3/5] Checking Required Files             [OK]
[4/5] Checking Port Availability          [OK]
[5/5] Verifying Log Permission            [OK]
--------------------------------------------------
All Boot Checks Passed!
Agent READY
```

실제 결과 붙여넣기:

```text
[여기에 앱 Boot Sequence 5단계 OK 및 Agent READY 결과를 붙여넣기]
```

---

## 8. monitor.sh 실행

앱은 터미널 1번에서 계속 실행한 상태로 둔다. 아래 명령어는 Ubuntu/Docker 터미널 2번에서 입력한다.

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
```

성공 시 필요한 결과는 아래 형태다.

```text
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent_app.py / agent-app'... [OK] (PID: 0000)
Checking port 15034... [OK]

[FIREWALL CHECK]
[OK] UFW firewall is active

[RESOURCE MONITORING]
CPU Usage : 0.0%
MEM Usage : 0.0%
DISK Used  : 0%

[INFO] Log appended: /var/log/agent-app/monitor.log
```

실제 결과 붙여넣기:

```text
[여기에 monitor.sh 실행 결과를 붙여넣기]
```

앱이 꺼져 있으면 `monitor.sh`는 프로세스 확인에서 실패하고 `exit 1`로 종료된다.

확인 명령어:

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
echo $?
```

실패 시 필요한 결과:

```text
[ERROR] Application process is not running
1
```

---

## 9. 로그 누적 확인

아래 명령어는 Ubuntu/Docker 터미널에서 입력한다.

```bash
sudo tail -n 5 /var/log/agent-app/monitor.log
```

필요한 로그 형식은 다음과 같다.

```text
[YYYY-MM-DD HH:MM:SS] PID:0000 CPU:0.0% MEM:0.0% DISK_USED:0%
```

실제 결과 붙여넣기:

```text
[여기에 /var/log/agent-app/monitor.log 최근 라인을 붙여넣기]
```

---

## 10. cron 매분 실행 확인

아래 명령어는 Ubuntu/Docker 터미널에서 입력한다.

```bash
# agent-admin의 crontab 확인
sudo crontab -u agent-admin -l

# cron 서비스 시작
sudo service cron start

# 현재 로그 라인 수 확인
sudo wc -l /var/log/agent-app/monitor.log

# 70초 대기 후 다시 확인
sleep 70
sudo wc -l /var/log/agent-app/monitor.log
sudo tail -n 5 /var/log/agent-app/monitor.log
```

crontab에 필요한 내용:

```text
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >/dev/null 2>&1
```

실제 결과 붙여넣기:

```text
[여기에 crontab 등록 내역과 1분 후 monitor.log 라인 증가 결과를 붙여넣기]
```

---

## 11. 보너스 1: report.sh 요약 리포트

아래 명령어는 Ubuntu/Docker 터미널에서 입력한다.

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh
```

특정 시간 구간만 분석할 경우:

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh "2026-02-25 13:58:00" "2026-02-25 14:05:00"
```

필요한 결과 형태:

```text
====== STATISTICS REPORT ======
[CPU]
Average : 0.0%
Maximum : 0.0% at YYYY-MM-DD HH:MM:SS
Minimum : 0.0% at YYYY-MM-DD HH:MM:SS
[Memory]
Average : 0.0%
Maximum : 0.0% at YYYY-MM-DD HH:MM:SS
Minimum : 0.0% at YYYY-MM-DD HH:MM:SS
[Disk]
Average : 0.0%
Maximum : 0.0% at YYYY-MM-DD HH:MM:SS
Minimum : 0.0% at YYYY-MM-DD HH:MM:SS
[Samples]
Data Points: 0 samples
```

실제 결과 붙여넣기:

```text
[여기에 report.sh 실행 결과를 붙여넣기]
```

---

## 12. 보너스 2: 시간 기반 로그 보존 정책

아래 명령어는 Ubuntu/Docker 터미널에서 입력한다.

```bash
sudo /home/agent-admin/agent-app/bin/log_retention.sh
```

정책은 다음과 같다.

| 조건 | 처리 |
|---|---|
| `/var/log/agent-app/*.log` 중 7일 이상 지난 파일 | gzip 압축 후 `/var/log/monitor/agent-app/archive/`로 이동 |
| `/var/log/monitor/agent-app/archive/*.gz` 중 30일 이상 지난 파일 | 삭제 |
| 대상 파일 없음 | `[INFO]` 출력 후 정상 종료 |
| 디렉토리 없음/권한 부족 | `[WARNING]` 출력 후 안전 종료 |

실제 결과 붙여넣기:

```text
[여기에 log_retention.sh 실행 결과를 붙여넣기]
```

---

## 13. 필수 증거 자료 체크리스트

### 13-1. SSH 포트 변경 및 Root 접속 차단

명령어:

```bash
sudo grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config
sudo ss -tulnp | grep ':20022' || true
```

필요 결과:

```text
Port 20022
PermitRootLogin no
[sshd가 20022에서 LISTEN 중인 결과]
```

실제 결과 붙여넣기:

```text
[여기에 SSH 설정 확인 결과를 붙여넣기]
```

### 13-2. 방화벽 확인

명령어:

```bash
sudo ufw status verbose
```

필요 결과:

```text
Status: active
20022/tcp ALLOW IN Anywhere
15034/tcp ALLOW IN Anywhere
```

실제 결과 붙여넣기:

```text
[여기에 ufw status 결과를 붙여넣기]
```

### 13-3. 계정/그룹 확인

명령어:

```bash
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core
```

필요 결과:

```text
agent-admin: agent-common, agent-core 포함
agent-dev  : agent-common, agent-core 포함
agent-test : agent-common 포함
agent-core : agent-admin, agent-dev 포함
```

실제 결과 붙여넣기:

```text
[여기에 id/getent 결과를 붙여넣기]
```

### 13-4. 디렉토리 권한 확인

명령어:

```bash
sudo ls -ld /home/agent-admin/agent-app
sudo ls -ld /home/agent-admin/agent-app/upload_files
sudo ls -ld /home/agent-admin/agent-app/api_keys
sudo ls -ld /var/log/agent-app
sudo ls -l /home/agent-admin/agent-app/bin/monitor.sh
sudo getfacl /home/agent-admin/agent-app/upload_files
sudo getfacl /home/agent-admin/agent-app/api_keys
sudo getfacl /var/log/agent-app
```

필요 결과:

```text
upload_files              group=agent-common, rwx 가능
api_keys                  group=agent-core, rwx 가능
/var/log/agent-app        group=agent-core, rwx 가능
monitor.sh owner/group    agent-dev:agent-core
monitor.sh permission     750
```

실제 결과 붙여넣기:

```text
[여기에 권한 확인 결과를 붙여넣기]
```

### 13-5. 앱 실행 확인

명령어:

```bash
sudo -iu agent-admin
/home/agent-admin/agent-app/bin/run_agent.sh
```

실제 결과 붙여넣기:

```text
[여기에 Boot Sequence 5단계 OK 및 Agent READY 결과를 붙여넣기]
```

### 13-6. 포트 확인

다른 Ubuntu/Docker 터미널에서 입력한다.

```bash
sudo ss -tulnp | grep ':15034'
```

실제 결과 붙여넣기:

```text
[여기에 0.0.0.0:15034 LISTEN 결과를 붙여넣기]
```

### 13-7. monitor.sh 및 로그 확인

명령어:

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
sudo tail -n 5 /var/log/agent-app/monitor.log
```

실제 결과 붙여넣기:

```text
[여기에 monitor.sh 출력과 monitor.log 결과를 붙여넣기]
```

### 13-8. cron 확인

명령어:

```bash
sudo crontab -u agent-admin -l
sudo wc -l /var/log/agent-app/monitor.log
sleep 70
sudo wc -l /var/log/agent-app/monitor.log
```

실제 결과 붙여넣기:

```text
[여기에 crontab과 로그 증가 결과를 붙여넣기]
```

---

## 14. monitor.sh 구현 설명

### 14-1. 프로세스 식별

사용 명령어:

```bash
pgrep -f "$APP_PATTERN"
```

선택 이유:

`pgrep -f`는 실행 파일명뿐 아니라 전체 실행 명령줄을 대상으로 검색한다. 제공 앱이 `agent_app.py`, `agent-app-linux-x86`, `agent-app-linux-arm64`, `/home/agent-admin/agent-app/agent-app` 중 어떤 이름으로 실행되어도 확인할 수 있도록 패턴을 넓게 잡았다.

### 14-2. 포트 확인

사용 명령어:

```bash
ss -ltn
```

선택 이유:

`ss`는 현재 LISTEN 중인 TCP 포트를 빠르게 확인할 수 있다. `netstat`보다 최신 Linux 환경에서 기본적으로 권장된다. `ss`가 없는 경우 `netstat -ltn`을 보조 수단으로 사용한다.

### 14-3. CPU 수집 방식

사용 파일:

```text
/proc/stat
```

방식:

1초 간격으로 `/proc/stat`의 CPU 누적 시간을 두 번 읽는다. 전체 시간 증가량에서 idle 증가량을 제외해 CPU 사용률을 계산한다.

### 14-4. MEM 수집 방식

사용 명령어:

```bash
free
```

방식:

`Mem:` 라인의 전체 메모리와 사용 중 메모리를 기준으로 사용률을 계산한다.

### 14-5. DISK 수집 방식

사용 명령어:

```bash
df -P /
```

방식:

루트 파티션 `/`의 사용률을 읽어 `DISK_USED` 값으로 기록한다.

### 14-6. 로그 포맷 고정 이유

사용 포맷:

```text
[YYYY-MM-DD HH:MM:SS] PID:0000 CPU:0.0% MEM:0.0% DISK_USED:0%
```

이 형식은 사람이 읽기 쉽고, `awk`로 CPU/MEM/DISK 값을 다시 파싱하기 쉽다. `report.sh`는 이 포맷을 기준으로 평균/최대/최소를 계산한다.

### 14-7. 권한 정책

| 파일/디렉토리 | 소유자 | 그룹 | 권한 | 이유 |
|---|---|---|---|---|
| `monitor.sh` | `agent-dev` | `agent-core` | `750` | 개발자가 작성하고 운영 그룹만 실행 |
| `upload_files` | `agent-admin` | `agent-common` | `2770` | admin/dev/test 공동 쓰기 가능 |
| `api_keys` | `agent-admin` | `agent-core` | `2770` | 키 파일은 admin/dev만 접근 |
| `/var/log/agent-app` | `agent-admin` | `agent-core` | `2770` | 로그는 운영 핵심 그룹만 접근 |

`2`가 붙은 `2770`은 setgid 권한이다. 이 디렉토리 안에 새 파일이 생길 때 디렉토리의 그룹을 유지하기 위해 사용한다.

### 14-8. 로그 용량 관리

`monitor.sh`는 `monitor.log`가 10MB 이상이면 다음 방식으로 파일을 회전한다.

```text
monitor.log   -> monitor.log.1
monitor.log.1 -> monitor.log.2
...
monitor.log.9 -> monitor.log.10
```

최대 보관 개수는 `LOG_KEEP=10`이다. 이 방식은 별도 `logrotate` 설정 없이 Bash 스크립트만으로 동작한다.

---

## 15. 평가 질문 답변 정리

### SSH 포트 변경과 Root 접속 차단이 왜 보안에 효과적인가?

SSH 기본 포트 `22`는 무차별 대입 공격과 자동 스캔의 주요 대상이다. 포트를 `20022`로 변경하면 기본 스캔 대상에서 벗어나는 효과가 있다. `root` 원격 접속을 막으면 관리자 계정이 직접 공격받는 위험을 줄이고, 일반 계정 접속 후 필요한 경우에만 `sudo`를 사용하게 만들 수 있다.

### `api_keys`, `/var/log/agent-app`를 `agent-core`로 제한한 이유는?

`api_keys`에는 인증 키가 있고, 로그에는 운영 정보가 남는다. 테스트 계정까지 접근 가능하면 키 유출이나 로그 노출 위험이 커진다. 그래서 운영/개발 담당자인 `agent-admin`, `agent-dev`만 포함된 `agent-core` 그룹으로 제한한다.

### 방화벽 비활성화나 리소스 초과를 경고로만 처리한 이유는?

프로세스 미실행과 포트 미오픈은 앱이 정상 서비스 중이 아니라는 뜻이므로 `exit 1`로 종료한다. 반면 방화벽 비활성화, CPU/MEM/DISK 임계값 초과는 즉시 앱 장애라고 단정할 수 없다. 운영자가 확인해야 하는 상태이므로 `[WARNING]`만 출력하고 로그 기록은 계속한다.

### `>`와 `>>` 차이는?

| 기호 | 의미 |
|---|---|
| `>` | 기존 내용을 지우고 새로 씀 |
| `>>` | 기존 내용 뒤에 이어서 씀 |

`monitor.log`는 시간이 지날수록 기록이 누적되어야 하므로 `>>`를 사용한다.

---

## 16. 장애 상황 대응

### 대상이 Nginx 같은 웹 서버로 바뀌면 수정할 핵심 포인트

| 항목 | 기존 | Nginx 예시 |
|---|---|---|
| 프로세스 패턴 | `agent_app.py/agent-app` | `nginx` |
| 포트 | `15034` | `80` 또는 `443` |
| 로그 경로 | `/var/log/agent-app/monitor.log` | `/var/log/nginx/access.log`, `/var/log/nginx/error.log` |
| 임계값 | CPU 20, MEM 10, DISK 80 | 서비스 기준에 맞게 조정 |
| 권한 | `agent-core` | 웹 운영 그룹 기준으로 조정 |

### 프로세스는 살아 있는데 포트가 열리지 않는 경우 확인 순서

1. 앱 로그 확인
2. 앱 실행 환경 변수 확인
3. 앱이 실제로 어떤 포트에 바인딩했는지 확인
4. `ss -tulnp`로 LISTEN 포트 확인
5. 방화벽 규칙 확인
6. 포트 충돌 여부 확인
7. 앱 설정 파일 또는 실행 옵션 확인

확인 명령어:

```bash
ps -ef | grep -E 'agent|nginx'
ss -tulnp
sudo ufw status verbose
sudo tail -n 50 /var/log/agent-app/monitor.log
```

### 로그가 급증해 디스크가 가득 찰 위험이 있을 때 대응

1. `df -h`로 디스크 사용량 확인
2. `du -sh /var/log/*`로 큰 로그 위치 확인
3. 오래된 로그 압축 또는 삭제
4. 로그 회전 주기와 보관 개수 축소
5. 앱 오류 로그가 반복되는 원인 확인
6. 필요 시 로그 레벨 조정

확인 명령어:

```bash
df -h
sudo du -sh /var/log/* | sort -h
sudo /home/agent-admin/agent-app/bin/log_retention.sh
```

---

## 17. 스크립트 코드 요약

### monitor.sh

- 프로세스 확인: `pgrep -f`
- 포트 확인: `ss -ltn`, 보조로 `netstat -ltn`
- 방화벽 확인: `ufw status`, 보조로 `firewall-cmd --state`
- CPU 확인: `/proc/stat`
- MEM 확인: `free`
- DISK 확인: `df -P /`
- 로그 기록: `/var/log/agent-app/monitor.log`
- 로그 용량 관리: 10MB 초과 시 `monitor.log.1`부터 `monitor.log.10`까지 회전

### report.sh

- `monitor.log`를 읽어 CPU/MEM/DISK 평균, 최대, 최소, 샘플 수 출력
- 시작 시간과 종료 시간을 인자로 받아 특정 구간만 분석 가능

### log_retention.sh

- 7일 이상 지난 `.log` 파일을 압축해 아카이브 디렉토리로 이동
- 30일 이상 지난 `.gz` 아카이브 삭제
- 대상 파일이 없어도 정상 종료

---

## 18. 최종 제출 전 확인 순서

```bash
# 1. 계정/그룹
id agent-admin
id agent-dev
id agent-test

# 2. SSH 설정
sudo grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config

# 3. 방화벽
sudo ufw status verbose

# 4. 권한
sudo ls -ld /home/agent-admin/agent-app/upload_files
sudo ls -ld /home/agent-admin/agent-app/api_keys
sudo ls -ld /var/log/agent-app
sudo ls -l /home/agent-admin/agent-app/bin/monitor.sh

# 5. 앱 실행 확인
sudo ss -tulnp | grep ':15034'

# 6. monitor.sh
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh

# 7. 로그 누적
sudo tail -n 5 /var/log/agent-app/monitor.log

# 8. cron
sudo crontab -u agent-admin -l
sleep 70
sudo tail -n 5 /var/log/agent-app/monitor.log

# 9. 보너스
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh
sudo /home/agent-admin/agent-app/bin/log_retention.sh
```

---

## 19. 제출용 짧은 설명

이번 과제에서는 Linux 서버 운영 환경을 기준으로 SSH, 방화벽, 계정/그룹, 디렉토리 권한, 앱 실행 환경, 관제 스크립트, 로그 누적, cron 주기 실행을 구성했다. `monitor.sh`는 앱 프로세스와 포트를 먼저 확인하고, 비정상 상태에서는 `exit 1`로 종료한다. 방화벽 비활성화와 CPU/MEM/DISK 임계값 초과는 운영 경고로 분리해 `[WARNING]`만 출력한다. 로그는 `/var/log/agent-app/monitor.log`에 정해진 포맷으로 누적되며, 10MB 초과 시 최대 10개까지 회전한다. 보너스 항목으로 `report.sh`를 통해 로그 통계 리포트를 출력하고, `log_retention.sh`를 통해 7일 이상 지난 로그 압축과 30일 이상 지난 아카이브 삭제 정책을 구현했다.
