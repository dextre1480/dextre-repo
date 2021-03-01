#!/bin/bash

##actaulizamos y reiniciamos
setenforce 0
sestatus -v
yum update -y
yum upgrade -y
reboot

##instalamos el epel repo
yum install epel-release -y
yum install vim nano wget unzip git -y

##instalar dependencias, si ves error continuas##
yum groupinstall 'Development Tools' -y
yum install gcc make automake autoconf libtool pcre pcre-devel libxml2 libxml2-devel httpd-devel -y
yum install gcc-c++ flex bison yajl yajl-devel curl curl-devel GeoIP-devel doxygen zlib-devel -y
yum install lmdb lmdb-devel libxml2 libxml2-devel ssdeep ssdeep-devel lua lua-devel pcre-devel -y
yum install libmodsecurity -y

cd /usr/src/
git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity
cd ModSecurity/
git submodule init
git submodule update
./build.sh
./configure
make && make install

##Modsecurity sera instalado en /usr/local/modsecurity
##compilar e instalr nginx modsecurity
cd /usr/src/
git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git

##revisar que version de nginx le toca para saber que version instalar 
nginx -V  ##no mostro nada

##descargamos nginx
cd /usr/src
wget http://nginx.org/download/nginx-1.19.1.tar.gz
tar -xf nginx-1.*.tar.gz
cd nginx-1.*/

##segunda propuesta
./configure --user=nginx --group=nginx --sbin-path=/usr/sbin/nginx --conf-path=/etc/nginx/nginx.conf --pid-path=/var/run/nginx.pid --lock-path=/var/run/nginx.lock --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --add-dynamic-module=../ModSecurity-nginx

make
make modules
make install

cp /usr/src/ModSecurity/modsecurity.conf-recommended /etc/nginx/modsecurity.conf
cp /usr/src/ModSecurity/unicode.mapping /etc/nginx/unicode.mapping

cd /usr/src/
sed -i "s/SecRuleEngine DetectionOnly/SecRuleEngine On/" /etc/nginx/modsecurity.conf

##agregar 4 lineas vacias o desplazar 4 lineas abajo
sed -i -e '1i\  \' /etc/nginx/nginx.conf
sed -i -e '1i\  \' /etc/nginx/nginx.conf
sed -i -e '1i\  \' /etc/nginx/nginx.conf
sed -i -e '1i\  \' /etc/nginx/nginx.conf
sed -i "1c\error_log  \/var\/log\/nginx/error.log;" /etc/nginx/nginx.conf
sed -i "2c\error_log  \/var\/log\/error.log;" /etc/nginx/nginx.conf
sed -i "3c\pid \/var\/run\/nginx.pid;" /etc/nginx/nginx.conf
sed -i "4c\load_module modules\/ngx_http_modsecurity_module.so;" /etc/nginx/nginx.conf

##desplazar dos lineas abajo desde la posicion 36
sed -i -e '44i\  \' /etc/nginx/nginx.conf
sed -i -e '44i\  \' /etc/nginx/nginx.conf
sed -i '44c\add_header X-XSS-Protection "1; mode=block";' /etc/nginx/nginx.conf
sed -i '45c\add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload";' /etc/nginx/nginx.conf

##despalzar doslienas abajo desde la posicion 
sed -i -e '50i\  \' /etc/nginx/nginx.conf
sed -i -e '50i\  \' /etc/nginx/nginx.conf
sed -i "50c\modsecurity on;" /etc/nginx/nginx.conf
sed -i "51c\modsecurity_rules_file \/etc\/nginx\/modsec_includes.conf;" /etc/nginx/nginx.conf

##descargar reglas owasp
cd /etc/nginx/
wget https://github.com/SpiderLabs/owasp-modsecurity-crs/archive/v3.2.0.zip
unzip v3.*.zip
mv owasp-modsecurity-crs-3.2.0 owasp-modsecurity-crs
cp -r owasp-modsecurity-crs/crs-setup.conf.example owasp-modsecurity-crs/crs-setup.conf

