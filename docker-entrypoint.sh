#!/bin/bash
set -e

if [ ! -d "/data/files" ];then

	mv /usr/src/redmine/config /data/config
	mv /usr/src/redmine/files /data/files
	mv /usr/src/redmine/log /data/log
	mv /usr/src/redmine/public /data/public
	mv /usr/src/redmine/db /data/db
	mv /usr/src/redmine/Gemfile.lock /data/Gemfile.lock
    mkdir /data/sqlite
	chown -R rain:rain /data
else
    rm -rf /usr/src/redmine/config
    rm -rf /usr/src/redmine/files
    rm -rf /usr/src/redmine/log
    rm -rf /usr/src/redmine/public
    rm -rf /usr/src/redmine/db
    rm -rf /usr/src/redmine/Gemfile.lock
    rm -rf /usr/src/redmine/sqlite
fi

ln -s /data/config /usr/src/redmine/config
ln -s /data/files /usr/src/redmine/files
ln -s /data/log /usr/src/redmine/log
ln -s /data/public /usr/src/redmine/public
ln -s /data/db /usr/src/redmine/db
ln -s /data/Gemfile.lock /usr/src/redmine/Gemfile.lock
ln -s /data/sqlite /usr/src/redmine/sqlite


case "$1" in
	rails|rake|passenger)
		if [ ! -f './config/database.yml' ]; then

            echo >&2
            echo >&2 'warning: missing REDMINE_DB_MYSQL or REDMINE_DB_POSTGRES environment variables'
            echo >&2
            echo >&2 '*** Using sqlite3 as fallback. ***'
            echo >&2

            adapter='sqlite3'
            host='localhost'
            : "${REDMINE_DB_PORT:=}"
            : "${REDMINE_DB_USERNAME:=redmine}"
            : "${REDMINE_DB_PASSWORD:=}"
            : "${REDMINE_DB_DATABASE:=sqlite/redmine.db}"
            : "${REDMINE_DB_ENCODING:=utf8}"

            mkdir -p "$(dirname "$REDMINE_DB_DATABASE")"
            chown -R rain:rain "$(dirname "$REDMINE_DB_DATABASE")"

			REDMINE_DB_ADAPTER="$adapter"
			REDMINE_DB_HOST="$host"
			echo "$RAILS_ENV:" > config/database.yml
			for var in \
				adapter \
				host \
				port \
				username \
				password \
				database \
				encoding \
			; do
				env="REDMINE_DB_${var^^}"
				val="${!env}"
				[ -n "$val" ] || continue
				echo "  $var: \"$val\"" >> config/database.yml
			done
		fi

		# ensure the right database adapter is active in the Gemfile.lock
		bundle install --without development test

		if [ ! -s config/secrets.yml ]; then
			if [ "$REDMINE_SECRET_KEY_BASE" ]; then
				cat > 'config/secrets.yml' <<-YML
					$RAILS_ENV:
					  secret_key_base: "$REDMINE_SECRET_KEY_BASE"
				YML
			elif [ ! -f /usr/src/redmine/config/initializers/secret_token.rb ]; then
				rake generate_secret_token
			fi
		fi
		if [ "$1" != 'rake' -a -z "$REDMINE_NO_DB_MIGRATE" ]; then
        # gosu 临时获得管理员权限
			gosu rain rake db:migrate
		fi

		chown -R rain:rain files log public/plugin_assets

		# remove PID file to enable restarting the container
		rm -f /usr/src/redmine/tmp/pids/server.pid

		if [ "$1" = 'passenger' ]; then
			# Don't fear the reaper.
			set -- tini -- "$@"
		fi

		set -- gosu rain "$@"
		;;
esac

exec "$@"