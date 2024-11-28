#!/bin/bash

set -e

# Función para mostrar un mensaje y salir en caso de error
function error_exit {
  echo "$1" >&2
  exit 1
}

# Preguntar información básica al usuario
read -p "Introduce el nombre de la base de datos (default: wordpress): " db_name
read -p "Introduce el nombre del usuario de la base de datos (default: wordpressuser): " db_user
read -p "Introduce la contraseña del usuario de la base de datos: " db_password
read -p "Introduce el dominio (o presiona ENTER para usar la IP del servidor): " server_domain

db_name=${db_name:-wordpress}
db_user=${db_user:-wordpressuser}

# Actualizar el sistema
sudo apt update && sudo apt upgrade -y || error_exit "Error al actualizar el sistema."

# Instalar Apache
sudo apt install apache2 -y || error_exit "Error al instalar Apache."
sudo systemctl enable apache2
sudo systemctl start apache2

# Instalar MySQL
sudo apt install mysql-server -y || error_exit "Error al instalar MySQL."
sudo mysql_secure_installation || error_exit "Error al asegurar MySQL."

# Crear base de datos y usuario
sudo mysql -e "CREATE DATABASE $db_name;" || error_exit "Error al crear la base de datos."
sudo mysql -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_password';" || error_exit "Error al crear el usuario de la base de datos."
sudo mysql -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';" || error_exit "Error al asignar privilegios al usuario."
sudo mysql -e "FLUSH PRIVILEGES;" || error_exit "Error al aplicar los privilegios."

# Instalar PHP
sudo apt install php php-mysql libapache2-mod-php -y || error_exit "Error al instalar PHP."
sudo systemctl restart apache2

# Descargar e instalar WordPress
cd /var/www/html || error_exit "Error al cambiar al directorio de Apache."
sudo rm -rf index.html
sudo wget https://wordpress.org/latest.tar.gz || error_exit "Error al descargar WordPress."
sudo tar -xzvf latest.tar.gz || error_exit "Error al extraer WordPress."
sudo mv wordpress/* .
sudo rm -rf wordpress latest.tar.gz

# Configurar permisos
sudo chown -R www-data:www-data /var/www/html || error_exit "Error al asignar permisos."
sudo chmod -R 755 /var/www/html

# Configurar WordPress
sudo cp wp-config-sample.php wp-config.php || error_exit "Error al copiar el archivo de configuración."
sudo sed -i "s/database_name_here/$db_name/" wp-config.php
sudo sed -i "s/username_here/$db_user/" wp-config.php
sudo sed -i "s/password_here/$db_password/" wp-config.php

# Configurar Apache
apache_conf="<VirtualHost *:80>
    ServerAdmin admin@$server_domain
    DocumentRoot /var/www/html
    ServerName $server_domain
    <Directory /var/www/html>
        AllowOverride All
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>"

echo "$apache_conf" | sudo tee /etc/apache2/sites-available/wordpress.conf > /dev/null || error_exit "Error al configurar Apache."

sudo a2ensite wordpress.conf || error_exit "Error al habilitar el sitio de Apache."
sudo a2enmod rewrite || error_exit "Error al habilitar mod_rewrite."
sudo systemctl restart apache2

# Instalar SSL con Let's Encrypt (opcional)
read -p "¿Quieres instalar un certificado SSL con Let's Encrypt? (y/n): " install_ssl
if [ "$install_ssl" == "y" ]; then
  sudo apt install certbot python3-certbot-apache -y || error_exit "Error al instalar Certbot."
  sudo certbot --apache || error_exit "Error al configurar SSL."
fi

# Mensaje final
if [ -z "$server_domain" ]; then
  echo "Instalación completa. Accede a WordPress en: http://$(curl -s ifconfig.me)"
else
  echo "Instalación completa. Accede a WordPress en: http://$server_domain"
fi
