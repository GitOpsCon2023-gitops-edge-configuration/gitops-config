#_ECHO_OFF
export DEMO_DELAY=0
source kctrl-test/set-env-hello-app.sh
clear
#_ECHO_ON
#_ECHO_# Based on demo: https://asciinema.org/a/515349
env | grep "KCTRL_"

rm -rf $KCTRL_DEMO_TEMP
mkdir -p $KCTRL_PKG_DIR

#_ECHO_# Initialize package (prompt answers: certman.carvel.dev , 2 , cert-manager/cert-manager , v1.9.0 , cert-manager.yaml)
kctrl package init --chdir $KCTRL_PKG_DIR
tree $KCTRL_DEMO_TEMP

#_ECHO_# Make sure you ran `docker login`. Prompt answers: index.docker.io/ciberkleid736/certman-package
kctrl package release --chdir $KCTRL_PKG_DIR --version $KCTRL_PKG_VERSION --repo-output $KCTRL_REPO_DIR --tag $KCTRL_PKG_VERSION --copy-to "carvel-artifacts"
#_ECHO_# Note:Runs ytt, kbld, and imgpkg push
tree $KCTRL_PKG_DIR/carvel-artifacts
tree $KCTRL_REPO_DIR

#_ECHO_# Prompt answers: kctrl-pkg-repo.carvel.dev , index.docker.io/ciberkleid736/kctrl-pkg-repo
kctrl package repository release --chdir $KCTRL_REPO_DIR --version $KCTRL_PKG_REPO_VERSION  # --copy-to can be used for location for pkgrepo-build.yml
#_ECHO_# kctrl package repository add -f package-repository.yml  # BETTER: USE GIT PUSH TO TRIGGER DECLARATIVE WORKFLOW

#_ECHO_# ----------------
#_ECHO_# You could apply to k8s or use `kctrl package repo release`
#_ECHO_# kapp deploy -a certman-package -f carvel-artifacts/packages/certman.carvel.dev  # applies package and metadata
kctrl package available list

#_ECHO_# ####

#kctrl package repo list
#kctrl package install -I help-app -p hello-app.corp.com —version 1.0.0
#kctrl package available get -p hello-app.corp.com/1.0.0 values-schema
#kctrl package installed update -I hello-app —values-file - << EOF
#—
#user_name: 100mik
#
#kctrl package installed delete -I hello-app
#
#kctrl package installed list
#
#kctrl package installed pause -I cert-man
#
#kctrl package installed get -I cert-man (See it is paused)
#
#kctrl package installed kick -I cert-man
#
#kctrl package installed get -I cert-man (See it is paused)
#
#kctrl app list
#
#kctrl  app get -a cert-main
#
#kctrl app pause -a simple-app
#
#kctrl app list (see app is paused)
#
#kctrl app pause -a cert-man
#
#cat faulty-app.yaml (see old demo from souk, 9 min in for content)
#kapp deploy -a faulty faulty-app -f faulty-app.yml —wait=false
#
#kctrl app status -a faulty-app
#kctrl app get -a faulty-app
#
#kctrl package installed status -I cert-man
