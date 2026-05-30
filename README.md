# 시스템 관제 자동화 스크립트 개발 과제 수행 내역서

> 이 문서는 제출용 README.md이다.  
> 실제 터미널 실행 결과는 각 항목의 `결과 증거` 칸에 직접 붙여넣는다.  
> Mac에서 ZIP 압축을 해제하는 과정은 제출 문서에서 제외하고, 컨테이너 내부 Ubuntu 운영 환경 기준으로 작성한다.

---

## 0. 필수 증거 자료 체크리스트

아래 항목은 과제 평가 시 확인될 수 있는 핵심 증거이다.

- [ ] SSH 포트 `20022` 변경 확인
- [ ] root 원격 접속 차단 확인
- [ ] SSH 서비스 시작 및 `20022` 포트 LISTEN 확인
- [ ] UFW 또는 firewalld 활성화 확인
- [ ] `20022/tcp`, `15034/tcp`만 허용한 방화벽 규칙 확인
- [ ] `agent-admin`, `agent-dev`, `agent-test` 계정 생성 확인
- [ ] `agent-common`, `agent-core` 그룹 구성 확인
- [ ] `upload_files`, `api_keys`, `/var/log/agent-app` 권한 확인
- [ ] `monitor.sh` 소유자, 그룹, 권한 `750` 확인
- [ ] 앱 Boot Sequence 5단계 `[OK]` 확인
- [ ] `Agent READY` 출력 확인
- [ ] 앱이 `0.0.0.0:15034` LISTEN 상태인지 확인
- [ ] `monitor.sh` 수동 실행 결과 확인
- [ ] `/var/log/agent-app/monitor.log` 누적 기록 확인
- [ ] `cron` 매분 자동 실행 등록 확인
- [ ] 1분 후 `monitor.log` 라인 증가 확인
- [ ] 보너스: `report.sh` 요약 리포트 실행 확인
- [ ] 보너스: 시간 기반 로그 보존 정책 실행 확인

---

## 1. 최종 결과물

### 1-1. 필수 제출 파일

```text
README.md
monitor.sh
```

### 1-2. 보너스 수행 시 추가 제출 가능 파일

```text
report.sh
log_retention.sh
```

### 1-3. 최종 제출 구조 예시

과제에서 `monitor.sh`를 별도 제출하라고 되어 있으면 아래처럼 `README.md`와 같은 위치에 둔다.

```text
제출폴더/
├── README.md
├── monitor.sh
├── report.sh              # 보너스 수행 시
└── log_retention.sh       # 보너스 수행 시
```

`monitor.sh`는 컨테이너 내부에서 다음 위치에 작성했다.

```text
/home/agent-admin/agent-app/bin/monitor.sh
```

Mac으로 꺼낼 때는 Mac 터미널에서 다음 명령어를 사용한다.

```bash
docker cp agent-mission:/home/agent-admin/agent-app/bin/monitor.sh ~/Desktop/monitor.sh
```

---

## 2. 과제 목표

이 과제의 목표는 단순히 명령어를 실행하는 것이 아니라, Linux 서버 운영자가 실제 서비스 배포 환경에서 수행하는 기본 보안 설정, 권한 분리, 서비스 실행, 상태 관제, 로그 기록 자동화를 직접 구성하는 것이다.

학습자는 다음 내용을 설명할 수 있어야 한다.

- SSH 포트 변경과 root 원격 접속 차단이 필요한 이유
- UFW 또는 firewalld를 이용해 필요한 포트만 허용하는 이유
- 역할 기반 계정/그룹을 구성하는 이유
- 공유 디렉토리와 보안 디렉토리 권한을 분리하는 이유
- 환경 변수로 앱 실행 환경을 고정하는 이유
- Bash 스크립트로 프로세스, 포트, 리소스 상태를 수집하는 방식
- `cron`으로 관제 스크립트를 주기 실행하는 방식
- 로그 용량 관리와 시간 기반 로그 보존 정책이 필요한 이유

---

## 3. 컨테이너 내부 실제 운영 환경

### 3-1. 실습 환경 요약