##relacionando reglas
cd /etc/nginx/
cat > modsec_includes.conf << 'EOF'
include modsecurity.conf
include /etc/nginx/owasp-modsecurity-crs/crs-setup.conf
include /etc/nginx/owasp-modsecurity-crs/rules/*.conf

##agregar tu regla custom aqui
SecRule REQUEST_URI "@beginsWith /rss/" "phase:1,t:none,pass,id:'26091902',nolog,ctl:ruleRemoveById=200002"
EOF

cd /etc/init.d/
cat > nginx << 'EOF'
#!/bin/sh
#
# nginx - this script starts and stops the nginx daemon
#
# chkconfig:   - 85 15
# description:  NGINX is an HTTP(S) server, HTTP(S) reverse \
#               proxy and IMAP/POP3 proxy server
# processname: nginx
# config:      /etc/nginx/nginx.conf
# config:      /etc/sysconfig/nginx
# pidfile:     /var/run/nginx.pid

# Source function library.
. /etc/rc.d/init.d/functions

# Source networking configuration.
. /etc/sysconfig/network

# Check that networking is up.
[ "$NETWORKING" = "no" ] && exit 0

nginx="/usr/sbin/nginx"
prog=$(basename $nginx)

NGINX_CONF_FILE="/etc/nginx/nginx.conf"

[ -f /etc/sysconfig/nginx ] && . /etc/sysconfig/nginx

lockfile=/var/lock/subsys/nginx

make_dirs() {
   # make required directories
   user=`$nginx -V 2>&1 | grep "configure arguments:.*--user=" | sed 's/[^*]*--user=\([^ ]*\).*/\1/g' -`
   if [ -n "$user" ]; then
      if [ -z "`grep $user /etc/passwd`" ]; then
         useradd -M -s /bin/nologin $user
      fi
      options=`$nginx -V 2>&1 | grep 'configure arguments:'`
      for opt in $options; do
          if [ `echo $opt | grep '.*-temp-path'` ]; then
              value=`echo $opt | cut -d "=" -f 2`
              if [ ! -d "$value" ]; then
                  # echo "creating" $value
                  mkdir -p $value && chown -R $user $value
              fi
          fi
       done
    fi
}

start() {
    [ -x $nginx ] || exit 5
    [ -f $NGINX_CONF_FILE ] || exit 6
    make_dirs
    echo -n $"Starting $prog: "
    daemon $nginx -c $NGINX_CONF_FILE
    retval=$?
    echo
    [ $retval -eq 0 ] && touch $lockfile
    return $retval
}

stop() {
    echo -n $"Stopping $prog: "
    killproc $prog -QUIT
    retval=$?
    echo
    [ $retval -eq 0 ] && rm -f $lockfile
    return $retval
}

restart() {
    configtest || return $?
    stop
    sleep 1
    start
}

reload() {
    configtest || return $?
    echo -n $"Reloading $prog: "
    killproc $nginx -HUP
    RETVAL=$?
    echo
}

force_reload() {
    restart
}

configtest() {
  $nginx -t -c $NGINX_CONF_FILE
}

rh_status() {
    status $prog
}

rh_status_q() {
    rh_status >/dev/null 2>&1
}

case "$1" in
    start)
        rh_status_q && exit 0
        $1
        ;;
    stop)
        rh_status_q || exit 0
        $1
        ;;
    restart|configtest)
        $1
        ;;
    reload)
        rh_status_q || exit 7
        $1
        ;;
    force-reload)
        force_reload
        ;;
    status)
        rh_status
        ;;
    condrestart|try-restart)
        rh_status_q || exit 0
            ;;
    *)
        echo $"Usage: $0 {start|stop|status|restart|condrestart|try-restart|reload|force-reload|configtest}"
        exit 2
esac
EOF

chmod 755 nginx

cd /lib/systemd/system/
cat > nginx.service << 'EOF'
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

useradd -r nginx

##iniciar nginx
systemctl enable nginx
systemctl start nginx
systemctl restart nginx
systemctl status nginx

