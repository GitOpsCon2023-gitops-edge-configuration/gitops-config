# To execute, run:
# ./scripts/demorunner.sh scripts/demoscript.sh

# To clean beforehand, run:
# source scripts/clean-app-env.sh

###### Pre-requisites:
#kubectl api-resources |grep kapp
#TODO
#check for kapp and run prerequisites or abort if not installed
#_ECHO_OFF

DEMO_HOME=$( pwd )

echo
echo "Setting env vars"
# unset APP_NAME VERSION PROFILE DEPLOYMENT REPO_VERSION MY_REG
# To override, export env vars with desired values and re-run demo script
source $DEMO_HOME/scripts/set-app-env.sh "${APP_NAME:=hello-app}" "${PROFILE:=lg}" "${DEPLOYMENT:=ny}" "${VERSION:=1.0.0}" "${REPO_VERSION:=0.0.1}" "${MY_REG:=localhost:5001/gitopscon}"

# TO-DO: Update registry and REPO_VERSION in files. Do this in set env actually

echo "Cloning source code"
mkdir -p $TEMP/src/$APP_NAME && rm -rf $TEMP/src/$APP_NAME && git clone $APP_REPO $TEMP/src/$APP_NAME
#sed -i '' "s|localhost:5001/gitopscon|$MY_REG|g" $APP_HOME/$APP_NAME/kbld.yml
myDest=$MY_REG/$APP_NAME yq e -i '.destinations[0].newImage = env(myDest)' $APP_HOME/$APP_NAME/kbld.yml

clear
#_ECHO_ON
#_ECHO_# Let's package an app for distribution & deployment using Project Carvel!

#_ECHO_# To start, we'll need our app source code and k8s config files
tree $TEMP/src/$APP_NAME $APP_HOME/$APP_NAME

#_ECHO_# Next, we need the k8s config for 3rd party dependencies. Carvel vendir can help us get it!
if [ -f $APP_HOME/$APP_NAME/vendir.yml ]; then yq $APP_HOME/$APP_NAME/vendir.yml; fi
if [ -f $APP_HOME/$APP_NAME/vendir.yml ]; then vendir sync --chdir $APP_HOME/$APP_NAME; tree $APP_HOME/$APP_NAME; fi

#_ECHO_# Finally, we need the k8s config values and overlays for this specific profile
tree $PROFILE_HOME/$PROFILE/$APP_NAME
yq $PROFILE_HOME/$PROFILE/$APP_NAME/overlay/app.yml
#yq $PROFILE_HOME/$PROFILE/$APP_NAME/values/values.yml

#_ECHO_# That's a lot of YAML! Carvel kbld can tell us all the images referenced...
kbld inspect -f $APP_HOME/$APP_NAME/base -f $PROFILE_HOME/$PROFILE/$APP_NAME --column image

# TO-DO: What is kbld flag --unresolved-inspect

#_ECHO_# Looks like we still need to build our app into an image and replace all tags with SHAs. kbld can help here too!
#_ECHO_OFF
# To instruct kbld to re-build the app from source code, remove the app resolution details from images.yaml or delete images.yml
if [[ -f $APP_HOME/$APP_NAME/base/.imgpkg/images.yml ]]; then unset BUILD_FLAG; else export BUILD_FLAG="-f $APP_HOME/$APP_NAME/kbld.yml"; fi;
#yq $APP_HOME/$APP_NAME/base/.imgpkg/images.yml
#yq $APP_HOME/$APP_NAME/kbld.yml
#_ECHO_ON
kbld $BUILD_FLAG -f $APP_HOME/$APP_NAME/base/config -f $PROFILE_HOME/$PROFILE/$APP_NAME --imgpkg-lock-output $APP_HOME/$APP_NAME/base/.imgpkg/images.yml > /dev/null

#_ECHO_# We now have a Bill of Materials that we can use to lock down these SHAs for our images!
yq $APP_HOME/$APP_NAME/base/.imgpkg/images.yml

clear
#_ECHO_# Let's bundle all of the config PLUS the new Bill of Materials file...
imgpkg push -b $MY_REG/$BUNDLE_NAME:$VERSION -f $APP_HOME/$APP_NAME/base -f $PROFILE_HOME/$PROFILE/$APP_NAME --lock-output $APP_HOME/$APP_NAME/$PROFILE-bundle.$VERSION.lock.yml
skopeo list-tags docker://$MY_REG/$BUNDLE_NAME #OR: curl localhost:5001/v2/gitopscon/$BUNDLE_NAME/tags/list |jq