```text
호스트 OS: macOS
실습 환경: Docker 컨테이너
컨테이너 이미지: ubuntu:22.04
컨테이너 이름: agent-mission
컨테이너 내부 OS: Ubuntu 22.04 LTS 또는 동등 환경
실행 사용자: root로 초기 설정 후, 앱 실행은 agent-admin 사용
앱 실행 포트: 15034
SSH 변경 포트: 20022
```

### 3-2. 컨테이너 환경 확인 명령어

```bash
hostname
cat /etc/os-release
uname -a
whoami
pwd
ps -p 1 -o pid,comm,args
```

### 결과 증거

```text

```

### 3-3. 컨테이너 내부에서 설치한 주요 패키지

```text
sudo             : 일반 계정으로 제한된 관리자 명령 실행
openssh-server   : SSH 서비스 제공
ufw              : 방화벽 설정 도구
cron             : 주기 실행 자동화
acl              : ACL 권한 설정 및 확인
procps           : ps, pgrep, free 등 프로세스/메모리 확인 도구
net-tools        : 네트워크 확인 보조 도구
iproute2         : ss 명령어 제공
gzip             : 로그 압축
python3          : 제공 앱 또는 실습용 앱 실행
```

### 설치 확인 명령어

```bash
dpkg -l | grep -E 'sudo|openssh-server|ufw|cron|acl|procps|net-tools|iproute2|gzip|python3'
```

### 결과 증거

```text

```

---

## 4. 사용자/그룹 구조와 권한 구조

### 4-1. 사용자 구조

| 사용자 | 역할 | 포함 그룹 | 설명 |
|---|---|---|---|
| `agent-admin` | 운영/관리 계정 | `agent-common`, `agent-core`, 필요 시 `sudo` | 앱 실행 및 cron 실행 계정 |
| `agent-dev` | 개발/운영 스크립트 작성 계정 | `agent-common`, `agent-core` | `monitor.sh` 작성자/소유자 |
| `agent-test` | QA/테스트 계정 | `agent-common` | 공유 업로드 디렉토리 접근 가능, 보안 디렉토리 접근 불가 |

### 4-2. 그룹 구조

| 그룹 | 포함 사용자 | 접근 목적 |
|---|---|---|
| `agent-common` | `agent-admin`, `agent-dev`, `agent-test` | 일반 공유 디렉토리 접근 |
| `agent-core` | `agent-admin`, `agent-dev` | 키 파일, 로그, 관제 스크립트 접근 |

### 4-3. 디렉토리 권한 구조

| 경로 | 소유자 | 그룹 | 권한 | 목적 |
|---|---|---|---|---|
| `/home/agent-admin/agent-app` | `agent-admin` | `agent-core` | `750` | 앱 홈 디렉토리 |
| `/home/agent-admin/agent-app/upload_files` | `agent-admin` | `agent-common` | `770` | 공통 업로드 파일 저장 |
| `/home/agent-admin/agent-app/api_keys` | `agent-admin` | `agent-core` | `770` | 민감한 키 파일 저장 |
| `/var/log/agent-app` | `agent-admin` | `agent-core` | `770` | 앱/관제 로그 저장 |
| `/home/agent-admin/agent-app/bin/monitor.sh` | `agent-dev` | `agent-core` | `750` | 관제 스크립트 |

### 4-4. 확인 명령어

```bash
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core

ls -ld /home/agent-admin/agent-app
ls -ld /home/agent-admin/agent-app/upload_files
ls -ld /home/agent-admin/agent-app/api_keys
ls -ld /var/log/agent-app
ls -l /home/agent-admin/agent-app/bin/monitor.sh

getfacl /home/agent-admin/agent-app/upload_files
getfacl /home/agent-admin/agent-app/api_keys
getfacl /var/log/agent-app
```

### 결과 증거

```text

```

---

## 5. 기능 요구 사항 수행 내역

---

## 5-1. SSH 설정

### 수행 내용

- SSH 접속 포트를 `20022`로 변경
- root 원격 접속 차단
- SSH 서비스 시작
- `20022` 포트 LISTEN 확인

### 사용 명령어

