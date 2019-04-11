# DOSUE
DOcker compose SUper Express deployment tool

## INTRODUCTION
`dosue` is a small commandline tool

`dosue` aims deploying docker container service more easily and comfortably

we want to deploy small service written in docker-compose.yml to remote server by one command

`dosue` wraps following process in one command
- copy docker-compoe.yml to remote server
- copy .env to remote server if you needed
- `docker login` to `ECR` in remote server using credential in local machine
- `docker-compose pull` in remote server
- `docker-compose up -d` in remote server

Therefore, services deployed by dosue can not scale out

dosue is suited environment like small internal tool created by docker-compose

## INSTALL
```
curl -L -o /usr/local/bin/dosue https://github.com/garicchi/dosue/releases/download/1.1/dosue.sh;chmod u+x /usr/local/bin/dosue
```

## UNINSTALL
```
rm /usr/local/bin/dosue
```

## REQUIREMENTS
- enable `aws` command and login using `aws configure`
```
aws configure
```
- enable ssh access to remote server and run `ssh-add <key>` with ssh-agent
```
ssh-add <path to ssh private key to remote server>
```
- enable to run `docker` and `docker-compose` command in remote server by normal user
```
ssh <remote server>
# if you use amazon linux on EC2
#   install docker
sudo yum update -y&&sudo yum install -y docker&&sudo service docker start&&sudo usermod -a -G docker ec2-user
#   install docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose&&sudo chmod +x /usr/local/bin/docker-compose

```

## DEPLOY CONTAINER

```
cd <path to docker-compose.yml dir>

# push image to registory
docker-compose push

# deploy container
dosue --server <user@host> deploy
```