#_ECHO_# What exactly is in the bundle we created? Let's take a look... imgpkg makes it easy to move or share our app bundle
imgpkg pull -b $MY_REG/$BUNDLE_NAME:$VERSION -o $TEMP/app-bundles/$PROFILE/$APP_NAME/$VERSION/bundle; tree -a $TEMP/app-bundles/$PROFILE/$APP_NAME/$VERSION/bundle

#_ECHO_# One nifty thing in this bundle is the app's values schema file. We can use it to understand all configurable values:
ytt -f $TEMP/app-bundles/$PROFILE/$APP_NAME/$VERSION/bundle/config/schema.yaml --data-values-schema-inspect -o openapi-v3 > $TEMP/app-bundles/$PROFILE/$APP_NAME/schema-openapi.yml
head -n 30 $TEMP/app-bundles/$PROFILE/$APP_NAME/schema-openapi.yml | yq

#_ECHO_# At this point, we could use Carvel ytt to render a deployable version of the YAML
#_ECHO_# But we want Kubernetes to do this declaratively, not imperatively! Carvel has some K8s CRDs that can do this!
# TO-DO: Consider: maybe this should be the first profile-specific artifact? One app, one package per profile?
#_ECHO_# Let's start with PackageMetadata, a way to provide some metadata to Kubernetes
#_ECHO_OFF
ytt -f $PKG_REPO_HOME/templates/metadata-template.yml -v packageName="$PACKAGE_NAME" -v appName="$APP_NAME" > $PKG_REPO_HOME/$PROFILE/$REPO_VERSION/packages/$PACKAGE_NAME/metadata.yml
#_ECHO_ON
yq $PKG_REPO_HOME/$PROFILE/$REPO_VERSION/packages/$PACKAGE_NAME/metadata.yml

#_ECHO_# For each release of the app bundle, we'll also need a Package CRD
#_ECHO_OFF
ytt -f $PKG_REPO_HOME/templates/package-template.yml --data-value-file openapi=$TEMP/app-bundles/$PROFILE/$APP_NAME/schema-openapi.yml -v version="$VERSION" -v packageName="$PACKAGE_NAME" -v bundleName="$BUNDLE_NAME" -v registry="$MY_REG" > $PKG_REPO_HOME/$PROFILE/$REPO_VERSION/packages/$PACKAGE_NAME/$VERSION.yml
#_ECHO_ON
yq $PKG_REPO_HOME/$PROFILE/$REPO_VERSION/packages/$PACKAGE_NAME/$VERSION.yml

clear
#_ECHO_# Most likely you have many apps, so you'll have many Packages, and you'll need to send all of them to many target locations.
tree $PKG_REPO_HOME/$PROFILE/$REPO_VERSION/packages/
#_ECHO_# How can you bundle and distribute these easily for deployment at many target locations? Remember our friend imgpkg?
kbld -f $PKG_REPO_HOME/$PROFILE/$REPO_VERSION/ --imgpkg-lock-output $PKG_REPO_HOME/$PROFILE/$REPO_VERSION/.imgpkg/images.yml > /dev/null

# TODO: This file should also be in git, along with the corrresponding packageinstaller and location values config: $PKG_REPO_HOME/$PROFILE/$REPO_VERSION/.imgpkg/images.yml

imgpkg push -b $MY_REG/$PACKAGE_REPO_NAME:$REPO_VERSION -f $PKG_REPO_HOME/$PROFILE/$REPO_VERSION
skopeo list-tags docker://$MY_REG/$PACKAGE_REPO_NAME  #OR curl localhost:5001/v2/gitopscon/$PACKAGE_REPO_NAME/tags/list |jq
#curl -X GET http://localhost:5001/v2/_catalog | jq

clear
#_ECHO_# Let's consider the perspective of the target deployment location. How do we get the PackageRepo into our cluster?
#_ECHO_# Carvel provides a Kubernetes Controller called kapp-controller that can help automate pulling and installing packages
#_ECHO_OFF
# TO-DO - Should this repo.$REPO_VERSION.yml file be versioned or put under a different hierarchy?
# TODO: Rework this command so as to suppress kbld output to /dev/null
# ALSO: Philosophical question: should the repo be updated through automated gitops?
#       Try this sometime: Split this command into two to capture the output of ytt
#       Consider putting that in git with a corresponding App CRD to automate PkgRepo updates
#       This about how to use kbld to control updates in this scenario
#       Ex. What if repo template has version 5 and pkg repo 5.0 is upgraded to 5.1?
ytt -f $DEPLOYMENT_HOME/templates/pkg-repo-template.yml -v registry="$MY_REG" -v profile="$PROFILE" -v packageRepoVersion="$REPO_VERSION" | kbld -f- --imgpkg-lock-output $DEPLOYMENT_HOME/$PROFILE/.imgpkg/images.yml > $DEPLOYMENT_HOME/$PROFILE/repo.$REPO_VERSION.yml
#_ECHO_ON
yq $DEPLOYMENT_HOME/$PROFILE/repo.$REPO_VERSION.yml