```bash
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sed -i '/^#*Port /d' /etc/ssh/sshd_config
sed -i '/^#*PermitRootLogin /d' /etc/ssh/sshd_config
cat >> /etc/ssh/sshd_config <<'SSHCONF'
Port 20022
PermitRootLogin no
SSHCONF

mkdir -p /run/sshd
sshd -t
service ssh restart

grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config
ss -tulnp | grep ':20022'
```

### 결과 증거

```text

```

### 설명

기본 SSH 포트인 `22`번은 자동화 스캔과 무차별 대입 공격의 주요 대상이다. 포트를 `20022`로 변경하면 기본 포트 대상 공격 노출을 줄일 수 있다.  
`PermitRootLogin no`는 root 계정의 직접 원격 접속을 막는다. 운영자는 일반 계정으로 접속한 뒤 필요한 경우에만 `sudo`를 사용해야 한다.

---

## 5-2. 방화벽 설정

### 수행 내용

- UFW 활성화
- inbound 기본 차단
- outbound 기본 허용
- `20022/tcp` 허용
- `15034/tcp` 허용

### 사용 명령어

```bash
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw --force enable
ufw status verbose
```

### 결과 증거

```text

```

### 설명

방화벽 정책은 서버가 외부에 노출하는 입구를 제한하는 역할을 한다. 이 과제에서는 SSH 접속용 `20022/tcp`와 앱 접속용 `15034/tcp`만 허용하고, 나머지 inbound 접근은 차단한다.

---

## 5-3. 애플리케이션 실행 환경 구성

### 환경 변수

```text
AGENT_HOME=/home/agent-admin/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
AGENT_LOG_DIR=/var/log/agent-app
```

### 키 파일

```text
/home/agent-admin/agent-app/api_keys/t_secret.key
```

키 파일 내용:

```text
agent_api_key_test
```

### 실행 명령어

```bash
sudo -iu agent-admin /home/agent-admin/agent-app/bin/run_agent.sh
```

### 성공 기준

- Boot Sequence 5단계 모두 `[OK]`
- `Agent READY` 출력
- `0.0.0.0:15034` LISTEN 상태

### 결과 증거: Boot Sequence

```text

```

### 결과 증거: 포트 확인

```bash
ss -tulnp | grep ':15034'
```

```text

```

### 설명

환경 변수를 사용하면 앱 실행에 필요한 경로와 포트를 코드에 직접 고정하지 않아도 된다. 운영 환경에서는 같은 앱이라도 서버마다 경로, 포트, 로그 디렉토리가 다를 수 있으므로 환경 변수로 실행 조건을 분리하는 것이 좋다.

---

## 5-4. monitor.sh 구현 및 실행 확인

### 파일 위치

```text
/home/agent-admin/agent-app/bin/monitor.sh
```

### 파일 권한

```text
소유자: agent-dev
그룹: agent-core
권한: 750
실행 계정: agent-admin
```

### 구현 기능

- `agent_app.py` 프로세스 실행 여부 확인
- TCP `15034` 포트 LISTEN 확인
- UFW 또는 firewalld 활성화 상태 확인
- CPU 사용률 수집
- MEM 사용률 수집
- Root partition DISK 사용률 수집
- 임계값 초과 시 `[WARNING]` 출력
- `/var/log/agent-app/monitor.log`에 지정 포맷으로 기록
- `monitor.log`가 10MB 이상이면 로그 회전
- 최대 10개 로그 파일 유지

### 실행 명령어

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
```

### 결과 증거

```text

