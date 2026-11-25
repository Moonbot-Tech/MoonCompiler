#!/usr/bin/env bash
# Both database instances live under a fresh private directory.
set -euo pipefail
compiler=$(realpath "$1")
source_dir=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
mysql_pid=
cleanup() {
  if [[ -n "$mysql_pid" ]]; then
    kill "$mysql_pid" 2>/dev/null || :
    wait "$mysql_pid" || :
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT
cd "$work"
"$compiler" -dRELEASE "-FU$work" "-FE$work" "$source_dir/native_blob_bind.dpr"
export FIREBIRD_LOCK="$work" FIREBIRD_TMP="$work"
./native_blob_bind "$work/probe.fdb"

export MYSQL_UNIX_PORT="$work/mysql.sock"
mysqld --no-defaults --initialize-insecure --datadir="$work/data" --secure-file-priv=NULL \
  --log-error="$work/mysql-init.log" || { cat "$work/mysql-init.log"; exit 1; }
mysqld --no-defaults --datadir="$work/data" --socket="$MYSQL_UNIX_PORT" --pid-file="$work/mysql.pid" \
  --skip-networking --mysqlx=0 --secure-file-priv=NULL --innodb-buffer-pool-size=64M --log-error="$work/mysql.log" &
mysql_pid=$!
for _ in {1..100}; do
  mysqladmin --no-defaults --socket="$MYSQL_UNIX_PORT" --user=root ping --silent && break
  kill -0 "$mysql_pid" || { cat "$work/mysql.log"; exit 1; }
  sleep 0.2
done
./native_blob_bind mysql
