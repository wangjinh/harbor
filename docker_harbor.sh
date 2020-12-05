#!/bin/bash
# Don't forget the beginner's mind
# author wangjinh

yum install wget net-tools lrzsz git gcc gcc-c++ ntp -y
hostnamectl set-hostname harbor2

IP=`ifconfig ens192 | awk  -F ' ' 'NR==2{print $2}'`

cat << EOF > /tmp/export.sh
export IP=${IP}
EOF

#dependment environment
ntpdate cn.pool.ntp.org
setenforce 0
sed -i s/SELINUX=enforcing/SELINUX=disabled/ /etc/selinux/config
systemctl stop firewalld
systemctl disable firewalld

#configure ssh
sed -i "s/#UseDNS yes/UseDNS no/g" /etc/ssh/sshd_config
sed -i "s/GSSAPIAuthentication yes/GSSAPIAuthentication no/g" /etc/ssh/sshd_config
#在有crond任务时，触发systemd-logind回收不及时的bug
systemctl stop systemd-logind.service
systemctl restart sshd

cat > /etc/yum.repos.d/gitlab-ce.repo << 'EOF'
[gitlab-ce]
name=Gitlab CE Repository
baseurl=https://mirrors.tuna.tsinghua.edu.cn/gitlab-ce/yum/el$releasever/
gpgcheck=0
enabled=1
EOF

wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
sleep 5
wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo


if [ -f /usr/lib/systemd/system/docker.service ];then
	echo "docker-ce is installed"
else
	echo "docker-ce is not found"
	# step 1: 安装必要的一些系统工具
	yum install -y yum-utils device-mapper-persistent-data lvm2
	sleep 3
	# Step 2: 添加软件源信息
	yum-config-manager --add-repo  https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo 
	sleep 3
	##sudo yum-config-manager --add-repo https://selinux.cn/docker-ce.repo
	# Step 3: 更新并安装 Docker-CE
	yum makecache fast
	yum -y install docker-ce
	sleep 3
	echo ">>> startup docker service"
	systemctl start docker 
	systemctl enable docker 
	systemctl status docker
	echo ">>> docker version"
	docker version
fi

#create docker source acceleration dirctory
mkdir -p /etc/docker 
cat << EOF > /etc/docker/daemon.json
{
  "registry-mirrors": ["https://v5d7kh0f.mirror.aliyuncs.com"]
}
EOF

# installation docker-compose package
docker-compose version
if [ $? -eq 0 ];then
	echo "docker-compose is installed."
else
	echo " the docker-compose is not found"
    rpm -ivh http://mirrors.aliyun.com/epel/7/x86_64/Packages/e/epel-release-7-11.noarch.rpm
    yum -y install certbot libevent-devel gcc libffi-devel python-devel openssl-devel python-pip
    pip -v
    pip install --upgrade pip
	pip install -i https://pypi.tuna.tsinghua.edu.cn/simple -U docker-compose
	sleep 3
    pip install docker-compose --ignore-installed requests
	echo "docker-compose is install successfully"
	echo ">>> docker-compose version"
	docker-compose version
fi

# downloading harbor packages

echo ">>> Please select the harbor of major version" 

select MAJOR_VERSION in 1.8.0 1.9.0; do
	echo "you choice is the harbor of major version number ${MAJOR_VERSION}"
if [ ${MAJOR_VERSION} = 1.8.0 ]; then

	echo "Please choice the harbor of minor version number you installed ?" 

	select MINOR_VERSION in 1.8.0 1.8.1 1.8.2 1.8.3 1.8.4; do
	    echo "you choice is the minor version number ${MINOR_VERSION}"
		if [ ! -f harbor-offline-installer-v${MINOR_VERSION}.tgz ]; then
			echo "harbor-offline-installer-v${MINOR_VERSION}.tgz is no found. is downloading..."
			wget -c https://storage.googleapis.com/harbor-releases/release-${MAJOR_VERSION}/harbor-offline-installer-v${MINOR_VERSION}.tgz
			sleep 3
			tar -xzf harbor-offline-installer-v${MINOR_VERSION}.tgz -C /usr/local/
		else 
			echo "harbor-offline-installer-v${MINOR_VERSION}.tgz is exist. is unpackaging..."
			tar -xzf harbor-offline-installer-v${MINOR_VERSION}.tgz -C /usr/local/
		fi
		break
	done
	echo $?

else
	select MINOR_VERSION in 1.9.0 1.9.1; do
	    echo "you choice is the minor version number ${MINOR_VERSION}"
		if [ ! -f harbor-offline-installer-v${MINOR_VERSION}.tgz ]; then
			echo "harbor-offline-installer-v${MINOR_VERSION}.tgz is no found. is downloading..."
			wget -c https://storage.googleapis.com/harbor-releases/release-${MAJOR_VERSION}/harbor-offline-installer-v${MINOR_VERSION}.tgz
			sleep 3
			tar -xzf harbor-offline-installer-v${MINOR_VERSION}.tgz -C /usr/local/
		else 
			echo "harbor-offline-installer-v${MINOR_VERSION}.tgz is exist. is unpackaging..."
			tar -xzf harbor-offline-installer-v${MINOR_VERSION}.tgz -C /usr/local/
		fi
		break
	done
	echo $?

