#!/bin/sh

CUR_DIR=$(cd "$(dirname "$0")";pwd)
CUR_SCRIPT_NAME="${0##*/}"

install_package() {
    cat /etc/issue | grep -i 'ubuntu' && {
        apt-get update && apt-get install -y --no-install-recommends $1
        return 0
    }
    cat /etc/issue | grep -i 'alpine' && {
        apk update && apk add --no-cache --update $1
        return 0
    }
}

run() {
	if [ -z "$RUN" ]; then
		echo "Commands Run:"
		echo "ENV: RUN"
	else
		eval "$RUN"
	fi
}

run_url() {
	if [ -z "$RUN_URL" ]; then
		echo "Run Script From URL:"
		echo "EVV: RUN_URL"
	else
		which curl 2>/dev/null || (install_packagee curl)
		RETURN=$(curl $RUN_URL 2>/dev/null)
		[ -z "$RETURN" ] || {
			echo "$RETURN">/tmp/run_url.sh
			chmod 755 /tmp/run_url.sh
			/tmp/run_url.sh
		}
	fi
}

run_sh() {
	while read SCRIPT
	do
		echo "Running $SCRIPT"
		chmod +x "$SCRIPT"
		$SCRIPT
	done<<-EOF
	$(ls /run/*.sh)
	EOF
}

run
run_url
run_sh
$(which supervisord) -n -c /etc/supervisor/supervisord.conf