```

### 설명

프로세스와 포트 확인은 앱이 실제로 실행 중인지 판단하는 핵심 조건이다. 프로세스가 없거나 포트가 열려 있지 않으면 서비스 장애이므로 `exit 1`로 종료한다. 방화벽 비활성화나 리소스 임계값 초과는 즉시 앱 종료 상태를 의미하지 않으므로 `[WARNING]`만 출력한다.

---

## 5-5. monitor.log 누적 기록 확인

### 로그 파일

```text
/var/log/agent-app/monitor.log
```

### 로그 포맷

```text
[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
```

### 확인 명령어

```bash
tail -n 5 /var/log/agent-app/monitor.log
```

### 결과 증거

```text

```

---

## 5-6. cron 자동 실행 확인

### 등록 내용

```text
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >/dev/null 2>&1
```

### 확인 명령어

```bash
service cron start
crontab -u agent-admin -l
wc -l /var/log/agent-app/monitor.log
sleep 70
wc -l /var/log/agent-app/monitor.log
tail -n 5 /var/log/agent-app/monitor.log
```

### 결과 증거

```text

```

### 설명

`cron`은 정해진 시간마다 명령어를 자동 실행하는 Linux의 기본 스케줄러다. 이 과제에서는 `agent-admin` 계정의 crontab에 `monitor.sh`를 매분 실행하도록 등록한다. 1분 뒤 `monitor.log`의 줄 수가 증가하면 자동 실행이 정상 동작한 것이다.

---

## 5-7. monitor.log 용량 관리

### 수행 내용

- `monitor.log`가 10MB 이상이면 로그 회전 수행
- 최대 10개 파일 유지

### 확인 명령어

```bash
ls -lh /var/log/agent-app/
```

### 결과 증거

```text

```

### 설명

로그가 무제한으로 증가하면 디스크가 가득 차서 장애가 발생할 수 있다. 그래서 `monitor.sh` 내부에서 로그 파일 크기를 확인하고, 10MB 이상이면 기존 로그를 `monitor.log.1`, `monitor.log.2` 형태로 회전시킨다.

---

## 6. 보너스 과제 1: report.sh 요약 리포트

### 파일 위치

```text
/home/agent-admin/agent-app/bin/report.sh
```

### 수행 내용

`monitor.log`를 분석해 다음 항목을 출력한다.

- CPU 평균/최대/최소
- MEM 평균/최대/최소
- DISK 평균/최대/최소
- 샘플 수

### 실행 명령어

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh
```

### 시간 구간 지정 실행

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh "YYYY-MM-DD HH:MM:SS" "YYYY-MM-DD HH:MM:SS"
```

### 결과 증거

```text

```

### 설명

`report.sh`는 누적된 로그에서 CPU, MEM, DISK의 평균/최대/최소 값을 계산한다. 운영자는 긴 로그를 직접 읽지 않고도 일정 기간의 시스템 상태를 요약해서 확인할 수 있다.

---

## 7. 보너스 과제 2: 시간 기반 로그 보존 정책

### 파일 위치

```text
/home/agent-admin/agent-app/bin/log_retention.sh
```

### 수행 내용

- 7일 이상 지난 `.log` 파일 압축
- 압축 파일을 `/var/log/monitor/agent-app/archive/`로 이동
- 30일 이상 지난 `.gz` 아카이브 삭제
- 대상 파일이 없어도 안전하게 종료

### 실행 명령어

```bash
sudo /home/agent-admin/agent-app/bin/log_retention.sh
```

### 결과 증거

```text

```

---

## 8. 추가 개념 정리

---

## 8-1. sudo의 역할

`sudo`는 일반 사용자가 필요한 순간에만 관리자 권한으로 명령어를 실행하게 해주는 도구이다.  
root 계정으로 계속 작업하면 실수로 시스템 전체를 변경하거나 삭제할 위험이 크다. 따라서 운영 환경에서는 일반 계정으로 접속하고, 패키지 설치, 서비스 재시작, 시스템 설정 변경처럼 관리자 권한이 필요한 작업에만 `sudo`를 사용한다.

### 예시

```bash
sudo service ssh restart
sudo ufw status verbose
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
```

위 명령어 중 `sudo -u agent-admin`은 root 권한으로 실행한다는 뜻이 아니라, 명령어 실행 사용자를 `agent-admin`으로 바꿔 실행한다는 뜻이다.

---

## 8-2. UFW와 Firewall의 차이 및 장단점

### 개념 차이

| 구분 | 설명 |
|---|---|
| Firewall | 네트워크 접근을 허용하거나 차단하는 전체적인 보안 개념 |
| UFW | Ubuntu에서 방화벽 규칙을 쉽게 관리하기 위한 도구 |
| firewalld | CentOS/RHEL 계열에서 많이 사용하는 방화벽 관리 도구 |
| iptables/nftables | Linux 커널 수준의 실제 패킷 필터링 규칙을 다루는 하위 도구 |

### UFW 장점

- 명령어가 단순하다.
- Ubuntu 환경에서 사용하기 쉽다.
- `ufw allow 20022/tcp`처럼 규칙 작성이 직관적이다.

### UFW 단점

- 복잡한 zone 기반 정책이나 대규모 서버 정책 관리에는 firewalld보다 단순하다.
- Docker 환경에서는 실제 네트워크 구조 때문에 UFW 동작이 일반 VM과 다르게 보일 수 있다.

### firewalld 장점

- zone 기반 정책 관리가 가능하다.
- 서버 역할별로 네트워크 정책을 분리하기 좋다.
- RHEL/CentOS 계열에서 표준적으로 사용된다.

### firewalld 단점

- UFW보다 개념과 명령어가 복잡하다.
- Ubuntu 기본 실습 환경에서는 UFW가 더 간단하다.

### 이 과제에서 UFW를 선택한 이유

실습 환경이 Ubuntu 22.04 기준이므로 UFW를 선택했다. UFW는 필요한 포트만 허용하는 과제 목표를 가장 간단하고 명확하게 충족할 수 있다.

---

## 8-3. rwx의 의미

Linux 파일 권한은 읽기, 쓰기, 실행 권한으로 구성된다.

| 기호 | 의미 | 파일에서의 의미 | 디렉토리에서의 의미 |
|---|---|---|---|
| `r` | read | 파일 내용 읽기 | 디렉토리 목록 조회 |
| `w` | write | 파일 내용 수정 | 디렉토리 안에 파일 생성/삭제/이름 변경 |
| `x` | execute | 파일 실행 | 디렉토리 안으로 진입 가능 |

### 숫자 권한

| 숫자 | 권한 | 의미 |
|---|---|---|
| `7` | `rwx` | 읽기, 쓰기, 실행 가능 |
| `6` | `rw-` | 읽기, 쓰기 가능 |
| `5` | `r-x` | 읽기, 실행 가능 |
| `0` | `---` | 권한 없음 |

예를 들어 `750`은 다음을 의미한다.

```text
소유자: 7 = rwx
그룹  : 5 = r-x
기타  : 0 = ---
```

---

## 8-4. monitor.sh 파일 권한이 750인 이유

`monitor.sh`는 시스템 상태, 로그 경로, 앱 실행 여부를 확인하는 운영용 스크립트이다. 모든 사용자가 수정하거나 실행할 수 있으면 보안상 위험하다.

```text
750 = rwxr-x---
```

| 대상 | 권한 | 이유 |
|---|---|---|
| 소유자 `agent-dev` | `rwx` | 스크립트 작성자이므로 읽기/수정/실행 가능 |
| 그룹 `agent-core` | `r-x` | 운영 그룹은 실행과 읽기 가능 |
| 기타 사용자 | `---` | `agent-test` 등 비운영 계정은 접근 차단 |

`agent-admin`은 `agent-core` 그룹에 포함되어 있으므로 `monitor.sh`를 실행할 수 있다. 그러나 기타 사용자인 `agent-test`는 실행할 수 없다. 이것이 최소 권한 원칙에 맞다.

---

## 8-5. pgrep -f 선택 이유와 대체 명령어 비교

### 사용한 명령어

```bash
pgrep -u agent-admin -f "agent_app.py"
```

### 선택 이유

`pgrep`은 실행 중인 프로세스를 검색하는 명령어이다. `-f` 옵션은 프로세스 이름만 보는 것이 아니라 전체 실행 명령어를 검색한다. Python 앱은 실제 프로세스 이름이 `python3`로 보일 수 있기 때문에 단순히 `pgrep agent_app.py`로는 찾지 못할 수 있다. 그래서 전체 실행 명령어에 포함된 `agent_app.py`를 찾기 위해 `-f`를 사용했다.

### 대체 명령어 비교

| 명령어 | 예시 | 장점 | 단점 |
|---|---|---|---|
| `pgrep -f` | `pgrep -f "agent_app.py"` | 간단하고 PID만 얻기 좋음 | 검색어가 넓으면 다른 명령도 잡힐 수 있음 |
| `ps aux  grep` | `ps aux | grep agent_app.py` | 사람이 보기 쉬움 | 자기 자신인 `grep` 프로세스가 같이 잡힐 수 있음 |
| `pidof` | `pidof python3` | 특정 실행 파일 PID 확인 가능 | Python 앱처럼 여러 스크립트가 같은 실행 파일을 쓰면 구분 어려움 |
| `systemctl status` | `systemctl status agent-app` | systemd 서비스 상태 확인에 좋음 | Docker 컨테이너에서는 systemd가 없을 수 있음 |

### 최종 선택

이 과제에서는 앱이 systemd 서비스가 아니라 일반 Python 프로세스로 실행되므로 `pgrep -f "agent_app.py"`가 가장 단순하고 적합하다.

---

## 8-6. 포트 상태 확인 명령어 설명 및 비교

### 사용한 명령어

```bash
ss -tulnp | grep ':20022'
ss -tulnp | grep ':15034'
```

### 옵션 의미

| 옵션 | 의미 |
|---|---|
| `-t` | TCP 소켓 표시 |
| `-u` | UDP 소켓 표시 |
| `-l` | LISTEN 상태의 소켓 표시 |
| `-n` | 포트와 주소를 숫자로 표시 |
| `-p` | 해당 포트를 사용하는 프로세스 표시 |

`grep ':20022'`는 출력 중에서 `20022` 포트를 사용하는 줄만 필터링한다.

### 이 명령어로 확인하는 것

- SSH 서비스가 `20022` 포트에서 LISTEN 중인지 확인
- 앱이 `15034` 포트에서 LISTEN 중인지 확인
- 어떤 프로세스가 포트를 사용 중인지 확인

### 대체 명령어 비교

| 명령어 | 예시 | 장점 | 단점 |
|---|---|---|---|
| `ss` | `ss -tulnp` | 최신 Linux에서 권장, 빠름 | 처음 보면 옵션이 어렵다 |
| `netstat` | `netstat -tulnp` | 오래된 자료에 많이 나옴 | 기본 설치가 아닐 수 있고 구식 도구로 분류됨 |
| `lsof` | `lsof -i :15034` | 특정 포트와 프로세스 확인이 명확함 | 별도 설치가 필요할 수 있음 |
| `nc` | `nc -zv 127.0.0.1 15034` | 접속 가능 여부 테스트에 좋음 | LISTEN 프로세스 정보는 알기 어려움 |

### 최종 선택

`ss -tulnp`는 현재 Linux 환경에서 포트 LISTEN 상태와 프로세스 정보를 함께 확인할 수 있어 SSH와 앱 포트 검증에 적합하다.

---

## 8-7. CPU/MEM/DISK 값 추출 및 파싱 방식

### CPU 사용률 추출 방식

`monitor.sh`에서는 `/proc/stat`의 CPU 누적 값을 두 번 읽고, 짧은 시간 차이를 계산해 CPU 사용률을 구한다.

```bash
read -r _ u1 n1 s1 i1 w1 irq1 sirq1 steal1 _ < /proc/stat
sleep 0.3
read -r _ u2 n2 s2 i2 w2 irq2 sirq2 steal2 _ < /proc/stat
```

CPU 사용률 계산 방식은 다음과 같다.

```text
전체 시간 차이 = 두 번째 total - 첫 번째 total
idle 시간 차이 = 두 번째 idle - 첫 번째 idle
CPU 사용률 = (전체 시간 차이 - idle 시간 차이) / 전체 시간 차이 * 100
```

`top`을 사용할 수도 있지만, `top`은 화면 출력 형식이 환경마다 달라 파싱이 불안정할 수 있다. `/proc/stat` 방식은 Linux 커널이 제공하는 값을 직접 읽기 때문에 스크립트 자동화에 더 적합하다.

### top 기반 대체 방식

```bash
top -bn1 | grep "Cpu(s)"
```

| 방식 | 장점 | 단점 |
|---|---|---|
| `/proc/stat` | 자동화에 안정적, 빠름 | 계산식을 직접 작성해야 함 |
| `top` | 사람이 보기 쉬움 | 출력 형식이 달라질 수 있어 파싱이 불안정함 |

### MEM 사용률 추출 방식

메모리는 `free` 명령어로 전체 메모리와 사용 중인 메모리를 확인한다.

```bash
free | awk '/Mem:/ { printf "%.1f", ($3 / $2) * 100 }'
```

의미는 다음과 같다.

```text
$2 = 전체 메모리
$3 = 사용 중인 메모리
MEM 사용률 = 사용 중인 메모리 / 전체 메모리 * 100
```

### DISK 사용률 추출 방식

디스크는 루트 파티션 `/` 기준으로 `df` 명령어를 사용한다.

```bash
df / | awk 'NR==2 { gsub("%", "", $5); print $5 }'
```

의미는 다음과 같다.

```text
df /     : 루트 파티션 사용량 확인
NR==2    : 결과의 두 번째 줄만 사용
$5       : 사용률 컬럼
gsub     : % 기호 제거
```

### 로그 포맷을 고정한 이유

```text
[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
```

로그 포맷을 고정한 이유는 다음과 같다.

- 사람이 읽기 쉽다.
- `report.sh`가 `awk`로 CPU/MEM/DISK 값을 안정적으로 파싱할 수 있다.
- 시간 범위 필터링이 가능하다.
- 장애 발생 시 어느 시점에 어떤 리소스가 높았는지 추적할 수 있다.
- 로그 형식이 매번 바뀌지 않으므로 자동 분석에 적합하다.

---

## 8-8. 임계값 설정 이유

```text
CPU > 20%      : WARNING
MEM > 10%      : WARNING
DISK_USED > 80%: WARNING
```

이 과제에서는 실습 환경에서 경고가 쉽게 발생하도록 CPU와 MEM 임계값을 낮게 설정했다. 실제 운영 서버에서는 서비스 특성에 맞게 임계값을 조정해야 한다. 예를 들어 CPU 사용률은 70~90%, 메모리는 80~90%, 디스크는 80~90% 수준에서 경고를 설정하는 경우가 많다.

---

## 9. 실제 테스트 절차와 명령어

이 장은 과제를 실제로 테스트할 때 사용하는 순서이다.

---

## 9-1. SSH 서비스 시작 및 설정 확인

```bash
mkdir -p /run/sshd
sshd -t
service ssh restart
service ssh status || true
grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config
ss -tulnp | grep ':20022'
```

### 결과 증거

```text

```

---

## 9-2. 방화벽 테스트

```bash
ufw status verbose
ufw status numbered
```

### 결과 증거

```text

```

---

## 9-3. cron 서비스 시작 및 등록 확인

```bash
service cron start
service cron status || true
crontab -u agent-admin -l
```

### 결과 증거

```text

```

---

## 9-4. 앱 실행 테스트

터미널 1에서 실행한다.

```bash
sudo -iu agent-admin /home/agent-admin/agent-app/bin/run_agent.sh
```

### 결과 증거

```text

```

---

## 9-5. 앱 포트 확인

터미널 2에서 실행한다.

```bash
ss -tulnp | grep ':15034'
```

### 결과 증거

```text

```

---

## 9-6. monitor.sh 수동 실행 테스트

터미널 2에서 실행한다.

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
```

### 결과 증거

```text

```

---

## 9-7. 로그 누적 확인

```bash
tail -n 5 /var/log/agent-app/monitor.log
```

### 결과 증거

```text

```

---

## 9-8. cron 자동 실행으로 로그가 증가하는지 확인

```bash
wc -l /var/log/agent-app/monitor.log
sleep 70
wc -l /var/log/agent-app/monitor.log
tail -n 5 /var/log/agent-app/monitor.log
```

### 결과 증거

```text

```

---

## 9-9. report.sh 테스트

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh
```

시간 범위를 지정할 경우:

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh "YYYY-MM-DD HH:MM:SS" "YYYY-MM-DD HH:MM:SS"
```

### 결과 증거

```text

```

---

## 9-10. log_retention.sh 테스트

```bash
sudo /home/agent-admin/agent-app/bin/log_retention.sh
```

### 결과 증거

```text

```

---

## 10. 제출용 증거 수집 명령어

아래 명령어는 주요 결과를 한 번에 모아 `evidence_result.txt`에 저장한다.

```bash
{
echo "===== ENVIRONMENT ====="
hostname
cat /etc/os-release | head
uname -a
whoami
ps -p 1 -o pid,comm,args

echo
echo "===== SSH CONFIG ====="
grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config
ss -tulnp | grep ':20022' || true

echo
echo "===== FIREWALL ====="
ufw status verbose || true

echo
echo "===== USERS / GROUPS ====="
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core

echo
echo "===== PERMISSIONS ====="
ls -ld /home/agent-admin/agent-app
ls -ld /home/agent-admin/agent-app/upload_files
ls -ld /home/agent-admin/agent-app/api_keys
ls -ld /var/log/agent-app
ls -l /home/agent-admin/agent-app/bin/monitor.sh
getfacl /home/agent-admin/agent-app/upload_files
getfacl /home/agent-admin/agent-app/api_keys
getfacl /var/log/agent-app

echo
echo "===== APP PORT ====="
ss -tulnp | grep ':15034' || true

echo
echo "===== MONITOR RESULT ====="
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh || true

echo
echo "===== MONITOR LOG ====="
tail -n 5 /var/log/agent-app/monitor.log || true

echo
echo "===== CRON ====="
crontab -u agent-admin -l || true

echo
echo "===== REPORT ====="
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh || true

echo
echo "===== LOG RETENTION ====="
sudo /home/agent-admin/agent-app/bin/log_retention.sh || true
} | tee /home/agent-admin/agent-app/evidence_result.txt
```

---

## 11. 문제 해결 및 트러블슈팅

### 문제 1. `/work/agent-monitor-practice`가 없다고 나오는 경우

```text
bash: cd: /work/agent-monitor-practice: No such file or directory
```

### 원인

Docker 실행 시 Mac 폴더를 `/work`에 마운트하지 않았거나, ZIP 파일 압축 해제 방식으로 진행하지 않았기 때문이다.

### 해결

이 README는 ZIP 압축 해제 방식이 아니라 컨테이너 내부에서 직접 파일을 작성하는 방식으로 정리했다. 따라서 `/work/agent-monitor-practice`로 이동하지 않고, 컨테이너 내부의 다음 경로를 기준으로 작업한다.

```text
/home/agent-admin/agent-app
```

---

### 문제 2. `monitor.sh` 실행 시 앱 프로세스를 찾지 못하는 경우

```text
[ERROR] Application process is not running
```

### 원인

앱이 실행 중이지 않거나, `agent-admin` 계정으로 실행되지 않았을 가능성이 있다.

### 해결

터미널 1에서 앱을 먼저 실행한다.

```bash
sudo -iu agent-admin /home/agent-admin/agent-app/bin/run_agent.sh
```

그 후 터미널 2에서 `monitor.sh`를 실행한다.

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
```

---

### 문제 3. `/var/log/agent-app/monitor.log`에 기록되지 않는 경우

### 원인

로그 디렉토리 권한이 잘못되었거나, `agent-admin`이 `agent-core` 그룹에 포함되지 않았을 수 있다.

### 해결

```bash
id agent-admin
ls -ld /var/log/agent-app
chown -R agent-admin:agent-core /var/log/agent-app
chmod 770 /var/log/agent-app
```

---

## 12. 최종 제출 체크리스트

- [ ] `README.md` 작성 완료
- [ ] `monitor.sh` 제출 파일 준비 완료
- [ ] `README.md`의 결과 증거 칸에 실제 실행 결과 붙여넣기 완료
- [ ] SSH 설정 증거 입력 완료
- [ ] 방화벽 설정 증거 입력 완료
- [ ] 사용자/그룹 구조 증거 입력 완료
- [ ] 권한 구조 증거 입력 완료
- [ ] 앱 실행 증거 입력 완료
- [ ] monitor.sh 실행 증거 입력 완료
- [ ] monitor.log 누적 증거 입력 완료
- [ ] cron 자동 실행 증거 입력 완료
- [ ] 보너스 수행 시 report.sh 결과 입력 완료
- [ ] 보너스 수행 시 log_retention.sh 결과 입력 완료

---

## 13. 제출 파일 목록

### 필수

```text
README.md
monitor.sh
```

### 보너스 포함 시

```text
README.md
monitor.sh
report.sh
log_retention.sh
```
