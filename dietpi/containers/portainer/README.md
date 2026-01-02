 ***************** portainer ******************
docker volume create portainer_data
docker run -d -p 8000:8000 -p 9000:9000 --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce
 ***************** ***************** *****************





 ***************** rancher ******************
docker run -d --restart=unless-stopped -p 80:80 -p 443:443 --privileged rancher/rancher:latest
 ***************** ***************** ***************** ***************** *****************
