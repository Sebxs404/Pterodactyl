#!/bin/bash
set -euo pipefail

GitHub_Account="https://raw.githubusercontent.com/Sebxs404/Pterodactyl/main/src"

blowfish_secret=""
FQDN=""
FQDN_Node="" 
MYSQL_PASSWORD=""
SSL_AVAILABLE=false
Node_SSL_AVAILABLE=false 
Pterodactyl_conf="pterodactyl-no_ssl.conf"
email=""
user_username=""
user_password=""
email_regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

print_error() {
    local COLOR_RED='\033[0;31m'
    local COLOR_NC='\033[0m'
    echo ""
    echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: $1"
    echo ""
}

print_success() {
    local COLOR_GREEN='\033[0;32m'
    local COLOR_NC='\033[0m'
    echo ""
    echo -e "* ${COLOR_GREEN}ÉXITO${COLOR_NC}: $1"
    echo ""
}

check_root() {
    if (( $EUID != 0 )); then
        print_error "Por favor, ejecuta este script como root."
        exit 1
    fi
}

check_ubuntu() {
    if [ -f "/etc/os-release" ]; then
        . /etc/os-release
        if [[ "$ID" = "ubuntu" ]]; then
            echo "Sistema operativo detectado: Ubuntu."
        else
            print_error "Este script está diseñado para funcionar solo en Ubuntu. Se ha detectado: $PRETTY_NAME."
            exit 1
        fi
    else
        print_error "No se pudo determinar el sistema operativo. Este script está diseñado para Ubuntu."
        exit 1
    fi
}

required_input() {
    local __resultvar=$1
    local result=''
    local prompt="$2"
    local error_msg="$3"
    local default_val="${4:-}" 

    while [ -z "$result" ]; do
        echo -n "* ${prompt}"
        read -r result

        if [ -z "$result" ]; then
            if [ -n "$default_val" ]; then
                result="$default_val"
            else
                print_error "$error_msg"
            fi
        fi
    done
    eval "$__resultvar="'$result'""
}

valid_email() {
    [[ $1 =~ ${email_regex} ]]
}

email_input() {
    local __resultvar=$1
    local result=''
    local prompt="$2"
    local error_msg="$3"

    while ! valid_email "$result"; do
        echo -n "* ${prompt}"
        read -r result

        valid_email "$result" || print_error "$error_msg"
    done
    eval "$__resultvar="'$result'""
}

password_input() {
    local __resultvar=$1
    local result=''
    local prompt="$2"
    local error_msg="$3"
    local default_val="${4:-}"

    while [ -z "$result" ]; do
        echo -n "* ${prompt}"

        while IFS= read -r -s -n1 char; do
            [[ -z $char ]] && {
                printf '\n'
                break
            }
            if [[ $char == $'\x7f' ]]; then 
                if [ -n "$result" ]; then
                    result=${result%?}
                    printf '\b \b'
                fi
            else
                result+=$char
                printf '*'
            fi
        done
        [ -z "$result" ] && [ -n "$default_val" ] && result="$default_val"
        [ -z "$result" ] && print_error "$error_msg"
    done
    eval "$__resultvar="'$result'""
}

invalid_ip() {
    ip route get "$1" >/dev/null 2>&1
    echo $?
}

check_FQDN_SSL() {
    if [[ $(invalid_ip "$FQDN") == 0 && "$FQDN" != 'localhost' ]]; then 
        SSL_AVAILABLE=true
    else
        SSL_AVAILABLE=false
    fi
}

check_FQDN_Node_SSL() {
    if [[ $(invalid_ip "$FQDN_Node") == 0 && "$FQDN_Node" != 'localhost' ]]; then
        Node_SSL_AVAILABLE=true
    else
        Node_SSL_AVAILABLE=false
    fi
}

