#!/bin/sh

# Docker Ubuntu

# Genernal Options
NGINX='1'
LNMP='1'
VNC='1'
ARIA2='1'
ARIA2_BUILD='1'
RCLONE='1'
YOUTUBE_DL='1'

TIMEZONE="Asia/Shanghai"
USER_NAME='vnc'
USER_PWD='_123456_'

# NGINX
NGINX_ADDON='/etc/nginx/sites-addon'

# PHP Options
PHP_MEMORY_LIMIT='512M'
PHP_UPLOAD_MAX_FILESIZE='50M'
PHP_MAX_FILE_UPLOADS='200'
PHP_MAX_EXECUTION_TIME='600'
PHP_POST_MAX_SIZE='100M'

# MySQL
MYSQL_PWD="$USER_PWD"

# VNC Options
VNC='1'
VNC_DISPLAY='1024x768'
VNC_DISPLAY_DEPTH="16"
VNC_PORT='5901'
VNC_HTTP_PORT='6081'
VNC_PWD="$USER_PWD"

CUR_DIR=$(cd "$(dirname "$0")";pwd)

supervisor_restart() {
	if pidof supervisord; then
		/usr/bin/supervisorctl reload
	else
		/etc/init.d/supervisor restart
	fi
}

add_user() {
	HOME_PATH='/root'
	[ "$USER_NAME" = 'root' ] || {
		useradd  -m -U -s /bin/bash $USER_NAME
		HOME_PATH="/home/$USER_NAME"
		echo "${USER_NAME}    ALL=(ALL) ALL" >> /etc/sudoers
		echo "${USER_NAME}:${USER_PWD}"|chpasswd
	}
	echo "root:${USER_PWD}"|chpasswd
}

install_base() {
	apt-get update && \
	apt-get install -y --no-install-recommends \
	bash psmisc iputils-ping curl wget axel git supervisor zip unzip unrar software-properties-common bc htop pwgen sudo vim-tiny net-tools rsync
	mkdir -p /etc/supervisor/conf.d/
	mkdir -p /data
}

install_build_tool() {
	[ $BUILD_TOOL = '1' ] && return 1
	apt-get install -y --no-install-recommends \
	build-essential autotools-dev libltdl-dev libtool autoconf autopoint automake pkgconf
	BUILD_TOOL='1'
}

install_ssh() {
	apt-get install -y --no-install-recommends openssh-server
	[ -f '/etc/ssh/sshd_config' ] || return 1
	sed -e '/PermitRootLogin/d' -e '/UsePAM/d' -e '/TCPKeepAlive/d' -e '/ClientAliveInterval/d' -e '/ClientAliveCountMax/d' -i /etc/ssh/sshd_config
	cat <<-EOF >>/etc/ssh/sshd_config
	PermitRootLogin yes
	UsePAM no
	TCPKeepAlive yes
	ClientAliveInterval 360
	ClientAliveCountMax 20
	EOF
	mkdir -p /run/sshd
	supervisor_ssh
}

supervisor_ssh() {
	cat <<-EOF > /etc/supervisor/conf.d/ssh.conf
	[program:sshd]
	command=/usr/sbin/sshd -D
	user=root
	autorestart=true
	priority=0
	EOF
}

