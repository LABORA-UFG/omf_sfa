#!/bin/sh
# wait-for-postgres.sh

set -e

host="$1"
shift
cmd="$@"

echo $host
echo $POSTGRES_USER
echo $POSTGRES_PASSWORD


until PGPASSWORD=$POSTGRES_PASSWORD psql -h "$host" -U $POSTGRES_USER $POSTGRES_DB -c '\q'; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done

>&2 echo "Postgres is up - executing command"
# echo "waiting a little longer for rabbitmq..."
# sleep 30
# echo "now executing..."
exec $cmd