fi
break
done

#install method 
# 1. http method installation

echo ">>> Please select the installation that harbor method ? eg: http or https " 

select i in http https; do
	echo "you choice is the installation harbor that ${i} method "

	if [ "${i}" = "http" ]; then
	
	source /tmp/export.sh
    cat << EOF > /etc/docker/daemon.json
{
    "registry-mirrors": ["http://v5d7kh0f.mirror.aliyuncs.com"],"insecure-registries":["http://${IP}"]}

}
EOF
    # view docker status
    systemctl daemon-reload
    systemctl restart docker
    systemctl status docker

	cat << EOF > /usr/local/harbor/harbor.yml
hostname: ${IP}
http:
  # port for http, default is 80. If https enabled, this port will redirect to https port
  port: 80
harbor_admin_password: Harbor12345
database:
  # The password for the root user of Harbor DB. Change this before any production use.
  password: root123
  # The maximum number of connections in the idle connection pool. If it <=0, no idle connections are retained.
  max_idle_conns: 50
  # The maximum number of open connections to the database. If it <= 0, then there is no limit on the number of open connections.
  # Note: the default number of connections is 100 for postgres.
  max_open_conns: 100
data_volume: /data
clair:
  # The interval of clair updaters, the unit is hour, set to 0 to disable the updaters.
  updaters_interval: 12
jobservice:
  # Maximum number of job workers in job service
  max_job_workers: 10
notification:
  # Maximum retry count for webhook job
  webhook_job_max_retry: 10
chart:
  # Change the value of absolute_url to enabled can enable absolute url in chart
  absolute_url: disabled
log:
  # options are debug, info, warning, error, fatal
  level: info
  # configs for logs in local storage
  local:
    # Log files are rotated log_rotate_count times before being removed. If count is 0, old versions are removed rather than rotated.
    rotate_count: 50
    # Log files are rotated only if they grow bigger than log_rotate_size bytes. If size is followed by k, the size is assumed to be in kilobytes.
    # If the M is used, the size is in megabytes, and if G is used, the size is in gigabytes. So size 100, size 100k, size 100M and size 100G
    # are all valid.
    rotate_size: 200M
    # The directory on your host that store log
    location: /var/log/harbor
  # Uncomment following lines to enable external syslog endpoint.
  # external_endpoint:
  #   # protocol used to transmit log to external endpoint, options is tcp or udp
  #   protocol: tcp
  #   # The host of external endpoint
  #   host: localhost
  #   # Port of external endpoint
  #   port: 5140
_version: 1.9.0
proxy:
  http_proxy:
  https_proxy:
  no_proxy: 127.0.0.1,localhost,.local,.internal,log,db,redis,nginx,core,portal,postgresql,jobservice,registry,registryctl,clair
  components:
    - core
    - jobservice
    - clair
EOF
  cd /usr/local/harbor
	./install.sh
	docker-compose start
	echo ">>> docker-compose status"
	docker-compose ps	

	echo ">>> Browser enter http://ip, By default, the username and password is：admin/Harbor12345"
	sleep 3

	else

	# https method installation

    source /tmp/export.sh
   cat << EOF > /etc/docker/daemon.json
{
  "registry-mirrors": ["https://v5d7kh0f.mirror.aliyuncs.com"],"insecure-registries":["https://${IP}"]}
}
EOF
    # view docker status
    systemctl daemon-reload
    systemctl restart docker
    systemctl status docker
    
    # install certificate production tools
    if [ ! -f  "/usr/local/bin/cfssl" ] && [ ! -f  "/usr/local/bin//usr/local/bin/cfssljson" ] && [ ! -f  "/usr/local/bin//usr/bin/cfssl-certinfo" ]; then
    wget -c https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
    wget -c https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
    wget -c https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
    chmod +x cfssl_linux-amd64 cfssljson_linux-amd64 cfssl-certinfo_linux-amd64
    mv cfssl_linux-amd64 /usr/local/bin/cfssl
    mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
    mv cfssl-certinfo_linux-amd64 /usr/bin/cfssl-certinfo
    else
    echo "file already exist"
    fi
    
    #create certificat dirctory
    mkdir -p /opt/harbor/cert && cd /opt/harbor/cert
    # certificate configure file