install_nginx() {
	[ "$NGINX" = '1' ] || return 1

	apt-get install -y --no-install-recommends nginx-extras spawn-fcgi fcgiwrap

	mkdir -p /www/html && chown -R www-data:www-data /www
	mkdir -p $NGINX_ADDON
	mkdir -p /data/download && chmod -R 777 /data/download
	ln -s /data/download /www/download

	cp /usr/share/nginx/html/index.html /www/html

	[ "$LNMP" = '1' ] && echo "<?php phpinfo(); ?>" >/www/html/index.php

	[ "$VNC" = '1' ] && cat <<-EOF >$NGINX_ADDON/vnc
	location = /vnc.html {
	    return 301 \$scheme://\$host:$VNC_HTTP_PORT/vnc_auto.html;
	}
	location = /vnc_auto.html {
	    return 301 \$scheme://\$host:$VNC_HTTP_PORT/vnc_auto.html;
	}
	location = /websockify {
	    proxy_http_version 1.1;
	    proxy_set_header Upgrade \$http_upgrade;
	    proxy_set_header Connection "upgrade";
	    proxy_pass http://127.0.0.1:$VNC_HTTP_PORT;
	}
	EOF

	# PHP
	cat <<-EOF >$NGINX_ADDON/php
	location ~ \.php\$ {
	    fastcgi_split_path_info ^(.+.php)(/.*)\$;
	    try_files \$uri =404;
	    fastcgi_keep_conn on;
	    include /etc/nginx/fastcgi_params;
	    fastcgi_pass unix:/run/php/php7.0-fpm.sock;
	    fastcgi_index index.php;
	    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
	}
	EOF

	# PHP & PHPMyAdmin
	cat <<-EOF >$NGINX_ADDON/php_phpmyadmin
	location /phpmyadmin {
		alias /www/phpmyadmin;
	}
	location ~ \.php\$ {
		fastcgi_pass unix:/run/php/php7.0-fpm.sock;
		fastcgi_index index.php;
		include /etc/nginx/fastcgi_params;
		set \$fastcgi_script_root \$document_root;
		if (\$fastcgi_script_name ~ /phpmyadmin/(.+.php)\$) {
				set \$fastcgi_script_root /www;
		}
		fastcgi_param SCRIPT_FILENAME \$fastcgi_script_root\$fastcgi_script_name;
	}
	EOF

	# RClone
	cat <<-EOF >$NGINX_ADDON/rclone
	location /rclone {
	    proxy_pass http://127.0.0.1:53682/auth;
	}
	EOF

	# Erroe Page
	cat <<-EOF >$NGINX_ADDON/error_page.conf
	error_page 404 /404.html;
	location = /404.html {
	    root /usr/share/nginx/html;
	}
	error_page 500 502 503 504 /50x.html;
	location = /50x.html {
	    root /usr/share/nginx/html;
	}
	EOF

	# FastCGI
	cat <<-EOF $NGINX_ADDON/fastcgi.conf
	location /cgi-bin/ {
	    fastcgi_pass unix:/var/run/fcgiwrap.socket;
	    include /etc/nginx/fastcgi_params;
	    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
	    fancyindex on;
	}
	EOF

	# FancyIndex
	cat <<-EOF >$NGINX_ADDON/fancyindex.conf
	fancyindex on;
	fancyindex_localtime on; #on for local time zone. off for GMT
	fancyindex_exact_size off; #off for human-readable. on for exact size in bytes
	fancyindex_header "/fancyindex/header.html";
	fancyindex_footer "/fancyindex/footer.html";
	fancyindex_ignore "fancyindex"; #ignore this directory when showing list
	fancyindex_name_length 255;
	location /fancyindex/ {
	    alias /www/fancyindex/;
	}
	EOF

	# Aria2
	cat <<-EOF >$NGINX_ADDON/aria2
	location /aria2/ {
	    alias /www/aria2/;
	    index index.html;
	}
	location /jsonrpc {
	    proxy_pass http://127.0.0.1:6800/jsonrpc;
	    proxy_http_version 1.1;
	    proxy_set_header Upgrade \$http_upgrade;
	    proxy_set_header Connection "upgrade";
	}
	EOF

	# Download
	cat <<-EOF >$NGINX_ADDON/download.conf
	location /dl/ {
		alias /www/download/;
		index _no_index;
	}
	EOF

	# Default
	cat <<-EOF >/etc/nginx/sites-enabled/default
	server {
	listen 80 default_server;
	server_name localhost;
	root /www/html;
	index index.html index.htm index.php;
	location / {
	    try_files \$uri \$uri/ =404;
	}
	include $NGINX_ADDON/*.conf;
	}
	EOF

	supervisor_nginx
}

supervisor_nginx() {
	cat <<-EOF > /etc/supervisor/conf.d/nginx.conf
	[program:nginx]
	command=nginx -c /etc/nginx/nginx.conf
	user=root
	autorestart=true
	priority=30
	EOF
}

install_lnmp() {
	[ "$LNMP" = '1' ] || return 1

	# MySQL Auto Set Password
	echo "mysql-server mysql-server/root_password password $MYSQL_PWD"|debconf-set-selections
	echo "mysql-server mysql-server/root_password_again password $MYSQL_PWD"|debconf-set-selections

	which nginx &>/dev/null || install_nginx
	apt-get install -y --no-install-recommends \
	php-fpm \
	php-mysql php-pgsql php-sqlite3 php-redis php-gd php-odbc \
	php-curl php-common php-zip php-bz2 php-mcrypt php-mbstring php-intl php-sybase php-pspell php-cli php-bcmath php-interbase php-recode php-readline php-gmp php-pear php-xdebug php-all-dev \
	php-xml php-xmlrpc php-json php-cgi \
	php-imap php-soap php-ldap php-fxsl \
	php-opcache php-apcu \
	mysql-server mysql-client

	curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

	sed -Ei -e "s/;?cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" \
	-e "s|;?date\.timezone.*|date.timezone=$TIMEZONE|" \
	-e "s/.*memory_limit.*/memory_limit=$PHP_MEMORY_LIMIT/" \
	-e "s/.*upload_max_filesize.*/upload_max_filesize=$PHP_UPLOAD_MAX_FILESIZE/" \
	-e "s/.*max_file_uploads.*/max_file_uploads=$PHP_MAX_FILE_UPLOADS/" \
	-e "s/.*post_max_size.*/post_max_size=$PHP_POST_MAX_SIZE/" \
	-e "s/.*error_reporting\s*=.*/error_reporting=E_ALL/" \
	-e "s/.*display_errors\s*=.*/display_errors=On/" \
	-e "s/^;?error_log\s*=.*/error_log=\/var\/logs\/php_errors.log/" \
	/etc/php/7.0/fpm/php.ini

	sed -Ei -e "s|;?date\.timezone.*|date.timezone=$TIMEZONE|" \
	/etc/php/7.0/cli/php.ini

	sed -Ei -e "s/;?daemonize\s*=.*/daemonize=yes/" \
	/etc/php/7.0/fpm/php-fpm.conf

	php_opcache
	php_apcu

	php_phpmyadmin &

	supervisor_lnmp
}

supervisor_lnmp() {
	cat <<-EOF > /etc/supervisor/conf.d/php.conf
	[program:php]
	command=php-fpm7.1
	user=root
	autorestart=true
	priority=100
	EOF

	cat <<-EOF > /etc/supervisor/conf.d/mysql.conf
	[program:mysql]
	command=mysqld
	user=root
	autorestart=true
	priority=100
	EOF
}

php_phpmyadmin() {
	DL=$(curl -sSL https://www.phpmyadmin.net/downloads/ 2>/dev/null|grep -Eo 'http[^"]+phpMyAdmin-[0-9.]+-english.tar.(gz|bz2)'|sort -ru|head -n1)
	[ -z "$DL" ] && return 1
	FILE_NAME=$(echo "$DL"|sed -E 's|.*/||')
	curl "$DL" >$FILE_NAME
	[ -f "$FILE_NAME" ] && {
		rm -rf /www/phpmyadmin
		tar -xf $FILE_NAME -C /www && mv /www/$(ls -al|grep -Ei '^d.*phpmyadmin'|head -n1|awk '{print $9}') /www/phpmyadmin
		rm -f $FILE_NAME
	}
}

php_opcache() {
	find /usr|grep opcache.so &>/dev/null || return 1
	echo "zend_extension=opcache.so
opcache.enable=1
opcache.enable_cli=1
opcache.fast_shutdown=1
opcache.memory_consumption=${OPCACHE_MEM_SIZE:-128}
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=5413
opcache.revalidate_freq=60">/etc/php/7.0/fpm/conf.d/10-opcache.ini
}

php_apcu() {
	find /usr|grep apcu.so &>/dev/null || return 1
	echo "extension=apcu.so
apc.enabled=1
apc.shm_size=${APC_SHM_SIZE:-128M}
apc.ttl=7200">/etc/php/7.0/fpm/conf.d/20-apcu.ini
}

build_aria2() {
	[ $BUILD_TOOL = '1' ] || install_build_tool
	rm -rf aria2
	git clone https://github.com/aria2/aria2.git aria2 && cd aria2 && {
		LINE=$(cat src/OptionHandlerFactory.cc|grep -n 'TEXT_CHECK_CERTIFICATE'|sed -E 's|:.*||')
		[ -z "$LINE" ] || LINE=$(($LINE+1))

		cat src/OptionHandlerFactory.cc | \
		# MAX_CONNECTION_PER_SERVER
		sed -E "s|\"1\", 1, 16, 'x'|\"16\", 1, -1, 'x'|" | \
		# MAX_CONCURRENT_DOWNLOADS
		sed -E "s|\"5\", 1, -1, 'j'|\"128\", 1, -1, 'j'|" | \
		# MIN_SPLIT_SIZE
		sed -E "s|\"5\", 1, -1, 'j'|\"128\", 1, -1, 'j'|" | \
		# MIN_SPLIT_SIZE
		sed -E "s|\"20M\", 1_m, 1_g, 'k'|\"1M\", 1_k, 1_g, 'k'|" | \
		# CONNECT_TIMEOUT
		sed -E "s|\"60\", 1, 600|\"30\", 1, 600|" | \
		# PIECE_LENGTH
		sed -E "s|\"1M\", 1_m, 1_g|\"1M\", 1_k, 1_g|" | \
		# RETRY_WAIT
		sed -E "s|TEXT_RETRY_WAIT, \"0\", 0, 600|TEXT_RETRY_WAIT, \"2\", 0, 600|" | \
		# SPLIT
		sed -E "s|TEXT_SPLIT, \"5\", 1, -1, 's'|TEXT_SPLIT, \"128\", 1, -1, 's'|" | \
		# CONTINUE
		sed -E "s|TEXT_CONTINUE, A2_V_FALSE|TEXT_CONTINUE, A2_V_TRUE|" | \
		# CHECK_CERTIFICATE
		sed -E "${LINE}s|A2_V_TRUE|A2_V_FALSE|" \
		>./src/OptionHandlerFactory.cc_

		mv -f ./src/OptionHandlerFactory.cc_ ./src/OptionHandlerFactory.cc

		autoreconf -i && ./configure && make && make install && ARIA2_BUILD='1' && rm -rf aria2
	}
}

install_aria2() {
	[ "$ARIA2" = '1' ] || return 1

	build_aria2

	which aria2c &>/dev/null || {
		apt-get install -y --no-install-recommends aria2 || return 1
	}

	rm -rf /www/aria2
	wget -O /tmp/ariang.zip https://github.com/mayswind/AriaNg-DailyBuild/archive/master.zip && {
		rm -rf /tmp/aria2ng
		unzip /tmp/ariang.zip -d /tmp/aria2ng
		mv -f "/tmp/aria2ng/$(ls /tmp/aria2ng|head -n1)" /www/aria2
		rm -rf /tmp/ariang.zip
		chown -R www-data:www-data /www/aria2
	}

	mkdir -p /etc/aria2
	mkdir -p /var/aria2
	touch /var/aria2/aria2.session && chmod 666 /var/aria2/aria2.session

	cat <<-EOF >/etc/aria2/aria2.conf
	dir=/www/download
	disk-cache=32M
	# on-download-complete=/conf/a2/a2-on-complete.sh
	save-session=/var/aria2/aria2.session
	input-file=/var/aria2/aria2.session
	file-allocation=trunc
	log-level=warn
	# peer-id-prefix=-TR2770-
	# user-agent=Transmission/2.77
	enable-http-pipelining=true
	max-concurrent-downloads=5
	max-connection-per-server=16
	split=10
	min-split-size=10M
	continue=true
	max-overall-download-limit=0
	max-overall-upload-limit=1K
	seed-time=0
	enable-rpc=true
	rpc-listen-all=true
	rpc-allow-origin-all=true
	rpc-listen-port=6800
	bt-max-peers=100
	seed-time=0
	EOF

	[ "$ARIA2_BUILD" = '1' ] && {
		sed -e 's/max-concurrent-downloads=.*/max-concurrent-downloads=1024/' -e 's/^split=.*/split=1024/' -i /etc/aria2/aria2.conf
	}

	BT_TRACKER=$(curl -SL https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt|grep -E '^(udp|http)')
	[ -z "$BT_TRACKER" ] || {
		BT_TRACKER="bt-tracker="$(echo $BT_TRACKER|sed 's| |,|g')
	}
	echo "$BT_TRACKER" >> /etc/aria2/aria2.conf

	supervisor_aria2

	mv $NGINX_ADDON/aria2 $NGINX_ADDON/aria2.conf
}

