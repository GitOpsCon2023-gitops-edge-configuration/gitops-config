#!/bin/bash
# Copyright 2021 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -eo pipefail

TANZU_BOM_DIR=${HOME}/.config/tanzu/EDGE/bom
INSTALL_INSTRUCTIONS='See https://github.com/mikefarah/yq#install for installation instructions'
EDGE_CUSTOM_IMAGE_REPOSITORY=${EDGE_CUSTOM_IMAGE_REPOSITORY:-''}
EDGE_IMAGE_REPO=${EDGE_IMAGE_REPO:-''}
EDGE_BOM_IMAGE_TAG=${EDGE_BOM_IMAGE_TAG:-''}


echodual() {
  echo "$@" 1>&2
  echo "#" "$@"
}

if [ -z "$EDGE_CUSTOM_IMAGE_REPOSITORY" ]; then
  echo "EDGE_CUSTOM_IMAGE_REPOSITORY variable is required but is not defined" >&2
  exit 1
fi

if [ -z "$EDGE_IMAGE_REPO" ]; then
  echo "EDGE_IMAGE_REPO variable is required but is not defined" >&2
  exit 2
fi

if ! [ -x "$(command -v imgpkg)" ]; then
  echo 'Error: imgpkg is not installed.' >&2
  exit 3
fi

if ! [ -x "$(command -v yq)" ]; then
  echo 'Error: yq is not installed.' >&2
  echo "${INSTALL_INSTRUCTIONS}" >&2
  exit 3
fi

function imgpkg_copy() {
    src=$1
    dst=$2
    echo ""
    echo "imgpkg copy --tar $src.tar --to-repo $dst"
}

if [ -n "$EDGE_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE" ]; then
  function imgpkg_copy() {
      src=$1
      dst=$2
      echo ""
      echo "imgpkg copy --tar $src.tar --to-repo $dst --registry-ca-cert-path /tmp/cacrtbase64d.crt"
  }
fi

echo "set -eo pipefail"
echo 'if [ -n "$EDGE_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE" ]; then
  echo $EDGE_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE > /tmp/cacrtbase64
  base64 -d /tmp/cacrtbase64 > /tmp/cacrtbase64d.crt
fi'
echodual "Note that yq must be version above or equal to version 4.9.2 and below version 5."

actualImageRepository="$EDGE_IMAGE_REPO"

# Iterate through EDGE BoM file to create the complete Image name
# and then pull, retag and push image to custom registry.
list=$(imgpkg  tag  list -i "${actualImageRepository}"/edge_bom)
for imageTag in ${list}; do
  tanzucliversion=$(tanzu version | head -n 1 | cut -c10-15)
  if [[ ${imageTag} == ${tanzucliversion}* ]] || [[ ${imageTag} == ${EDGE_BOM_IMAGE_TAG} ]]; then
    EDGE_BOM_FILE="edge_bom-${imageTag//_/+}.yaml"
    imgpkg pull --image "${actualImageRepository}/edge_bom:${imageTag}" --output "tmp" > /dev/null 2>&1
    echodual "Processing EDGE BOM file ${EDGE_BOM_FILE}"

    actualEDGEImage=${EDGE_CUSTOM_IMAGE_REPOSITORY}/edge_bom
    customEDGEImage=edge_bom-${imageTag}
    imgpkg_copy $customEDGEImage $actualEDGEImage

    # Get components in the edge_bom.
    # Remove the leading '[' and trailing ']' in the output of yq.
    components=(`yq e '.components | keys | .. style="flow"' "tmp/$EDGE_BOM_FILE" | sed 's/^.//;s/.$//'`)
    for comp in "${components[@]}"
    do
    # remove: leading and trailing whitespace, and trailing comma
    comp=`echo $comp | sed -e 's/^[[:space:]]*//' | sed 's/,*$//g'`
    get_comp_images="yq e '.components[\"${comp}\"][]  | select(has(\"images\"))|.images[] | .imagePath + \":\" + .tag' "\"tmp/\"$EDGE_BOM_FILE""

    eval $get_comp_images | while read -r image; do        
        image2=$(echo "$image" | tr ':' '-' | tr '/' '-')
        image3=$(echo "$image" | cut -f1 -d":")
        actualImage=${EDGE_CUSTOM_IMAGE_REPOSITORY}/${image3}
        customImage=${image2}
        imgpkg_copy $customImage $actualImage 
      done
    done

    rm -rf tmp
    echodual "Finished processing EDGE BOM file ${EDGE_BOM_FILE}"
    echo ""
  fi