cat << EOF >> ca-config.json
{
    "signing": {
        "default": {
            "expiry": "87600h"
        },
        "profiles": {
            "harbor": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF
   
    # create Certificate Signing Request file
cat << EOF >> ca-csr.json
{
    "CN": "harbor",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "O": "harbor",
            "OU": "harbor",
            "L": "the internet"
        }
    ]
}
EOF
   
    # use cfssl tools generation ca and  certificate key file
    cfssl gencert -initca ca-csr.json | cfssljson -bare ca
    ls ca*
   
cat << EOF > harbor-csr.json
{
    "CN": "harbor",
    "hosts": [
      "127.0.0.1",
      "${IP}"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "O": "harbor",
            "OU": "harbor",
            "L": "the internet"
        }
    ]
}
EOF
   
    # Generate the certificate and private key of proxy-client 
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=harbor harbor-csr.json | cfssljson -bare harbor
    ls harbor*.pem
   
    source /tmp/export.sh
    cd /usr/local/harbor/
cat << EOF > harbor.yml 
hostname: ${IP} 
#https related config
https:
  # https port for harbor, default is 443
  port: 443
  # The path of cert and key files for nginx
  certificate: /opt/harbor/cert/harbor.pem
  private_key: /opt/harbor/cert/harbor-key.pem

#http:
  # port for http, default is 80. If https enabled, this port will redirect to https port
  # port: 80
harbor_admin_password: Harbor12345
database:
  # The password for the root user of Harbor DB. Change this before any production use.
  password: root123
  # The maximum number of connections in the idle connection pool. If it <=0, no idle connections are retained.
  max_idle_conns: 50
  # The maximum number of open connections to the database. If it <= 0, then there is no limit on the number of open connections.
  # Note: the default number of connections is 100 for postgres.
  max_open_conns: 100
data_volume: /data
clair:
  # The interval of clair updaters, the unit is hour, set to 0 to disable the updaters.
  updaters_interval: 12
jobservice:
  # Maximum number of job workers in job service
  max_job_workers: 10
notification:
  # Maximum retry count for webhook job
  webhook_job_max_retry: 10
chart:
  # Change the value of absolute_url to enabled can enable absolute url in chart
  absolute_url: disabled
log:
  # options are debug, info, warning, error, fatal
  level: info
  # configs for logs in local storage
  local:
    # Log files are rotated log_rotate_count times before being removed. If count is 0, old versions are removed rather than rotated.
    rotate_count: 50
    # Log files are rotated only if they grow bigger than log_rotate_size bytes. If size is followed by k, the size is assumed to be in kilobytes.
    # If the M is used, the size is in megabytes, and if G is used, the size is in gigabytes. So size 100, size 100k, size 100M and size 100G
    # are all valid.
    rotate_size: 200M
    # The directory on your host that store log
    location: /var/log/harbor
  # Uncomment following lines to enable external syslog endpoint.
  # external_endpoint:
  #   # protocol used to transmit log to external endpoint, options is tcp or udp
  #   protocol: tcp
  #   # The host of external endpoint
  #   host: localhost
  #   # Port of external endpoint
  #   port: 5140
_version: 1.9.0
proxy:
  http_proxy:
  https_proxy:
  no_proxy: 127.0.0.1,localhost,.local,.internal,log,db,redis,nginx,core,portal,postgresql,jobservice,registry,registryctl,clair
  components:
    - core
    - jobservice
    - clair
EOF

	source /tmp/export.sh
	cd /usr/local/harbor/
	#docker-compose down -v
	./install.sh
	echo ">>> docker-compose startup"
	docker-compose up -d
	echo ">>> docker-compose status"
	docker-compose ps
	fi
	break
done

#然后再测试再harbor本机登录，即可成功。
#
#登录的账号信息都保存到/root/.docker/config.json文件里了
## cat /root/.docker/config.json
#{
#        "auths": {
#                "192.168.170.12": {
#                        "auth": "YWRtaW46a2V2aW5AQk8xOTg3"
#                }
#        },
#        "HttpHeaders": {
#                "User-Agent": "Docker-Client/18.09.6 (linux)"
#        }
#  
#只要/root/.docker/config.json里的信息不删除，后续再次登录的时候，就不用输入用户名和密码了
#
#4、 从docker客户端，开始push镜像,push/pull镜像只能在docker主机上执行命令操作！对于私有镜像，不管是push还是pull都需要login之后才能操作。
#
##给镜像打标签：按照harbor_ip/{project-name}/{image-name}[:Tag]的方式打Tag
##  docker tag nginx:1.11.5 192.168.170.12/my_data/nginx:1.11.5
##  docker tag alpine 192.168.170.12/my_data/alpine
#
##push镜像
##  docker push 192.168.170.12/my_data/nginx:1.11.5
#....
##  docker push 192.168.170.12/my_data/alpine
#The push refers to a repository [192.168.170.12/my_data/alpine]
#011b303988d2: Pushed 
#latest: digest: sha256:1354db23ff5478120c980eca1611a51c9f2b88b61f24283ee8200bf9a54f2e5c size: 528
#
#push上传镜像成功，然后在web上看一下镜像是否存在。