installPhpMyAdmin() {
    echo "Iniciando instalación de phpMyAdmin..."
    mkdir -p /var/www/pterodactyl/public/phpmyadmin || print_error "Error al crear directorio para phpMyAdmin."

    cd /var/www/pterodactyl/public/phpmyadmin || print_error "Error al cambiar de directorio a /var/www/pterodactyl/public/phpmyadmin."

    echo "Descargando phpMyAdmin..."
    wget -q --show-progress https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz || print_error "Error al descargar phpMyAdmin."
    tar xvzf phpMyAdmin-latest-all-languages.tar.gz || print_error "Error al extraer phpMyAdmin."

    mv phpMyAdmin-*-all-languages/* . || print_error "Error al mover los archivos de phpMyAdmin."

    rm -rf phpMyAdmin-*-all-languages || print_error "Error al limpiar archivos temporales de phpMyAdmin."
    rm -f phpMyAdmin-latest-all-languages.tar.gz || print_error "Error al eliminar archivo tar.gz de phpMyAdmin."
    rm -f config.sample.inc.php 

    mkdir -p /var/www/pterodactyl/public/phpmyadmin/tmp || print_error "Error al crear directorio tmp de phpMyAdmin."
    chmod -R 755 /var/www/pterodactyl/public/phpmyadmin/tmp || print_error "Error al establecer permisos para tmp de phpMyAdmin."
    chown -R www-data:www-data /var/www/pterodactyl/public/phpmyadmin/tmp || print_error "Error al cambiar propietario de tmp de phpMyAdmin."

    echo "Descargando configuración de phpMyAdmin..."
    curl -o config.inc.php "$GitHub_Account/config.inc.php" || print_error "Error al descargar config.inc.php de phpMyAdmin."
    sed -i -e "s@<blowfish_secret>@${blowfish_secret}@g" config.inc.php || print_error "Error al configurar blowfish secret de phpMyAdmin."

    rm -rf /var/www/pterodactyl/public/phpmyadmin/setup 

    print_success "phpMyAdmin instalado correctamente."
    cd || print_error "Error al volver al directorio home."
}

installPanel() {
    echo "Iniciando instalación de Pterodactyl Panel..."

    echo "Realizando limpieza de configuraciones antiguas..."
    for f in "/etc/apt/sources.list.d/mariadb.list" "/etc/apt/sources.list.d/mariadb.list.old_"*; do
        if [ -f "$f" ]; then rm "$f" || print_error "Error al eliminar $f"; fi
    done
    
    for conf_file in "/etc/mysql/my.cnf" "/etc/mysql/mariadb.conf.d/50-server.cnf"; do
        if [ -f "$conf_file" ]; then
            mv "$conf_file" "${conf_file}.bak.$(date +%Y%m%d%H%M%S)" || print_error "Error al respaldar $conf_file."
        fi
    done

    if [ -f "/etc/systemd/system/pteroq.service" ]; then rm /etc/systemd/system/pteroq.service || print_error "Error al eliminar pteroq.service."; fi
    if [ -f "/etc/nginx/sites-enabled/default" ]; then rm /etc/nginx/sites-enabled/default || print_error "Error al eliminar la configuración default de Nginx."; fi
    if [ -f "/etc/nginx/sites-enabled/pterodactyl.conf" ]; then rm /etc/nginx/sites-enabled/pterodactyl.conf || print_error "Error al eliminar pterodactyl.conf de Nginx."; fi

    echo "Actualizando paquetes e instalando dependencias básicas..."
    apt update || print_error "Error al actualizar paquetes."
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg || print_error "Error al instalar dependencias básicas."

    echo "Añadiendo repositorio de PHP 8.3..."
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php || print_error "Error al añadir repositorio de PHP."

    echo "Añadiendo repositorio de Redis..."
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg || print_error "Error al añadir clave GPG de Redis."
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list > /dev/null || print_error "Error al añadir repositorio de Redis."
    
    echo "Actualizando índices de paquetes y instalando PHP, MariaDB, Nginx, Redis y Composer..."
    apt update || print_error "Error al actualizar paquetes después de añadir repositorios."
    apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server || print_error "Error al instalar paquetes principales."
    
    echo "Instalando Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer || print_error "Error al instalar Composer."

    echo "Descargando Pterodactyl Panel..."
    mkdir -p /var/www/pterodactyl || print_error "Error al crear el directorio de Pterodactyl."
    cd /var/www/pterodactyl || print_error "Error al cambiar de directorio a /var/www/pterodactyl."
    
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz || print_error "Error al descargar Pterodactyl Panel."
    tar -xzvf panel.tar.gz || print_error "Error al extraer Pterodactyl Panel."
    chmod -R 755 storage/* bootstrap/cache/ || print_error "Error al establecer permisos en storage/ y bootstrap/cache/."
    rm -f panel.tar.gz || print_error "Error al eliminar panel.tar.gz."

    echo "Configurando base de datos MariaDB..."
    echo ""
    read -p "ADVERTENCIA: ¿Deseas eliminar la base de datos 'panel' y los usuarios 'pterodactyl'/'pterodactyluser' existentes? (y/N): " confirm_db_wipe
    if [[ "$confirm_db_wipe" =~ ^[yY]$ ]]; then
        echo "Eliminando usuarios y base de datos existentes..."
        mysql -u root -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" || true 
        mysql -u root -e "DROP DATABASE IF EXISTS panel;" || true
        mysql -u root -e "DROP USER IF EXISTS 'pterodactyluser'@'127.0.0.1';" || true
        mysql -u root -e "DROP USER IF EXISTS 'pterodactyluser'@'%';" || true
    else
        echo "Omitiendo eliminación de base de datos y usuarios existentes. Asegúrate de que no haya conflictos."
    fi

    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';" || print_error "Error al crear usuario 'pterodactyl'."
    mysql -u root -e "CREATE DATABASE panel;" || print_error "Error al crear base de datos 'panel'."
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;" || print_error "Error al conceder privilegios a 'pterodactyl'."
    mysql -u root -e "CREATE USER 'pterodactyluser'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';" || print_error "Error al crear usuario 'pterodactyluser'@'127.0.0.1'."
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'127.0.0.1' WITH GRANT OPTION;" || print_error "Error al conceder privilegios a 'pterodactyluser'@'127.0.0.1'."
    mysql -u root -e "CREATE USER 'pterodactyluser'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';" || print_error "Error al crear usuario 'pterodactyluser'@'%'. Asegúrate de que el firewall permita la conexión remota si es necesario."
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'%' WITH GRANT OPTION;" || print_error "Error al conceder privilegios a 'pterodactyluser'@'%'."
    mysql -u root -e "FLUSH PRIVILEGES;" || print_error "Error al refrescar privilegios de MySQL."

    echo "Descargando configuraciones de MariaDB..."
    curl -o /etc/mysql/my.cnf "$GitHub_Account/my.cnf" || print_error "Error al descargar my.cnf."
    curl -o /etc/mysql/mariadb.conf.d/50-server.cnf "$GitHub_Account/50-server.cnf" || print_error "Error al descargar 50-server.cnf."

    echo "Reiniciando MariaDB..."
    systemctl restart mariadb || print_error "Error al reiniciar MariaDB."

    echo "Configurando Pterodactyl..."
    cp .env.example .env || print_error "Error al copiar .env.example."
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader || print_error "Error al ejecutar composer install."
    php artisan key:generate --force || print_error "Error al generar la clave de la aplicación."
        
    app_url="http://$FQDN"
    if [ "$SSL_AVAILABLE" == true ]; then
        app_url="https://$FQDN"
        Pterodactyl_conf="pterodactyl.conf"
        echo "Detectado FQDN válido para SSL. Instalando Certbot..."
        apt update || print_error "Error al actualizar paquetes para Certbot."
        apt -y install certbot python3-certbot-nginx || print_error "Error al instalar Certbot."
        echo "Obteniendo certificado SSL para $FQDN..."
        certbot certonly --nginx --non-interactive --agree-tos --email "$email" --redirect --no-eff-email -d "$FQDN" || print_error "Error al obtener certificado SSL con Certbot. Verifica tu FQDN y DNS."
    else
        echo "No se detectó un FQDN válido o se especificó localhost. Se usará HTTP."
    fi

    php artisan p:environment:setup \
        --author="sebasc@redfire-hosting.com" \
        --url="$app_url" \
        --timezone="America/New_York" \
        --cache="file" \
        --session="file" \
        --queue="redis" \
        --redis-host="localhost" \
        --redis-pass="null" \
        --redis-port="6379" \
        --settings-ui=true \
        --telemetry=true || print_error "Error al configurar el entorno de Pterodactyl."

    php artisan p:environment:database \
        --host="127.0.0.1" \
        --port="3306" \
        --database="panel" \
        --username="pterodactyl" \
        --password="${MYSQL_PASSWORD}" || print_error "Error al configurar la base de datos de Pterodactyl."

    php artisan migrate --seed --force || print_error "Error al ejecutar las migraciones de la base de datos."

    php artisan p:user:make \
        --email="$email" \
        --username="$user_username" \
        --name-first="$user_username" \
        --name-last="$user_username" \
        --password="$user_password" \
        --admin=1 || print_error "Error al crear el usuario administrador."

    echo "Estableciendo permisos de archivos para Pterodactyl..."
    chown -R www-data:www-data /var/www/pterodactyl/* || print_error "Error al establecer propietario de archivos de Pterodactyl."

    echo "Configurando Cronjob para Pterodactyl..."
    (crontab -l 2>/dev/null | grep -v 'schedule:run'; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab - || print_error "Error al configurar cronjob."

    echo "Configurando servicio Pteroq Queue Worker..."
    curl -o /etc/systemd/system/pteroq.service "$GitHub_Account/pteroq.service" || print_error "Error al descargar pteroq.service."
    systemctl daemon-reload || print_error "Error al recargar daemon de systemd."
    systemctl enable --now redis-server || print_error "Error al habilitar/iniciar redis-server."
    systemctl enable --now pteroq.service || print_error "Error al habilitar/iniciar pteroq.service."
    
    echo "Configurando Nginx para Pterodactyl..."
    curl -o /etc/nginx/sites-enabled/pterodactyl.conf "$GitHub_Account/$Pterodactyl_conf" || print_error "Error al descargar la configuración de Nginx."
    sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf || print_error "Error al configurar el dominio en Nginx."
    nginx -t || print_error "Error de sintaxis en la configuración de Nginx. Revisa /etc/nginx/sites-enabled/pterodactyl.conf"
    systemctl restart nginx || print_error "Error al reiniciar Nginx."

    print_success "Pterodactyl Panel instalado correctamente."
    cd || print_error "Error al volver al directorio home."
}

installWings() {
    echo "Iniciando instalación de Pterodactyl Wings..."
    
    echo "Realizando limpieza de configuraciones antiguas..."
    for f in "/etc/apt/sources.list.d/mariadb.list" "/etc/apt/sources.list.d/mariadb.list.old_"*; do
        if [ -f "$f" ]; then rm "$f" || print_error "Error al eliminar $f"; fi
    done
    if [ -f "/etc/default/grub" ]; then
        mv /etc/default/grub /etc/default/grub.bak.$(date +%Y%m%d%H%M%S) || print_error "Error al respaldar /etc/default/grub."
    fi
    for conf_file in "/etc/mysql/my.cnf" "/etc/mysql/mariadb.conf.d/50-server.cnf"; do
        if [ -f "$conf_file" ]; then
            mv "$conf_file" "${conf_file}.bak.$(date +%Y%m%d%H%M%S)" || print_error "Error al respaldar $conf_file."
        fi
    done
    if [ -f "/etc/systemd/system/wings.service" ]; then rm /etc/systemd/system/wings.service || print_error "Error al eliminar wings.service."; fi

    echo "Instalando Docker..."
    curl -fsSL https://get.docker.com/ | CHANNEL=stable bash || print_error "Error al instalar Docker."
    systemctl enable --now docker || print_error "Error al habilitar/iniciar Docker."

    echo "Configurando GRUB..."
    curl -o /etc/default/grub "$GitHub_Account/grub" || print_error "Error al descargar la configuración de GRUB."
    update-grub || print_error "Error al actualizar GRUB."
    
    echo "Descargando Pterodactyl Wings..."
    mkdir -p /etc/pterodactyl || print_error "Error al crear el directorio /etc/pterodactyl."
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")" || print_error "Error al descargar Wings."
    chmod u+x /usr/local/bin/wings || print_error "Error al dar permisos de ejecución a Wings."
    
    echo "Actualizando paquetes y añadiendo repositorio de MariaDB..."
    apt update || print_error "Error al actualizar paquetes."
    if ! curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash; then
        print_error "Error al añadir el repositorio de MariaDB. Verifica tu conexión o el comando."
        exit 1
    fi
    apt update || print_error "Error al actualizar paquetes después de añadir repositorio de MariaDB."
    apt -y install mariadb-server || print_error "Error al instalar mariadb-server."


    echo "Configurando usuario de MariaDB para Wings (acceso remoto)..."
    echo ""
    read -p "ADVERTENCIA: ¿Deseas eliminar el usuario 'pterodactyluser'@'%' existente si lo hubiera? (y/N): " confirm_user_wipe
    if [[ "$confirm_user_wipe" =~ ^[yY]$ ]]; then
        mysql -u root -e "DROP USER IF EXISTS 'pterodactyluser'@'%';" || true 
    else
        echo "Omitiendo eliminación del usuario existente. Asegúrate de que no haya conflictos."
    fi

    mysql -u root -e "CREATE USER 'pterodactyluser'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';" || print_error "Error al crear usuario 'pterodactyluser'@'%'."
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'%' WITH GRANT OPTION;" || print_error "Error al conceder privilegios a 'pterodactyluser'@'%'. Asegúrate de que el firewall permita la conexión remota si es necesario."
    mysql -u root -e "FLUSH PRIVILEGES;" || print_error "Error al refrescar privilegios de MySQL."

    echo "Descargando configuraciones de MariaDB..."
    curl -o /etc/mysql/my.cnf "$GitHub_Account/my.cnf" || print_error "Error al descargar my.cnf."
    curl -o /etc/mysql/mariadb.conf.d/50-server.cnf "$GitHub_Account/50-server.cnf" || print_error "Error al descargar 50-server.cnf."
    
    echo "Reiniciando MariaDB..."
    systemctl restart mariadb || print_error "Error al reiniciar MariaDB."

    if [ "$Node_SSL_AVAILABLE" == true ]; then
        echo "Detectado FQDN válido para SSL en el nodo. Instalando Certbot..."
        apt update || print_error "Error al actualizar paquetes para Certbot."
        apt -y install certbot python3-certbot-nginx || print_error "Error al instalar Certbot."
        echo "Obteniendo certificado SSL para $FQDN_Node..."
        certbot certonly --nginx --non-interactive --agree-tos --email "admin@example.com" --redirect --no-eff-email -d "$FQDN_Node" || print_error "Error al obtener certificado SSL con Certbot para el nodo. Verifica tu FQDN y DNS."
    else
        echo "No se detectó un FQDN válido para SSL en el nodo o se especificó localhost. Saltando configuración SSL para Wings."
    fi
    
    echo "Configurando servicio Wings..."
    curl -o /etc/systemd/system/wings.service "$GitHub_Account/wings.service" || print_error "Error al descargar wings.service."
    systemctl daemon-reload || print_error "Error al recargar daemon de systemd."
    systemctl enable --now wings || print_error "Error al habilitar/iniciar Wings."
    
    echo "Creando archivo de configuración de Wings (vacío, la configuración se realiza desde el Panel)..."
    touch /etc/pterodactyl/config.yml || print_error "Error al crear config.yml."
    chmod 644 /etc/pterodactyl/config.yml || print_error "Error al establecer permisos para config.yml."
    
    print_success "Pterodactyl Wings instalado correctamente."
    cd || print_error "Error al volver al directorio home."
}

updatePanel() {
    echo "Iniciando actualización de Pterodactyl Panel..."
    cd /var/www/pterodactyl || print_error "Error: El directorio del Panel no existe. ¿Está instalado?"

    echo "Poniendo el Panel en modo mantenimiento..."
    php artisan down || print_error "Error al poner el Panel en modo mantenimiento."

    echo "Descargando e instalando la última versión del Panel..."
    curl -L https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzv || print_error "Error al descargar/extraer la última versión del Panel."
    chmod -R 755 storage/* bootstrap/cache || print_error "Error al establecer permisos."
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader || print_error "Error al ejecutar composer install durante la actualización."
    php artisan optimize:clear || print_error "Error al limpiar la caché de optimización."
    php artisan migrate --seed --force || print_error "Error al ejecutar las migraciones de la base de datos."
    chown -R www-data:www-data /var/www/pterodactyl/* || print_error "Error al establecer propietario de archivos."
    php artisan queue:restart || print_error "Error al reiniciar la cola de workers."
    
    echo "Sacando el Panel del modo mantenimiento..."
    php artisan up || print_error "Error al sacar el Panel del modo mantenimiento."
    
    print_success "Pterodactyl Panel actualizado correctamente."
    cd || print_error "Error al volver al directorio home."
}

uninstallPhpMyAdmin() {
    echo "Desinstalando phpMyAdmin..."
    if [ -d "/var/www/pterodactyl/public/phpmyadmin" ]; then
        rm -rf /var/www/pterodactyl/public/phpmyadmin || print_error "Error al eliminar el directorio de phpMyAdmin."
        print_success "phpMyAdmin desinstalado correctamente."
    else
        print_error "phpMyAdmin no parece estar instalado en /var/www/pterodactyl/public/phpmyadmin."
    fi
}

summary() {
    clear
    echo ""
    echo -e "\033[1;94mCredenciales de la Base de Datos:\033[0m"
    echo -e "\033[1;92m*\033[0m Nombre de la Base de Datos: panel"
    echo -e "\033[1;92m*\033[0m IPv4: 127.0.0.1"
    echo -e "\033[1;92m*\033[0m Puerto: 3306"
    echo -e "\033[1;92m*\033[0m Usuario: pterodactyl, pterodactyluser"
    echo -e "\033[1;92m*\033[0m Contraseña: $MYSQL_PASSWORD"
    echo ""
    echo -e "\033[1;94mCredenciales del Panel:\033[0m"
    echo -e "\033[1;92m*\033[0m Email: $email"
    echo -e "\033[1;92m*\033[0m Usuario: $user_username"
    echo -e "\033[1;92m*\033[0m Contraseña: $user_password"
    echo ""
    echo -e "\033[1;96mDominio/IPv4 del Panel:\033[0m $FQDN"
    echo ""
    read -p "Presiona Enter para continuar..."
}

main_menu() {
    check_root
    check_ubuntu 
    clear
    echo ""
    echo "[0] Salir"
    echo "[1] Instalar Panel"
    echo "[2] Instalar Wings (Nodo)"
    echo "[3] Actualizar Panel"
    echo "[4] Instalar phpMyAdmin"
    echo "[5] Desinstalar phpMyAdmin"
    echo ""
    read -p "Por favor, ingresa un número: " choice
    echo ""

    case "$choice" in
        0)
            echo -e "\033[0;96m¡Hasta luego!\033[0m"
            ;;
        1)
            password_input MYSQL_PASSWORD "Proporciona la contraseña para la base de datos: " "La contraseña de MySQL no puede estar vacía."
            email_input email "Proporciona la dirección de correo electrónico para el panel: " "El correo electrónico no puede estar vacío o ser inválido."
            required_input user_username "Proporciona el nombre de usuario para el panel: " "El nombre de usuario no puede estar vacío."
            password_input user_password "Proporciona la contraseña para el panel: " "La contraseña del panel no puede estar vacía."

            while [ -z "$FQDN" ]; do
                echo -n "* Establece el FQDN de este panel (ej. panel.example.com | 0.0.0.0 si usas IP): "
                read -r FQDN
                [ -z "$FQDN" ] && print_error "El FQDN no puede estar vacío."
            done
            check_FQDN_SSL
            installPanel
            summary
            ;;
        2)
            password_input MYSQL_PASSWORD "Proporciona la contraseña para la base de datos (se usará para el usuario remoto del nodo): " "La contraseña de MySQL no puede estar vacía."

            while [ -z "$FQDN_Node" ]; do
                echo -n "* Establece el FQDN del nodo (ej. node.example.com | 0.0.0.0 si usas IP): "
                read -r FQDN_Node
                [ -z "$FQDN_Node" ] && print_error "El FQDN del nodo no puede estar vacío."
            done
            FQDN="$FQDN_Node" 
            check_FQDN_SSL 
            Node_SSL_AVAILABLE="$SSL_AVAILABLE" 
            FQDN="" 
            
            installWings
            clear
            print_success "Wings instalado correctamente."
            ;;
        3)
            updatePanel
            clear
            print_success "Panel actualizado correctamente."
            ;;
        4)
            required_input blowfish_secret "Proporciona el 'blowfish secret' para phpMyAdmin (una cadena aleatoria de 32 caracteres): " "El 'blowfish secret' no puede estar vacío."
            installPhpMyAdmin
            clear
            print_success "phpMyAdmin instalado correctamente."
            ;;
        5)
            uninstallPhpMyAdmin
            clear
            print_success "phpMyAdmin desinstalado correctamente."
            ;;
        *)
            print_error "Opción inválida. Por favor, ingresa un número del 0 al 5."
            ;;
    esac
    echo ""
}

main_menu