supervisor_aria2() {
	cat <<-EOF >/etc/supervisor/conf.d/aria2.conf
	[program:aria2]
	priority=30
	directory=/www/download
	command=aria2c --conf-path=/etc/aria2/aria2.conf
	user=www-data
	autostart=true
	autorestart=true
	EOF
}

install_youtube_dl() {
	[ "$YOUTUBE_DL" = '1' ] || return 1

	curl -L https://yt-dl.org/downloads/latest/youtube-dl -o /usr/sbin/youtube-dl && chmod a+rx /usr/sbin/youtube-dl
}

install_rclone() {
	[ "$RCLONE" = '1' ] || return 1

	RCLONE_DL=$(curl -sSL https://rclone.org/downloads/|grep -Eo 'https?://[^"]+v[0-9.]+-linux-amd64\.zip'|head -n1)
	[ -z "$RCLONE_DL" ] && return 1
	curl $RCLONE_DL >/tmp/rclone.zip && unzip /tmp/rclone.zip -d /tmp && {
		mv $(ls -d /tmp/rclone-*)/rclone /usr/sbin/rclone && chmod +x /usr/sbin/rclone
		rm -rf /tmp/rclone*
	}
	mv $NGINX_ADDON/rclone $NGINX_ADDON/rclone.conf
}

install_timezone() {
	apt-get install -y --force-yes --no-install-recommends \
	tzdata
	ln -snf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
	echo $TIMEZONE > /etc/timezone
}

install_vnc() {
	[ "$VNC" = '1' ] || return 1

    apt-get install -y --force-yes --no-install-recommends \
        lxde x11vnc xvfb \
        gtk2-engines-murrine ttf-ubuntu-font-family fonts-wqy-microhei \
        firefox \
	xdotool \
        python-pip python-dev \
        mesa-utils libgl1-mesa-dri \
        gnome-themes-standard gtk2-engines-pixbuf gtk2-engines-murrine pinta xfce4-terminal

    # Sublime Text
    SUBLIME_TEXT_URL=$(curl -sSL https://www.sublimetext.com/3|grep -Eo 'https?://[^"]+amd64\.deb')
    curl -sSL $SUBLIME_TEXT_URL > /tmp/sublime_text.deb && dpkg -i /tmp/sublime_text.deb && rm -f /tmp/sublime_text.deb

	mkdir -p $HOME_PATH/.x11vnc
	x11vnc -storepasswd $VNC_PWD $HOME_PATH/.x11vnc/x11vnc.pass

	
	vnc_lxde
	rm -f /usr/share/applications/lxterminal.desktop

	# noVNC
	git clone https://github.com/novnc/noVNC.git /usr/share/noVNC
	git clone https://github.com/novnc/websockify.git /usr/share/noVNC/utils/websockify

	chown -R ${USER_NAME}:${USER_NAME} $HOME_PATH

	supervisor_vnc
}

supervisor_vnc() {
	cat <<-EOF >/etc/supervisor/conf.d/vnc.conf
[program:xvfb]
priority=10
directory=/
command=/usr/bin/Xvfb :1 -screen 0 ${VNC_DISPLAY}x${VNC_DISPLAY_DEPTH}
user=$USER_NAME
autostart=true
autorestart=true
stopsignal=QUIT
stdout_logfile=/var/log/xvfb.log
redirect_stderr=true
[program:lxsession]
priority=15
directory=$HOME_PATH
command=/usr/bin/lxsession
user=$USER_NAME
autostart=true
autorestart=true
stopsignal=QUIT
environment=DISPLAY=":1",HOME="$HOME_PATH"
stdout_logfile=/var/log/lxsession.log
redirect_stderr=true
[program:x11vnc]
priority=20
directory=/
command=x11vnc -display :1 -xkb -forever -shared -rfbauth $HOME_PATH/.x11vnc/x11vnc.pass -rfbport $VNC_PORT
user=$USER_NAME
autostart=true
autorestart=true
stopsignal=QUIT
stdout_logfile=/var/log/x11vnc.log
redirect_stderr=true
[program:novnc]
priority=25
directory=/usr/share/noVNC/
command=/usr/share/noVNC/utils/launch.sh --vnc localhost:$VNC_PORT --listen $VNC_HTTP_PORT
user=$USER_NAME
autostart=true
autorestart=true
stopsignal=QUIT
stdout_logfile=/var/log/novnc.log
redirect_stderr=true
stopasgroup=true
	EOF
}

vnc_lxde() {
	mkdir -p $HOME_PATH/.config

	wget -O /usr/share/lxde/images/ubuntu.png https://www.davidtan.org/wp-content/uploads/2010/01/ubuntu-logo-icon.png
	mkdir -p $HOME_PATH/.config/lxpanel/LXDE/panels
	cat <<-EOF >$HOME_PATH/.config/lxpanel/LXDE/panels/panel
	# lxpanel <profile> config file. Manually editing is not recommended.
	# Use preference dialog in lxpanel to adjust config when you can.
	Global {
	  edge=top
	  allign=left
	  margin=0
	  widthtype=percent
	  width=100
	  height=24
	  transparent=1
	  tintcolor=#000000
	  alpha=255
	  setdocktype=1
	  setpartialstrut=1
	  usefontcolor=1
	  fontcolor=#ffffff
	  background=0
	  backgroundfile=/usr/share/lxpanel/images/background.png
	  align=left
	  iconsize=24
	  autohide=0
	  usefontsize=1
	  fontsize=9
	}
	Plugin {
	  type=space
	  Config {
	    Size=10
	  }
	}
	Plugin {
	  type=menu
	  Config {
	    image=/usr/share/lxde/images/ubuntu.png
	    system {
	    }
	    separator {
	    }
	    item {
	      command=run
	    }
	    separator {
	    }
	    item {
	      image=gnome-logout
	      command=logout
	    }
	  }
	}
	Plugin {
	  type=space
	  Config {
	    Size=10
	  }
	}
	Plugin {
	  type=launchbar
	  Config {
	    Button {
	      id=menu://applications/System/xfce4-terminal.desktop
	    }
	    Button {
	      id=pcmanfm.desktop
	    }
	    Button {
	      id=lxde-x-www-browser.desktop
	    }
	  }
	}
	Plugin {
	  type=space
	  Config {
	    Size=10
	  }
	}
	Plugin {
	  type=wincmd
	  Config {
	    Button1=iconify
	    Button2=shade
	  }
	}
	Plugin {
	  type=space
	  Config {
	    Size=10
	  }
	}
	Plugin {
	  type=pager
	  Config {
	  }
	}
	Plugin {
	  type=space
	  Config {
	    Size=4
	  }
	}
	Plugin {
	  type=taskbar
	  expand=1
	  Config {
	    tooltips=1
	    IconsOnly=0
	    AcceptSkipPager=1
	    ShowIconified=1
	    ShowMapped=1
	    ShowAllDesks=0
	    UseMouseWheel=1
	    UseUrgencyHint=1
	    FlatButton=1
	    MaxTaskWidth=150
	    spacing=1
	    SameMonitorOnly=0
	    GroupedTasks=1
	    DisableUpscale=0
	  }
	}
	Plugin {
	  type=cpu
	  Config {
	  }
	}
	Plugin {
	  type=tray
	  Config {
	  }
	}
	Plugin {
	  type=dclock
	  Config {
	    ClockFmt=%l:%M %p
	    TooltipFmt=%A %x
	    BoldFont=1
	    IconOnly=0
	    CenterText=0
	  }
	}
	Plugin {
	  type=launchbar
	  Config {
	    Button {
	      id=lxde-screenlock.desktop
	    }
	    Button {
	      id=lxde-logout.desktop
	    }
	  }
	}
	EOF

	mkdir -p $HOME_PATH/.config/gtk-3.0
	cat <<-EOF >$HOME_PATH/.config/gtk-3.0/settings.ini
	[Settings]
	gtk-theme-name=Natura
	gtk-icon-theme-name=gnome
	gtk-font-name=Sans 10
	gtk-cursor-theme-size=18
	gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
	gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
	gtk-button-images=1
	gtk-menu-images=1
	gtk-enable-event-sounds=1
	gtk-enable-input-feedback-sounds=1
	gtk-xft-antialias=1
	gtk-xft-hinting=1
	gtk-xft-hintstyle=hintslight
	gtk-xft-rgba=rgb
	EOF

	mkdir -p $HOME_PATH/.config/lxsession/LXDE
	cat <<-EOF >$HOME_PATH/.config/lxsession/LXDE/desktop.conf
	[Session]
	window_manager=openbox-lxde
	windows_manager/command=openbox
	windows_manager/session=LXDE
	disable_autostart=no
	polkit/command=lxpolkit
	clipboard/command=lxclipboard
	xsettings_manager/command=build-in
	proxy_manager/command=build-in
	keyring/command=ssh-agent
	quit_manager/command=lxsession-logout
	quit_manager/image=/usr/share/lxde/images/logout-banner.png
	quit_manager/layout=top
	lock_manager/command=lxlock
	terminal_manager/command=lxterminal
	launcher_manager/command=lxpanelctl
	[GTK]
	sNet/ThemeName=Natura
	sNet/IconThemeName=gnome
	sGtk/FontName=Sans 10
	iGtk/ToolbarStyle=3
	iGtk/ButtonImages=1
	iGtk/MenuImages=1
	iGtk/CursorThemeSize=18
	iXft/Antialias=1
	iXft/Hinting=1
	sXft/HintStyle=hintslight
	sXft/RGBA=rgb
	iNet/EnableEventSounds=1
	iNet/EnableInputFeedbackSounds=1
	sGtk/ColorScheme=
	iGtk/ToolbarIconSize=3
	sGtk/CursorThemeName=DMZ-White
	[Mouse]
	AccFactor=20
	AccThreshold=10
	LeftHanded=0
	[Keyboard]
	Delay=500
	Interval=30
	Beep=1
	[State]
	guess_default=true
	[Dbus]
	lxde=true
	[Environment]
	menu_prefix=lxde-
	EOF

	mkdir -p $HOME_PATH/.config/openbox
	cat <<-EOF >$HOME_PATH/.config/openbox/lxde-rc.xml
	<?xml version="1.0" encoding="UTF-8"?>
	<!-- Do not edit this file, it will be overwritten on install.
	        Copy the file to $HOME/.config/openbox/ instead. -->
	<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
	  <resistance>
	    <strength>10</strength>
	    <screen_edge_strength>20</screen_edge_strength>
	  </resistance>
	  <theme>
	    <name>Natura</name>
	    <titleLayout>NLIMC</titleLayout>
	    <keepBorder>yes</keepBorder>
	    <animateIconify>yes</animateIconify>
	    <font place="ActiveWindow">
	      <name>sans</name>
	      <size>10</size>
	      <!-- font size in points -->
	      <weight>bold</weight>
	      <!-- 'bold' or 'normal' -->
	      <slant>normal</slant>
	      <!-- 'italic' or 'normal' -->
	    </font>
	    <font place="InactiveWindow">
	      <name>sans</name>
	      <size>10</size>
	      <!-- font size in points -->
	      <weight>bold</weight>
	      <!-- 'bold' or 'normal' -->
	      <slant>normal</slant>
	      <!-- 'italic' or 'normal' -->
	    </font>
	    <font place="MenuHeader">
	      <name>sans</name>
	      <size>9</size>
	      <!-- font size in points -->
	      <weight>normal</weight>
	      <!-- 'bold' or 'normal' -->
	      <slant>normal</slant>
	      <!-- 'italic' or 'normal' -->
	    </font>
	    <font place="MenuItem">
	      <name>sans</name>
	      <size>9</size>
	      <!-- font size in points -->
	      <weight>normal</weight>
	      <!-- 'bold' or 'normal' -->
	      <slant>normal</slant>
	      <!-- 'italic' or 'normal' -->
	    </font>
	    <font place="ActiveOnScreenDisplay">
	      <name>sans</name>
	      <size>9</size>
	      <!-- font size in points -->
	      <weight>bold</weight>
	      <!-- 'bold' or 'normal' -->
	      <slant>normal</slant>
	      <!-- 'italic' or 'normal' -->
	    </font>
	    <font place="InactiveOnScreenDisplay">
	      <name>sans</name>
	      <size>9</size>
	      <!-- font size in points -->
	      <weight>bold</weight>
	      <!-- 'bold' or 'normal' -->
	      <slant>normal</slant>
	      <!-- 'italic' or 'normal' -->
	    </font>
	  </theme>
	  <desktops>
	    <!-- this stuff is only used at startup, pagers allow you to change them
	       during a session
	       these are default values to use when other ones are not already set
	       by other applications, or saved in your session
	       use obconf if you want to change these without having to log out
	       and back in -->
	    <number>4</number>
	    <firstdesk>1</firstdesk>
	    <names>
	      <!-- set names up here if you want to, like this:
	    <name>desktop 1</name>
	    <name>desktop 2</name>
	    -->
	    </names>
	    <popupTime>875</popupTime>
	    <!-- The number of milliseconds to show the popup for when switching
	       desktops.  Set this to 0 to disable the popup. -->
	  </desktops>
	  <resize>
	    <drawContents>yes</drawContents>
	    <popupShow>Nonpixel</popupShow>
	    <!-- 'Always', 'Never', or 'Nonpixel' (xterms and such) -->
	    <popupPosition>Center</popupPosition>
	    <!-- 'Center', 'Top', or 'Fixed' -->
	    <popupFixedPosition>
	      <!-- these are used if popupPosition is set to 'Fixed' -->
	      <x>10</x>
	      <!-- positive number for distance from left edge, negative number for
	         distance from right edge, or 'Center' -->
	      <y>10</y>
	      <!-- positive number for distance from top edge, negative number for
	         distance from bottom edge, or 'Center' -->
	    </popupFixedPosition>
	  </resize>
	</openbox_config>
	EOF

	# pcmanfm
	mkdir -p $HOME_PATH/.config/pcmanfm/LXDE
	cat <<-EOF >$HOME_PATH/.config/pcmanfm/LXDE/desktop-items-0.conf
	[*]
	wallpaper_mode=stretch
	wallpaper_common=0
	wallpapers_configured=4
	wallpaper0=/usr/share/wallpapers/bg1.jpg
	desktop_bg=#000000
	desktop_fg=#ffffff
	desktop_shadow=#000000
	desktop_font=Sans 10
	show_wm_menu=0
	sort=mtime;ascending;mingle;
	show_documents=0
	show_trash=1
	show_mounts=1
	EOF

	# xfce terminal
	mkdir -p $HOME_PATH/.config/xfce4/terminal
	cat <<-EOF >$HOME_PATH/.config/xfce4/terminal/terminalrc
	[Configuration]
	FontName=Monospace 10
	MiscAlwaysShowTabs=FALSE
	MiscBell=FALSE
	MiscBordersDefault=TRUE
	MiscCursorBlinks=FALSE
	MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
	MiscDefaultGeometry=80x24
	MiscInheritGeometry=FALSE
	MiscMenubarDefault=TRUE
	MiscMouseAutohide=FALSE
	MiscToolbarDefault=FALSE
	MiscConfirmClose=TRUE
	MiscCycleTabs=TRUE
	MiscTabCloseButtons=TRUE
	MiscTabCloseMiddleClick=TRUE
	MiscTabPosition=GTK_POS_TOP
	MiscHighlightUrls=TRUE
	MiscScrollAlternateScreen=TRUE
	ColorPalette=#000000;#cc0000;#4e9a06;#c4a000;#3465a4;#75507b;#06989a;#d3d7cf;#555753;#ef2929;#8ae234;#fce94f;#739fcf;#ad7fa8;#34e2e2;#eeeeec
	EOF

	# wget -O ./hedera.deb https://github.com/sixsixfive/Hedera/raw/master/pkgs/hedera-current_testing.deb && {
	# 	dpkg -i hedera.deb || apt-get install -y --force-yes -f
	# 	cat /usr/share/themes/Hedera/gtk-2.0/settings.ini >/home/$USER_NAME/.gtkrc-2.0
	# 	rm -f ./hedera.deb
	# }

	# WallPaper
	mkdir -p /usr/share/wallpapers
	wget -O /usr/share/wallpapers/bg1.jpg "https://images.pexels.com/photos/1240/road-street-blur-blurred.jpg?dl&fit=crop&w=1920&h=1280"
}

install_base
add_user
install_ssh
install_timezone
install_nginx
install_lnmp
install_vnc
install_aria2
install_rclone
install_youtube_dl
