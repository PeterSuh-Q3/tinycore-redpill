#!/bin/bash

# 사용법: ./set_shm.sh jellyfin 512
CONTAINER_NAME=${1:-jellyfin}
SHM_MB=${2}

if [ -z "$SHM_MB" ]; then
  echo "사용법: $0 <컨테이너명> <크기(MB)>"
  echo "예시:   $0 jellyfin 512"
  exit 1
fi

# MB → bytes 변환
SHM_BYTES=$(( SHM_MB * 1024 * 1024 ))

# 컨테이너 ID (short) 가져오기
SHORT_ID=$(docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format "{{.ID}}")
if [ -z "$SHORT_ID" ]; then
  echo "❌ 컨테이너 '${CONTAINER_NAME}' 를 찾을 수 없습니다."
  exit 1
fi

# full ID로 hostconfig.json 경로 찾기
CONFIG_PATH=$(find /volume1/@docker/containers -name "hostconfig.json" | grep "^/volume1/@docker/containers/${SHORT_ID}")
if [ -z "$CONFIG_PATH" ]; then
  echo "❌ hostconfig.json 을 찾을 수 없습니다. (ID: ${SHORT_ID})"
  exit 1
fi

echo "📄 설정 파일: $CONFIG_PATH"
CURRENT_BYTES=$(jq '.ShmSize' "$CONFIG_PATH")
CURRENT_MB=$(( CURRENT_BYTES / 1024 / 1024 ))
echo "📦 현재 ShmSize: ${CURRENT_BYTES} bytes (${CURRENT_MB}MB)"

# 컨테이너 중지
echo ""
echo "⏹  컨테이너 중지 중..."
docker stop "$CONTAINER_NAME"

# jq로 ShmSize 치환 (임시 파일 사용)
TMP_FILE=$(mktemp)
jq --argjson size "$SHM_BYTES" '.ShmSize = $size' "$CONFIG_PATH" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_PATH"

NEW_BYTES=$(jq '.ShmSize' "$CONFIG_PATH")
echo "✅ ShmSize 변경: ${CURRENT_MB}MB → ${SHM_MB}MB (${NEW_BYTES} bytes)"

# Docker 데몬 재시작
echo ""
echo "🔄 Docker 데몬 재시작 중... (pkg-ContainerManager-dockerd)"
systemctl restart pkg-ContainerManager-dockerd
echo "⏳ 데몬 안정화 대기 (10초)..."
sleep 10

# 컨테이너 시작
echo ""
echo "▶️  컨테이너 시작 중..."
docker start "$CONTAINER_NAME"
echo "⏳ 컨테이너 기동 대기 (5초)..."
sleep 5

# 적용 확인
echo ""
echo "============================================"
echo "            /dev/shm 적용 결과              "
echo "============================================"
docker exec "$CONTAINER_NAME" df -h /dev/shm
echo "============================================"
echo "🎉 완료: ${CONTAINER_NAME} ShmSize = ${SHM_MB}MB"
