#!/bin/sh
#
# dva-gpu-compat-spoof.sh
#
# ============================================================================
# 배경 (DVA3219/DVA3221 실기 조사, 2026-08)
# ============================================================================
#
# DSM 제어판 -> 정보센터 -> GPU(내장형) 항목에 "OOO (호환되지 않음)"으로
# 표시되는 카드가 있다. 예: Quadro P1000을 DVA3221에 꽂으면 "호환되지
# 않음"이 뜨지만, 같은 카드를 DVA3219에 꽂으면 아무 경고가 없다.
#
# 이 표시 때문에 "denverton DVA 시리즈는 NAS 모델별로 GPU가 하드웨어/
# 코드 레벨로 화이트리스트되어 있고, 비공인 카드는 딥러닝(Deep Video
# Analytics)이 아예 동작하지 않는다"고 오해하기 쉽다. 실기로 직접 검증한
# 결과는 다음과 같다.
#
# 1. synodvad/synofaced(딥러닝 데몬)와 그 코어 라이브러리
#    (libdvacore-*.so, libsynodva-*.so)에는 GPU PCI ID나 모델명
#    화이트리스트가 전혀 없다 (strings로 전수 확인). 커널 드라이버 레벨
#    (/proc/driver/nvidia/gpus/*/information)의 "Blacklisted:" 필드도
#    "No"로 나온다.
#
# 2. 실기 검증: GTX1650(Turing, DVA3221 공인 카드)과 Quadro P1000
#    (Pascal, 비공인)을 DVA3219/DVA3221 양쪽에 번갈아 장착해 2x2 매트릭스
#    전부 테스트 - 재부팅 없이 즉시 인식되고, nvidia-smi Processes 항목에
#    synodvad/synofaced가 실제 CUDA 컴퓨트 컨텍스트(Type "C")로 GPU 메모리를
#    할당하는 것까지 확인했다. 카메라를 등록하고 Deep Video Analytics
#    작업(IVA TaskGroup)을 실제로 만들어 모션을 주면 nvidia-smi의
#    GPU-Util/메모리 사용량이 그 순간 실제로 스파이크하는 것도 확인됨
#    (짧은 간격 폴링으로 검증, 예: 0.3~0.5초 간격).
#
#    => 결론: 딥러닝 파이프라인 자체는 GPU 모델과 무관하게 정상 동작한다.
#
# 3. 그럼 정보센터의 "호환되지 않음"은 어디서 나오는가?
#    - 담당 모듈: /usr/syno/synoman/webapi/lib/SYNO.Core.System.GpuInfo.so
#      (WebAPI: SYNO.Core.System.GpuInfo)
#    - 핵심 함수: SYNOGpuIsModelSupportGpu() (libsynogpuinfo.so.7 소속,
#      /usr/lib/libsynogpuinfo.so.7)
#    - 이 라이브러리는 NVML을 직접 링크하지 않는다(NEEDED에 없음). 대신
#      "nvidia-smi --query-gpu=name,clocks.current.graphics,memory.total,
#      temperature.gpu,pci.bus_id" 를 서브프로세스로 실행해서 그 텍스트
#      출력을 파싱한다 (strings로 정확한 --query-gpu 인자까지 확인).
#    - 반환된 GPU 모델명 문자열을 라이브러리 내부에 하드코딩된 목록과
#      비교한다. 목록 예시(strings로 확인된 것):
#        GeForce GTX 1050
#        GeForce GTX 1050 Ti
#        GeForce GTX 1650
#        NVIDIA RTX 2000 Ada Generation
#        NVIDIA RTX 4000 SFF Ada Generation
#        NVIDIA RTX PRO 2000 Blackwell
#        NVIDIA RTX PRO 4000 Blackwell SFF Edition
#      (DVA3H/DVA3L/DVA7H 같은 모델 등급 태그와 함께 저장되어 있음)
#      Quadro P1000은 이 목록에 없다 -> "호환되지 않음" 표시.
#    - 이 문자열들은 NULL 구분자 없이 통째로 이어붙어 있어(아마
#      boost::regex 패턴 하나로 컴파일됨), 라이브러리 자체를 바이너리
#      패치하는 건 위험하다(길이가 안 맞으면 ELF 오프셋이 전부 깨짐).
#
# 4. => 결론: 이 "호환되지 않음" 표시는 순수 UI 라벨링용 체크이고,
#    실제 딥러닝 동작에는 영향이 없다. 그래도 UI에 뜨는 경고 자체가
#    거슬린다면, libsynogpuinfo.so.7을 건드리는 대신 그것이 호출하는
#    "/usr/bin/nvidia-smi"를 감싸는 wrapper로 --query-gpu=name 출력의
#    모델명만 화이트리스트에 있는 이름으로 치환하는 게 훨씬 안전하다
#    (원본 드라이버/DVA 파이프라인은 전혀 안 건드림, 되돌리기도 쉬움).
#
# ============================================================================
# 그 외 이번 조사에서 확인된 별개의 함정들 (이 스크립트와 무관하지만 기록)
# ============================================================================
#
# - "default" 라이선스(DVA 모델 기본 제공 8개 디바이스 라이선스)는
#   NAS의 모델 아이덴티티(synoinfo.conf의 unique=)와 시리얼 번호 조합에
#   묶여 있다. dva3219 -> dva3221로 모델 마이그레이션만 하고 시리얼을
#   맞는 규칙으로 안 바꾸면 SYNO.SurveillanceStation.License(version=1,
#   method=Load)의 quota가 0으로 나오고 카메라 추가 시 "라이선스 없음"
#   오류가 뜬다. 시리얼을 해당 모델 규칙에 맞게 교체하고 재부팅하면
#   quota=8로 정상 복원된다.
#
# - /usr/lib/modules/nvidia*.ko 는 SPK 설치 스크립트가 매번 재생성하는
#   파일이 아니라, DSM 설치/마이그레이션 시점에 한 번 배치되는 팩토리
#   드라이버 파일이다. 실수로 지우면(예: 다른 프로젝트의 잔재 정리 중)
#   재부팅이나 NVIDIARuntimeLibrary 재설치로도 복구되지 않는다. 복구
#   방법은 DSM 마이그레이션(모델 재설정)뿐이었다 - 백업 없이 지우지 말 것.
#
# - `find /var/packages/<pkg>/target ...` 같은 명령에 `-L`을 빼먹으면
#   target이 심볼릭 링크라서 내용이 하나도 안 보인다("비어있다"는
#   오진단의 원인이었음). DSM 패키지 디렉토리를 find로 조사할 땐 항상
#   `find -L`을 쓸 것.
#
# ============================================================================
# 사용법
# ============================================================================
#   ssh로 DSM 실기에 접속한 뒤 root로 실행:
#     sh dva-gpu-compat-spoof.sh apply     # wrapper 적용
#     sh dva-gpu-compat-spoof.sh revert    # 원본 nvidia-smi로 복구
#     sh dva-gpu-compat-spoof.sh status    # 현재 상태 확인
#
#   적용 직후에는 Surveillance Station을 완전히 재시작(stop -> start)
#   해줄 것을 권장한다 - wrapper 교체 타이밍에 synodvad가 일시적으로
#   불안정(주기적 segfault) 해지는 게 실기에서 관찰됐다. 원인은 wrapper
#   자체로 재현 확정은 못 했지만(원복 후에도 한동안 재현됨), 완전
#   재시작으로 매번 안정화됐다.
#
#   화이트리스트에 넣을 대체 이름은 SPOOF_NAME 변수로 바꿀 수 있다.
#   기본값은 GTX1650(가장 흔한 DVA 시리즈 공인 카드).
#
set -eu

