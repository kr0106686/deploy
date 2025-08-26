#!/bin/bash
set -e

# 사용법: ./deploy.sh server1.conf
if [ -z "$1" ]; then
  echo "❗ 사용법: ./deploy.sh <app config file>"
  exit 1
fi

CONFIG_FILE="config/server.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❗server 설정 파일이 없음: $CONFIG_FILE"
  exit 1
fi

CONFIG_APP_FILE="config/$1.conf"
if [ ! -f "$CONFIG_APP_FILE" ]; then
  echo "❗ APP 설정 파일이 없음: $CONFIG_APP_FILE"
  exit 1
fi

# 🔧 서버 설정 로드
source "$CONFIG_FILE"
source "$CONFIG_APP_FILE"

REMOTE_PATH="$REMOTE_PATH/$SERVER_DIR"

APP_NAME="server"
BUILD_TIME=$(date +%Y%m%d_%H%M%S)
OUTPUT="${APP_NAME}_${BUILD_TIME}"

LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/deployed.log"
mkdir -p "$LOG_DIR"

# 🛠 빌드
echo "🚀 [$REMOTE_HOST] 빌드 시작..."
cd $APP_DIR
go build -o "$OUT_DIR/$OUTPUT" "./$APP_MAIN"
echo "✅ 빌드 완료: $OUTPUT"

# 빌드대신
cd $APP_DIR
echo > "$OUT_DIR/$OUTPUT"

# 📦 복사
echo "📦 파일 전송 중..."
scp -i "$SSH_KEY" "$APP_DIR/$OUT_DIR/$OUTPUT" $APP_ENV \
  $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/

# 🌐 원격 실행
ssh -i "$SSH_KEY" $REMOTE_USER@$REMOTE_HOST << EOF
  set -e
  cd $REMOTE_PATH

  echo "🛑 기존 서버 종료..."
  if [ -f server.pid ]; then
    kill \$(cat server.pid) || true
    rm -f server.pid
  fi

  echo "📦 실행 파일 교체..."
  rm -f $APP_NAME
  mv $OUTPUT $APP_NAME

  echo "⚙️ .env.prod → .env 갱신..."
  if [ "" == "$APP_ENV" ]; then
    echo "❗.env: 없음"
  elif [ ".env" != "$APP_ENV" ]; then
    mv -f $APP_ENV .env
  fi

  echo "🚀 서버 실행..."
  nohup ./$APP_NAME > server.log 2>&1 &
  echo \$! > server.pid

  echo "🔎 현재 서버 PID: \$(cat server.pid)"
EOF

# 📋 원격 PID 가져오기
PID=$(ssh -i "$SSH_KEY" $REMOTE_USER@$REMOTE_HOST "cat $REMOTE_PATH/server.pid")

# 📝 로컬 로그 저장
cd /home/kr6686/p/deploy/v1
echo "$REMOTE_HOST PID=$PID TIME=$BUILD_TIME" >> "$LOG_FILE"

echo "✅ 배포 완료!"
echo "🗂 기록 저장됨: $LOG_FILE"