#_ECHO_# Let's apply this to the cluster!
# TODO: This step fails if the pkg-repo image is on kind. Just move this one to gcr and all is good
kapp deploy -a $PROFILE-pkg-repo -f $DEPLOYMENT_HOME/$PROFILE/repo.$REPO_VERSION.yml -y

#_ECHO_# We can now list all of the available Packages in the PackageRepository
# kubectl get packagerepository
# kubectl get packagemetadatas
kubectl get packages
kubectl get package $PACKAGE_NAME.$VERSION  -o yaml |yq

#_ECHO_# To install the Package and to specify any final configuration values, we need a PackageInstall and Secret
#_ECHO_OFF
# TO DO: Create a PackageInstall template
# Write a command here to generate a PackageInstall file
# This file would eventually need to be committed to git when you decide to automate this with an App
#_ECHO_ON
yq $DEPLOYMENT_HOME/$PROFILE/pkg-installer/$REPO_VERSION/$DEPLOYMENT/$APP_NAME.yml

#_ECHO_# At this point, you could imperatively apply the PackageInstall and Secret to K8s, but... we'd rather automate this!
# e.g. kapp deploy -a $PROFILE-$APP_NAME -f $DEPLOYMENT_HOME/$PROFILE/pkg-installer/$DEPLOYMENT/$APP_NAME.yml -y

#_ECHO_# Of course, our PackageInstall and Secret would need to be available in a git repo...
open https://github.com/GitOpsCon2023-gitops-edge-configuration/gitops-config/tree/main/$DEPLOYMENT_HOME/$PROFILE/pkg-installer/$REPO_VERSION/$DEPLOYMENT/$APP_NAME.yml
# If you created a new app or a new version, git push the following files:
#git add $DEPLOYMENT_HOME/$PROFILE/pkg-installer/$REPO_VERSION/$DEPLOYMENT/$APP_NAME.yml
#git add $DEPLOYMENT_HOME/$PROFILE/pkg-installer/$REPO_VERSION/$DEPLOYMENT/$APP_NAME.yml
#git commit -m "update"
#git push

#_ECHO_# And we can use Carvel kapp-controller to watch for changes in these files and automatically update the cluster
#_ECHO_OFF
ytt -f $DEPLOYMENT_HOME/templates/pkg-gitops-template.yml -v profile="$PROFILE" -v packageRepoVersion="$REPO_VERSION" -v deployment="$DEPLOYMENT" | kbld -f- --imgpkg-lock-output $DEPLOYMENT_HOME/$PROFILE/gitops-controller/.imgpkg/images.yml > $DEPLOYMENT_HOME/$PROFILE/gitops-controller/$DEPLOYMENT/pkg-gitops.$REPO_VERSION.yml
#_ECHO_ON
yq $DEPLOYMENT_HOME/$PROFILE/gitops-controller/$DEPLOYMENT/pkg-gitops.$REPO_VERSION.yml

# TODO: Try also with kapp
kubectl apply  -f $DEPLOYMENT_HOME/$PROFILE/gitops-controller/$DEPLOYMENT/pkg-gitops.$REPO_VERSION.yml

#_ECHO_# Now every time a location wants to upgrade a package or change local vales, they just need to make a git commit!

# DEMO - Change local values


# DEMO - Upgrade Package version

kubectl get packagerepository
kubectl get packages
kubectl get packageinstalls

#_ECHO_# What if the target location is air-gapped? imgpkg can help!
imgpkg copy -b $MY_REG/$PACKAGE_REPO_NAME:$REPO_VERSION --to-repo $EDGE_REG/$PACKAGE_REPO_NAME
imgpkg pull -b $EDGE_REG/$PACKAGE_REPO_NAME:$REPO_VERSION -o $TEMP/airgapped
tree -a $TEMP/airgapped
yq $TEMP/airgapped/.imgpkg/images.yml

##This PackageRepository CR will allow kapp-controller to install any of the packages found within the repo
#kctrl package available list
#kctrl package installed list
#kctrl package installed delete lg-hello-app.corp.com -y
#kctrl package installed delete lg-gaint-app.corp.com -y
#kapp delete -a repo -y
#kapp delete -a lg-ny-pkg-gitops -y
#kapp delete -a lg-hello-app   -y
#kapp delete -a lg-giant-app   -y
#
#kctrl package available get lg-hello-app.corp.com/1.0.0 --values-schema
#kubectl get package lg-hello-app.corp.com.1.0.0 -o yaml