done

# Iterate through TKR BoM file to create the complete Image name
# and then pull, retag and push image to custom registry.
# DOWNLOAD_TKRS is a space separated list of TKR names, as stored in registry
# when set, the tkr-bom will be ignored.
list=${DOWNLOAD_TKRS:-$(imgpkg  tag  list -i ${actualImageRepository}/tkr-bom)}
for imageTag in ${list}; do
  if [[ ${imageTag} == v* ]]; then
    TKR_BOM_FILE="tkr-bom-${imageTag//_/+}.yaml"
    echodual "Processing TKR BOM file ${TKR_BOM_FILE}"

    actualTKRImage=${EDGE_CUSTOM_IMAGE_REPOSITORY}/tkr-bom
    customTKRImage=tkr-bom-${imageTag}
    imgpkg_copy $customTKRImage $actualTKRImage
    imgpkg pull --image ${actualImageRepository}/tkr-bom:${imageTag} --output "tmp" > /dev/null 2>&1

    # Get components in the tkr-bom.
    # Remove the leading '[' and trailing ']' in the output of yq.
    components=(`yq e '.components | keys | .. style="flow"' "tmp/$TKR_BOM_FILE" | sed 's/^.//;s/.$//'`)
    for comp in "${components[@]}"
    do
    # remove: leading and trailing whitespace, and trailing comma
    comp=`echo $comp | sed -e 's/^[[:space:]]*//' | sed 's/,*$//g'`
    get_comp_images="yq e '.components[\"${comp}\"][]  | select(has(\"images\"))|.images[] | .imagePath + \":\" + .tag' "\"tmp/\"$TKR_BOM_FILE""

    eval $get_comp_images | while read -r image; do
        image2=$(echo "$image" | cut -f1 -d":")
        actualImage=${EDGE_CUSTOM_IMAGE_REPOSITORY}/${image2}
        image3=$(echo "$image" | tr ':' '-' | tr '/' '-')
        customImage=${image3}
        imgpkg_copy $customImage $actualImage 
      done
    done

    rm -rf tmp
    echodual "Finished processing TKR BOM file ${TKR_BOM_FILE}"
    echo ""
  fi
done

list=$(imgpkg  tag  list -i ${actualImageRepository}/tkr-compatibility)
for imageTag in ${list}; do
  if [[ ${imageTag} == v* ]]; then
    echodual "Processing TKR compatibility image"
    actualImage=${EDGE_CUSTOM_IMAGE_REPOSITORY}/tkr-compatibility
    customImage=tkr-compatibility-${imageTag}
    imgpkg_copy $customImage $actualImage 
    echo ""
    echodual "Finished processing TKR compatibility image"
  fi
done

list=$(imgpkg  tag  list -i ${actualImageRepository}/EDGE-compatibility)
for imageTag in ${list}; do
  if [[ ${imageTag} == v* ]]; then
    echodual "Processing EDGE compatibility image"
    actualImage=${EDGE_CUSTOM_IMAGE_REPOSITORY}/EDGE-compatibility
    customImage=EDGE-compatibility-${imageTag}
    imgpkg_copy $customImage $actualImage 
    echo ""
    echodual "Finished processing EDGE compatibility image"
  fi
done
