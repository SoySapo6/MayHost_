#!/bin/ash

cd /app

mkdir -p /app/var /var/log/panel/logs/ /var/log/supervisord/ /var/log/nginx/ /var/log/php7/ \
&& rm -rf /app/storage/logs/ \
&& chmod 777 /var/log/panel/logs/ \
&& ln -s /var/log/panel/logs/ /app/storage/

if [ ! -f /app/var/.env ]; then
  echo "external vars don't exist."
  APP_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
  echo "Generated app key: $APP_KEY"
  echo "APP_KEY=$APP_KEY" > /app/var/.env
else
  echo "external vars exist."
fi

cp /app/var/.env /app/.env

echo "Checking if https is required."
if [ -f /etc/nginx/conf.d/default.conf ]; then
  echo "Using nginx config already in place."
else
  if [ -z $LE_EMAIL ]; then
    echo "No letsencrypt email is set, using http config."
    cp .dev/docker/default.conf /etc/nginx/conf.d/default.conf
  else
    echo "Writing ssl config"
    cp .dev/docker/default_ssl.conf /etc/nginx/conf.d/default.conf
    sed -i "s|<domain>|$(echo $APP_URL | sed 's~http[s]*://~~g')|g" /etc/nginx/conf.d/default.conf
    certbot certonly -d $(echo $APP_URL | sed 's~http[s]*://~~g') --standalone -m $LE_EMAIL --agree-tos -n
  fi
fi

echo "Checking database status..."
until nc -z -v -w30 $DB_HOST $DB_PORT; do
  echo "Waiting for database connection..."
  sleep 5
done

echo "Migrating and Seeding D.B"
php artisan migrate --force
php artisan db:seed --force

echo "Starting cron jobs."
crond -L /var/log/crond -l 5

echo "Starting supervisord."
exec "$@"
