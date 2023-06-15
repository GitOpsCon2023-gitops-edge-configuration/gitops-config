!#/bin/sh
export APP_NAME=$1
export APP_VERSION=$2
export REPO_VERSION=1.0.0

# Flow to create new package
# mkdir -p temp/src/$APP_NAME  
# kctrl package init --chdir packages/$APP_NAME  
# redis.corp.com,3,https://charts.bitnami.com/bitnami,redis,17.8.2
# kctrl package release --version $APP_VERSION   --repo-output ../../repository/1.0.0 --chdir packages/$APP_NAME    
kctrl package repository release --chdir repository/1.0.0 --version $REPO_VERSION  # --copy-to can be used for location for pkgrepo-build.yml



# # Flow to create a new release for existing package
# # change the version in vendir.yaml then run 
# kctrl package init -y --chdir packages/$APP-NAME   # or vendor sync
# kctrl package release -y --version $APP-VERSION --repo-output ../../repository/1.0.0 --chdir packages/$APP-NAME   


# # Flow for new release
# # change the REPO version then run 
# kctrl package repository release -y --chdir repository/1.0.0 --version $REPO_VERSION  # --copy-to can be used for location for pkgrepo-build.yml
