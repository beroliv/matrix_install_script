#!/bin/bash
#Install script for Synapse Matrix with letsencrypt ssl_certificates domain.com matrix.domain.com and element.domain.com
#forward your ports  443,80 to this server
#federation is on port 443
#Check https://github.com/vector-im/element-web/releases for newest version.
#Federation check after install https://federationtester.matrix.org

MRX_DOM="matrix.yourdomain.com" #Matrix domain
ELE_DOM="element.yourdomain.com" #webinterface
ELE_VER="v1.7.21" #check first on github
MRX_NME="yourdomain.com" #server_name

#Dont change anything from here

MRX_PKE=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

ELE_DBNAME="synapse_db"
ELE_DBUSER="synapse_user"

ELE_DBPASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

apt update && apt full-upgrade -y

apt install -y build-essential python3-certbot-nginx python3-dev libffi-dev sqlite3 python-pip python-setuptools libssl-dev python-virtualenv libjpeg-dev libxslt1-dev apt-transport-https software-properties-common net-tools nginx mc postgresql python3-psycopg2 curl

wget -qO - https://matrix.org/packages/debian/repo-key.asc | apt-key add -
add-apt-repository https://matrix.org/packages/debian/
apt update && apt install -y matrix-synapse
systemctl enable matrix-synapse

#netstat -tulpen


cat > /etc/nginx/sites-available/$MRX_NME <<EOF
# Virtual Host configuration for example.com

server {

       server_name $MRX_NME;

       root /var/www/$MRX_NME;
       index index.html;

       location / {
               try_files \$uri \$uri/ =404;
       }



}

EOF
ln -s /etc/nginx/sites-available/$MRX_NME /etc/nginx/sites-enabled/$MRX_NME

cat > /etc/nginx/sites-available/$MRX_DOM <<EOF
# Virtual Host configuration for matrix.example.com

server {

       server_name $MRX_DOM;

       root /var/www/$MRX_NME;
       index index.html;

       location / {
              proxy_pass http://localhost:8008;
       }

}

EOF
ln -s /etc/nginx/sites-available/$MRX_DOM /etc/nginx/sites-enabled/$MRX_DOM

cat > /etc/nginx/sites-available/$ELE_DOM <<EOF
# Virtual Host configuration for element.example.com

server {

       server_name $ELE_DOM;

       root /var/www/$ELE_DOM/element;
       index index.html;

       location / {
               try_files \$uri \$uri/ =404;
       }
  }

EOF
ln -s /etc/nginx/sites-available/$ELE_DOM /etc/nginx/sites-enabled/$ELE_DOM

echo Genearating well known file for federation

mkdir -p /var/www/$MRX_NME/.well-known/matrix
cat > /var/www/$MRX_NME/.well-known/matrix/server <<EOF
{ "m.server": "$MRX_DOM:443" }
EOF
echo enter your valid email adress for certbot generating letsencrypt ssl_certificates
echo
certbot --nginx -d $MRX_NME -d $ELE_DOM -d $MRX_DOM
systemctl restart nginx

mkdir /var/www/$ELE_DOM
cd /var/www/$ELE_DOM
wget https://github.com/vector-im/element-web/releases/download/$ELE_VER/element-$ELE_VER.tar.gz
tar -xzvf element-$ELE_VER.tar.gz
ln -s element-$ELE_VER element
chown www-data:www-data -R element
cp ./element/config.sample.json ./element/config.json
sed -i "s|https://matrix-client.matrix.org|https://$MRX_DOM|" ./element/config.json
sed -i "s|\"server_name\": \"matrix.org\"|\"server_name\": \"$MRX_NME\"|" ./element/config.json
echo Genearating Postgres database
su postgres <<EOF
psql -c "CREATE USER $ELE_DBUSER WITH PASSWORD '$ELE_DBPASS';"
psql -c "CREATE DATABASE $ELE_DBNAME ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' template=template0 OWNER $ELE_DBUSER;"
echo "Postgres User '$ELE_DBUSER' and database '$ELE_DBNAME' created."
EOF

cd /
sed -i "s|#registration_shared_secret: <PRIVATE STRING>|registration_shared_secret: \"$MRX_PKE\"|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|#public_baseurl: https://example.com/|public_baseurl: https://$MRX_DOM/|" /etc/matrix-synapse/homeserver.yaml #Loggin bug
sed -i "s|#enable_registration: false|enable_registration: true|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|name: sqlite3|name: psycopg2|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|database: /var/lib/matrix-synapse/homeserver.db|database: $ELE_DBNAME\n    user: $ELE_DBUSER\n    password: $ELE_DBPASS\n    host: 127.0.0.1\n    cp_min: 5\n    cp_max: 10|" /etc/matrix-synapse/homeserver.yaml

systemctl restart matrix-synapse
echo
echo
echo register new Matrix user!!
register_new_matrix_user -c /etc/matrix-synapse/homeserver.yaml http://127.0.0.1:8008

echo
echo Done!!