REAL_NVIDIA_SMI=/usr/bin/nvidia-smi
BACKUP_NVIDIA_SMI=/usr/bin/nvidia-smi.real
REAL_GPU_NAME="${REAL_GPU_NAME:-Quadro P1000}"
SPOOF_NAME="${SPOOF_NAME:-GeForce GTX 1650}"

apply() {
    if [ -f "$BACKUP_NVIDIA_SMI" ]; then
        echo "already applied (backup already exists at $BACKUP_NVIDIA_SMI)" >&2
        exit 1
    fi
    [ -f "$REAL_NVIDIA_SMI" ] || { echo "no nvidia-smi at $REAL_NVIDIA_SMI - is NVIDIARuntimeLibrary installed?" >&2; exit 1; }

    mv "$REAL_NVIDIA_SMI" "$BACKUP_NVIDIA_SMI"
    cat > "$REAL_NVIDIA_SMI" <<EOF
#!/bin/sh
# dva-gpu-compat-spoof.sh 가 생성한 wrapper. 원본은 $BACKUP_NVIDIA_SMI.
# DSM Info Center의 SYNOGpuIsModelSupportGpu() (libsynogpuinfo.so.7)가
# 이 바이너리의 --query-gpu=name 출력을 화이트리스트와 대조하는데,
# "$REAL_GPU_NAME"이 목록에 없어 "호환되지 않음"으로 뜨는 걸 막기 위한
# 라벨링 우회. 실제 드라이버/DVA 동작에는 영향 없음.
OUT=\$("$BACKUP_NVIDIA_SMI" "\$@")
RC=\$?
echo "\$OUT" | sed "s/$REAL_GPU_NAME/$SPOOF_NAME/g"
exit \$RC
EOF
    chmod 0755 "$REAL_NVIDIA_SMI"
    echo "applied: $REAL_GPU_NAME -> $SPOOF_NAME"
    echo "권장: Surveillance Station을 stop 후 start로 완전 재시작할 것"
}

revert() {
    [ -f "$BACKUP_NVIDIA_SMI" ] || { echo "no backup found - nothing to revert" >&2; exit 1; }
    rm -f "$REAL_NVIDIA_SMI"
    mv "$BACKUP_NVIDIA_SMI" "$REAL_NVIDIA_SMI"
    chmod 0755 "$REAL_NVIDIA_SMI"
    echo "reverted to original nvidia-smi"
}

status() {
    if [ -f "$BACKUP_NVIDIA_SMI" ]; then
        echo "wrapper ACTIVE ($REAL_GPU_NAME -> $SPOOF_NAME)"
    else
        echo "wrapper NOT active (original nvidia-smi in place)"
    fi
    [ -x "$REAL_NVIDIA_SMI" ] && "$REAL_NVIDIA_SMI" --query-gpu=name --format=csv,noheader 2>&1
}

case "${1:-}" in
    apply)  apply ;;
    revert) revert ;;
    status) status ;;
    *) echo "usage: $0 {apply|revert|status}" >&2; exit 1 ;;
esac
