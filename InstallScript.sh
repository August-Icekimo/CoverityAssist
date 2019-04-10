#!/bin/bash
cat  << ANNOUNCEMENT
This Script Will Help you complete Basic Configure Over RHEL 7.1
Before that, You shoud do the follow things:
1. Make sure you subscribe RHN is working, and network too.

You Must Run This As Root Priveledge, due to SSL Certificate is root previledge.

This Script is Created By DTC Consult, Partner of Coverity(Company of Synopsis).
ANNOUNCEMENT
#CHINESENOTE 作為控制憑證與私鑰的路徑全域變數 #
CERTIFICATE=`pwd`/server.crt
PRIVATEKEY=`pwd`/server.key
read -p "Please enter thix machine FQDN" SERVER_FQDN
[ X = X"SERVER_FQDN" ] && SERVER_FQDN=`hostname`

#CHINESENOTE 設定目錄的SE屬性 #
function setSELinux()
{
yum -y install setools-console
sed -i 's/SELINUX=enforcing/#SELINUX=enforcing\nSELINUX=disabled/g' /etc/sysconfig/selinux
}
# Install ORACLE JAVA /SUN JAVA
function installJAVA()
{
subscription-manager repos --enable rhel-7-server-thirdparty-oracle-java-rpms
yum -y install java-1.6.0-sun-devel.i686
yum -y install java-1.7.0-oracle-devel.i686
yum -y install java-1.8.0-oracle-devel.i686
cat << JAVANOTE
Jenkins will swith JDK version by case. But if you need to chanege in the shell, do this:

  alternatives --config java
  alternatives --config javac

 These command will Swith java you want to use.
 You MUST take JDK 1.6 above to do JAVA CERTIFICATE "KeyTool".
JAVANOTE
echo "Current JAVA Version"
java -version 
echo "Current JAVA Compiler Version"
javac -version
# Check JAVA Keytool is in path
which keytool
if [ $? = 1 ] ;then 
echo "[Note]You Need To Reset JDK for JAVA Key Tool."
#CHINESENOTE 詢問需要切換JDK#
bash -i -c "alternatives --config java"
bash -i -c "alternatives --config javac"
fi
}
# Install GNU C
function installGNUC()
{
yum -y install gcc.x86_64
}
# Install Some Basic Network Tools
function installWget()
{
yum -y install wget
#CHINESENOTE註解掉可以多安裝一些慣用的網路命令工具
# unmark if you want netstat/ipconfig commands.
# yum -y install net-tools
}
#CHINESENOTE 準備SSL憑證要安裝的位置
function ReadySSLCert()
{
# SET a folder to place all SSL CERTIFICATE
read -p "Enter where you plan to put SSL CERTIFICATE , blank for /etc/ssl/coverity: " CERTPATH
if [ X = X"$CERTPATH"] ;then 
 CERTPATH=/etc/ssl/coverity
fi
[ -d $CERTPATH ] && echo $CERTPATH || mkdir -p $CERTPATH
if [ $? = 1 ]; then 
echo "Creat Folder Error, You can do it on your own now, Press Ctrl D to return"
bash -i
fi
#CHINESENOTE 蒐集確認SSL憑證可以讀取#
#CHINESENOTE 預設Server.crt(PEM)與安裝腳本同一目錄

until [-r $CERTIFICATE]
do
 read -p "Enter your SSL CERTIFICATE filename(FullPATH if different $CERTIFICATE): " CERTIFICATE
 echo $CERTIFICATE
done
mv $CERTIFICATE $CERTPATH/server.crt
#CHINESENOTE 預設Server.key與安裝腳本同一目錄

until [-r $PRIVATEKEY]
do
 read -p "Enter your SSL Private filename(FullPATH if different $PRIVATEKEY): " PRIVATEKEY
 echo $PRIVATEKEY
done
mv ./$PRIVATEKEY $CERTPATH/server.key
#CHINESENOTE 切換目錄做JAVA KEY STORE#
pushd $CERTPATH
#CHINESENOTE 將PEM格式轉為DER格式#
openssl x509 -outform der -in $CERTIFICATE -out $CERTPATH/server.der
#CHINESENOTE 修改參數作為後續安裝時使用#
$CERTIFICATE=$CERTPATH/server.crt #Global
$PRIVATEKEY=$CERTPATH/server.key #Global
popd 
}
#CHINESENOTE 安裝JENKINS 穩定版#
function installJENKINS()
{ 
# Install Jenkins Stable Version 
wget -O /etc/yum.repos.d/jenkins.repo http://pkg.jenkins-ci.org/redhat-stable/jenkins.repo
rpm --import http://pkg.jenkins-ci.org/redhat-stable/jenkins-ci.org.key
yum -y install jenkins
# Move Jenkins binary files location.
  if [-d /var/lib/jenkins] ;then
  mv /var/lib/jenkins /opt/
  ln -s /var/lib/jenkins /opt/jenkins
  fi
#Configure the jenkins 
JENKINSCONF=/etc/sysconfig/jenkins # RHEL 
# JENKINSCONF=/etc/default/jenkins # Debian
sed -i 's/JENKINS_PORT="8080"/JENKINS_PORT="8088"/g' $JENKINSCONF
sed -i 's/JENKINS_LISTEN_ADDRESS=""/JENKINS_LISTEN_ADDRESS="127.0.0.1"/g' $JENKINSCONF
  if [[-f /etc/redhat-release]];then 
  # cat /etc/redhat-release
  cd /etc/sysconfig
  mv $JENKINSCONF $JENKINSCONF.sample # The Backup file
   grep -v ^#  $JENKINSCONF.sample | sed -e '/^$/d' | sed -e '/^JENKINS_ARGS.*/d' > $JENKINSCONF
   #gzip $JENKINSCONF.sample #Cleanup
   
cat >> $JENKINSCONF << JENKINSCONFIG
PREFIX=jenkins
HTTPS_PORT="8843"
SERVER_CRT=$CERTIFICATE
SERVER_KEY=$PRIVATEKEY
JENKINS_ARGS="--httpPort=\$JENKINS_PORT --httpListenAddress=\$JENKINS_HTTP_HOST --ajp13Port=\$AJP_PORT --httpsPort=\$HTTPS_PORT --httpsCertificate=\$SERVER_CRT --httpsPrivateKey=\$SERVER_KEY --prefix=/\$PREFIX "
JENKINSCONFIG
  fi
# Start Jenkins Service 
service jenkins start  
chkconfig jenkins on
}
#CHINESENOTE 開始安裝NGINX#
function installNGINX()
{  
# Install NGINX 
cat > /etc/yum.repos.d/nginx.repo << NGINXREPO
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/rhel/7/\$basearch/
gpgcheck=0
enabled=1
NGINXREPO
yum -y update
yum -y install nginx
#CHINESENOTE 複製對應的轉址設定#
pushd /etc/nginx
tar czvf conf.depose.tgz ./conf.d
rm -rf conf.d
mkdir -p /etc/nginx/sites-enabled
mkdir -p /etc/nginx/sites-available
sed -i 's/\/etc\/nginx\/conf.d\/\*.conf/\/etc\/nginx\/sites-enabled\/\*/g' nginx.conf


if [ -f ./nginx_int ]; then
cat > /etc/nginx/sites-available/nginx_int << INTERGRATION_CONF
upstream coverity_server {
    server localhost:8080 fail_timeout=0;
}
upstream jenkinsapp_server {
    server localhost:443 fail_timeout=0;
}
server {
    listen 80;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443;
    server_name $SERVER_FQDN;
    ssl_certificate           $CERTIFICATE;
    ssl_certificate_key       $PRIVATEKRY;
    ssl on;
    ssl_session_cache  builtin:1000  shared:SSL:10m;
    ssl_protocols  TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers 'AES128+EECDH:AES128+EDH:!aNULL';
    ssl_prefer_server_ciphers on;
	ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.4.4 8.8.8.8 valid=300s;
    resolver_timeout 10s;
	ssl_session_cache shared:SSL:10m;
	add_header Strict-Transport-Security max-age=63072000;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
	access_log  /var/log/nginx/jenkins.access.log;
	location / {
	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	proxy_set_header Host \$http_host;
	proxy_redirect off;
        if (!-f \$request_filename) {
		proxy_pass http://coverity_server;
		break;
    }
  }
	location ^~ /jenkins/ {
	proxy_set_header        Host \$host;
	proxy_set_header        X-Real-IP \$remote_addr;
	proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
	proxy_set_header        X-Forwarded-Proto \$scheme;
	proxy_ssl_session_reuse off;

      # Fix the “It appears that your reverse proxy set up is broken" error.
      proxy_pass          https://localhost:8843;
      proxy_read_timeout  90;
      proxy_redirect      https://localhost:8843/jenkins  https://$SERVER_FQDN/jenkins;
    }
  }

INTERGRATION_CONF
else 
  cp ./jenkins /etc/nginx/sites-available/nginx_int
fi
ln -s /etc/nginx/sites-available/nginx_int /etc/nginx/sites-enble/nginx_int
popd
popd
#CHINESENOTE 測試與重起服務
nginx -t 
if [ $? = 1 ]; then 
echo "NGINX Need Manual Edit"
else
service nginx restart
fi
}
# Install Apache Maven 
function installMVN()
{
wget http://apache.stu.edu.tw/maven/maven-3/3.3.3/binaries/apache-maven-3.3.3-bin.tar.gz
tar -zxvf apache-maven-3.3.3-bin.tar.gz -C /opt/
# Create MAVEN Environment Script 
cat << MVNSH > /etc/profile.d/maven.sh
export M2_HOME=/opt/apache-maven-3.3.3
export M2=\$M2_HOME/bin
PATH=\$M2:$PATH
MVNSH
}
# Install Apache ANT
function installANT()
{
wget http://apache.stu.edu.tw//ant/binaries/apache-ant-1.9.5-bin.tar.gz
tar -zxvf apache-ant-1.9.5-bin.tar.gz -C /opt/
# Install legency Apache ANT
antversion=1.6.0
until [ X = X"$antversion" ]
do 
 read -p "Enter Version like 1.6.1" antversion
 wget http://archive.apache.org/dist/ant/binaries/apache-ant-$antversion-bin.tar.gz
 tar -zxvf apache-ant-$antversion-bin.tar.gz -C /opt/
done
# Create ANT Environment Script 
cat << ANTSH > /etc/profile.d/ant.sh
export ANT_HOME=/opt/apache-ant-1.9.5
ANTPATH=$M2_HOME/bin
PATH=$ANTPATH:$PATH
ANTSH
}
# Install Coverity Analyse
function installCOVANA()
{
COV_ANA_ORDER_URL="https://www.dropbox.com/s/27ascktphelfp99/cov-analysis-linux64-7.6.1.sh?dl=0"
if [ -f cov-analysis-linux64-7.6.1.sh ];then
wget $COV_ANA_ORDER_URL
mv cov-analysis-linux64-7.6.1.sh{*,}
fi

read -p "Enter Coverity Analysis Install Path, Default /opt/cov-analysis :" COV_ANA_INSTALL
[ X = X"$COV_ANA_INSTALL" ] && COV_ANA_INSTALL=/opt/cov-analysis 
[ -d $COV_ANA_INSTALL ] && echo $COV_ANA_INSTALL || mkdir -p $COV_ANA_INSTALL
pushd $COV_ANA_INSTALL
touch license.dat
#Silence install
cat << INSTALLCOVANA > install-Analysis.sh
#!/bin/sh
./cov-analysis-linux64-7.6.1.sh -q -dir "$HOME/cov-analysis-7.6.1" -Vlicense.dat=$HOME/license.dat -Vlicense.region=2 -Vcomponent.sdk=true -Vcomponent.aa=true
INSTALLCOVANA
chmod +x install-Analysis.sh
mkdir -p $HOME\InstallSource
mv cov-analysis-linux64-7.6.1.sh $HOME\InstallSource\
#popd
}
# Install Coverity Platform
function installCOVPLT()
{
COV_PLF_ORDER_URL="https://www.dropbox.com/s/db5qmbpjg9t4wh9/cov-platform-linux64-7.6.1.sh?dl=0"
if [ -f cov-platform-linux64-7.6.1.sh ];then
wget $COV_PLF_ORDER_URL
mv cov-platform-linux64-7.6.1.sh{*,}
fi
#Silence install
read -p "Enter Coverity Analysis Install Path, Default /opt/cov-analysis :" COV_PLF_INSTALL
[ X = X"$COV_PLF_INSTALL" ] && COV_PLF_INSTALL=/opt/cov-platform
[ -d $COV_PLF_INSTALL ] && echo $COV_PLF_INSTALL || mkdir -p $COV_PLF_INSTALL
pushd $COV_PLF_INSTALL
touch license.dat
cat << INSTALLCOVPLF > install-Platform.sh
#!/bin/sh
./cov-platform-linux64-7.6.1.sh -q -dir "$HOME/cov-platform-7.6.1" -Vadmin.password=1qaz@WSX  -Vlicense.region=2 -Vlicense.agreement=i.agree.to.the.license -Vlicense.dat=$HOME/license.dat -Vdb.type=embedded -Vhostname=$SERVER_FQDN -Vhttp.port=8080 -Vaccept.https=true -Vhttps.port=8443 -Vcommit.port=9090 -Vcontrol.port=8005 -Vdb.embedded.port=5432 -Vinternal.db.embedded.settings=Medium -Vs13n.enable=true -db.dir="$HOME/cov-platform-7.6.1/database"
INSTALLCOVPLF
chmod +x install-Platform.sh
mv cov-platform-linux64-7.6.1.sh $HOME\InstallSource\
}
function setCoveritySSL()
{
#CHINESENOTE 更換原廠的SSL憑證，非必要，因為NGINX已經包裝銜接OK
pushd $COV_PLF_INSTALL/server/base/conf
echo "commit.encryption=preferred" >> $COV_PLF_INSTALL/config/cim.properties

#CHINESENOTE 需要keystore密碼
read -p "Enter your JKS Password: " STOREPASSWD

JKS_PATH=/keystore.jks
#  -import -alias tomcat -keystore $JKS_PATH -file $CERTPATH/server.der --storepass $STOREPASSWD
# echo "Lets see what is in the Java key store. "
# keytool -list -keystore $JKS_PATH --storepass $STOREPASSWD
openssl pkcs12 -export -in ssl.crt -inkey server.key -out keystore.p12 -name tomcat -CAfile ssl-lab.crt -caname root

keytool -importkeystore -deststorepass changeit -destkeypass changeit -destkeystore keystore.jks -srckeystore keystore.p12 -srcstoretype PKCS12 -srcstorepass changeit -alias tomcat

#CHINESENOTE 修改Coverity設定檔#
sed -i 's/sslEnabledProtocols/sslProtocol="TLS" sslEnabledProtocols/g' /server/base/conf/server.xml

cat > /etc/systemd/system/coverity-connect.service <<COVERITY-CONNECT.SERVICE
[Unit]
Description=Coverity Connect Service
Wants=network-online.target
After=network.target

[Service]
Type=forking
#PIDFILE=/var/run/coverity-connect.pid
#GuessMainPID=yes
User=peter
ExecStart=/opt/coverity/platform/bin/cov-start-im
ExecStop=/opt/coverity/platform/bin/cov-stop-im

[Install]
Alias=cov-connect
WantedBy=multi-user.target
COVERITY-CONNECT.SERVICE
}

installJAVA
installGNUC
installMVN
installANT

installWget
installCOVANA
installCOVPLT

ReadySSLCert
installJENKINS
installNGIN

setSELinux
