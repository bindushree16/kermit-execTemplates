#!/bin/bash -e

#
# Header script is attached at the beginning of every script generated and
# contains the most common methods use across the script
#

# tracks groups started with start_group
export open_group_list=()
declare -x -A open_group_info=()

bump_semver() {
  local version_to_bump=$1
  local action=$2
  local versionParts=$(echo "$version_to_bump" | cut -d "-" -f 1 -s)
  local prerelease=$(echo "$version_to_bump" | cut -d "-" -f 2 -s)
  if [[ $versionParts == "" && $prerelease == "" ]]; then
    # when no prerelease is present
    versionParts=$version_to_bump
  fi
  local major=$(echo "$versionParts" | cut -d "." -f 1 | sed "s/v//")
  local minor=$(echo "$versionParts" | cut -d "." -f 2)
  local patch=$(echo "$versionParts" | cut -d "." -f 3)
  if ! [[ $action == "major" || $action == "minor" || $action == "patch" ||
    $action == "rc" || $action == "alpha" || $action == "beta" || $action == "final" ]]; then
    echo "error: Invalid action given in the argument." >&2; exit 99
  fi
  local numRegex='^[0-9]+$'
  if ! [[ $major =~ $numRegex && $minor =~ $numRegex && $patch =~ $numRegex ]] ; then
    echo "error: Invalid semantics given in the argument." >&2; exit 99
  fi
  if [[ $(echo "$versionParts" | cut -d "." -f 1) == $major ]]; then
    appendV=false
  else
    appendV=true
  fi
  if [[ $action == "final" ]];then
    local new_version="$major.$minor.$patch"
  else
    if [[ $action == "major" ]]; then
      major=$((major + 1))
      minor=0
      patch=0
    elif [[ $action == "minor" ]]; then
      minor=$((minor + 1))
      patch=0
    elif [[ $action == "patch" ]]; then
      patch=$((patch + 1))
    elif [[ $action == "rc" || $action == "alpha" || $action == "beta" ]]; then
      local prereleaseCount="";
      local prereleaseText="";
      if [ ! -z $(echo "$prerelease" | grep -oP "$action") ]; then
        local count=$(echo "$prerelease" | grep -oP "$action.[0-9]*")
        if [ ! -z $count ]; then
          prereleaseCount=$(echo "$count" | cut -d "." -f 2 -s)
          prereleaseCount=$(($prereleaseCount + 1))
        else
          prereleaseCount=1
        fi
        prereleaseText="$action.$prereleaseCount"
      else
        prereleaseText=$action
      fi
    fi
    local new_version="$major.$minor.$patch"
    if [[ $prereleaseText != "" ]]; then
      new_version="$new_version-$prereleaseText"
    fi
  fi
  if [[ $appendV == true ]]; then
    new_version="v$new_version"
  fi
  echo $new_version
}

read_json() {
  if [ "$1" == "" ]; then
    echo "Usage: read_json JSON_PATH FIELD" >&2
    exit 99
  fi
  if [ -f "$1" ]; then
    cat "$1" | jq -r '.'"$2"
  else
    echo "$1: No such file present in this directory" >&2
    exit 99
  fi
}

decrypt_file() {
  local source_file=""
  local key_file=""
  local dest_file="decrypted"
  local temp_dest='/tmp/shippable/decrypt'

  if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
      ARGUMENT="$1"

      case $ARGUMENT in
        --key)
          key_file=$2
          shift
          shift
          ;;
        --output)
          dest_file=$2
          shift
          shift
          ;;
        *)
          source_file=$1
          shift
          ;;
      esac
    done
  fi

  echo "decrypt_file: Decrypting $source_file using key $key_file"

  if [ ! -f "$key_file" ]; then
    echo "decrypt_file: ERROR - Key file $key_file not found" >&2
    exit 100
  fi

  if [ ! -f "$source_file" ]; then
    echo "decrypt_file: ERROR - Source file $source_file not found" >&2
    exit 100
  fi

  if [ -d "$temp_dest" ]; then
    rm -r ${temp_dest:?}
  fi
  mkdir -p $temp_dest/fragments

  base64 --decode < "$source_file" > $temp_dest/encrypted.raw
  split -b 256 "$temp_dest/encrypted.raw" $temp_dest/fragments/
  local fragments
  fragments=$(ls -b $temp_dest/fragments)
  for fragment in $fragments; do
    openssl rsautl -decrypt -inkey "$key_file" -oaep < "$temp_dest/fragments/$fragment" >> "$dest_file"
  done;

  rm -r ${temp_dest:?}/*
  echo "decrypt_file: Decrypted $source_file to $dest_file"
}

encrypt_file() {
  local source_file=""
  local key_file=""
  local dest_file="encrypted"
  local temp_dest='/tmp/shippable/encrypt'

  if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
      ARGUMENT="$1"

      case $ARGUMENT in
        --key)
          key_file=$2
          shift
          shift
          ;;
        --output)
          dest_file=$2
          shift
          shift
          ;;
        *)
          source_file=$1
          shift
          ;;
      esac
    done
  fi

  echo "encrypt_file: Encrypting $source_file using key $key_file"

  if [ ! -f "$key_file" ]; then
    echo "encrypt_file: ERROR - Key file $key_file not found" >&2
    exit 100
  fi

  if [ ! -f "$source_file" ]; then
    echo "encrypt_file: ERROR - Source file $source_file not found" >&2
    exit 100
  fi

  if [ -d "$temp_dest" ]; then
    rm -r ${temp_dest:?}
  fi
  mkdir -p $temp_dest/fragments

  split -b 128 "$source_file" $temp_dest/fragments/
  local fragments
  fragments=$(ls -b $temp_dest/fragments)

  for fragment in $fragments; do
    openssl rsautl -encrypt -inkey $key_file -pubin -oaep < "$temp_dest/fragments/$fragment" >> $temp_dest/encrypted
  done;

  base64 < "$temp_dest/encrypted" > $dest_file

  rm -r ${temp_dest:?}/*
  echo "encrypt_file: Encrypted $source_file to $dest_file"
}

decrypt_string() {
  local source_string=""
  local key_file=""
  local dest_file=""
  local temp_dest='/tmp/shippable/decrypt'

  if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
      ARGUMENT="$1"

      case $ARGUMENT in
        --key)
          key_file=$2
          shift
          shift
          ;;
        *)
          source_string="$1"
          shift
          ;;
      esac
    done
  fi

  if [ ! -f "$key_file" ]; then
    echo "decrypt_string: ERROR - Key file $key_file not found" >&2
    exit 100
  fi

  if [ -d "$temp_dest" ]; then
    rm -r ${temp_dest:?}
  fi
  mkdir -p $temp_dest/fragments

  echo "$source_string" >> $temp_dest/input

  base64 --decode < "$temp_dest/input" > $temp_dest/encrypted.raw

  split -b 256 "$temp_dest/encrypted.raw" $temp_dest/fragments/
  local fragments
  fragments=$(ls -b $temp_dest/fragments)
  for fragment in $fragments; do
    openssl rsautl -decrypt -inkey "$key_file" -oaep < "$temp_dest/fragments/$fragment" >> "$temp_dest/output"
  done;

  cat $temp_dest/output

  rm -r ${temp_dest:?}/*
}

encrypt_string() {
  local source_string=""
  local key_file=""
  local dest_file=""
  local temp_dest='/tmp/shippable/encrypt'

  if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
      ARGUMENT="$1"

      case $ARGUMENT in
        --key)
          key_file=$2
          shift
          shift
          ;;
        *)
          source_string=$1
          shift
          ;;
      esac
    done
  fi

  if [ ! -f "$key_file" ]; then
    echo "encrypt_string: ERROR - Key file $key_file not found" >&2
    exit 100
  fi

  if [ -d "$temp_dest" ]; then
    rm -r ${temp_dest:?}
  fi
  mkdir -p $temp_dest/fragments

  echo $source_string >> $temp_dest/input

  split -b 128 "$temp_dest/input" $temp_dest/fragments/
  local fragments
  fragments=$(ls -b $temp_dest/fragments)

  for fragment in $fragments; do
    openssl rsautl -encrypt -inkey $key_file -pubin -oaep < "$temp_dest/fragments/$fragment" >> $temp_dest/encrypted
  done;

  base64 < "$temp_dest/encrypted" > $temp_dest/output

  cat $temp_dest/output

  rm -r ${temp_dest:?}/*
}

compare_git() {
  if [[ $# -le 0 ]]; then
    echo "Usage: compare_git [--path | --resource]" >&2
    exit 99
  fi

  # declare options
  local opt_path=""
  local opt_resource=""
  local opt_depth=0
  local opt_directories_only=false
  local opt_commit_range=""

  for arg in "$@"
  do
    case $arg in
      --path)
      opt_path="$2"
      shift
      shift
      ;;
      --resource)
      opt_resource="$2"
      shift
      shift
      ;;
      --depth)
      opt_depth="$2"
      shift
      shift
      ;;
      --directories-only)
      opt_directories_only=true
      shift
      ;;
      --commit-range)
      opt_commit_range="$2"
      shift
      shift
      ;;
    esac
  done

  # obtain the path of git repository
  if [[ "$opt_path" == "" ]] && [[ "$opt_resource" == "" ]]; then
    echo "Usage: compare_git [--path|--resource]" >&2
    exit 99
  fi

  # set file path of git repository
  local git_repo_path="$opt_path"
  if [[ "$git_repo_path" == "" ]]; then
    local dependency_type=$(cat "$step_json_path" | jq -r '.'"$2")
    local resource_directory=$(cat "$step_json_path" | jq -r ."resources.$opt_resource.resourcePath")
    git_repo_path="$resource_directory"
  fi

  if [[ ! -d "$git_repo_path/.git" ]]; then
    echo "git repository not found at path: $git_repo_path" >&2
    exit 99
  fi

  # set default commit range
  # for CI
  local commit_range

  # for runSh with IN: GitRepo
  if [[ "$opt_resource" != "" ]]; then
    # for runSh with IN: GitRepo commits
    local current_commit_sha=$(cat "$step_json_path" | jq -r ."resources.$opt_resource.resourceVersionContentPropertyBag.shaData.commitSha")
    local before_commit_sha=$(cat "$step_json_path" | jq -r ."resources.$opt_resource.resourceVersionContentPropertyBag.shaData.beforeCommitSha")
    commit_range="$before_commit_sha..$current_commit_sha"

    # for runSh with IN: GitRepo pull requests
    local is_pull_request=$(cat "$step_json_path" | jq -r ."resources.$opt_resource.resourceVersionContentPropertyBag.shaData.isPullRequest")
    if [[ "$is_pull_request" == "true" ]]; then
      local current_commit_sha=$(cat "$step_json_path" | jq -r ."resources.$opt_resource.resourceVersionContentPropertyBag.shaData.commitSha")
      local base_branch=$(cat "$step_json_path" | jq -r ."resources.$opt_resource.resourceVersionContentPropertyBag.shaData.pullRequestBaseBranch")
      commit_range="origin/$base_branch...$current_commit_sha"
    fi
  fi

  if [[ "$opt_commit_range" != "" ]]; then
    commit_range="$opt_commit_range"
  fi
  if [[ "$commit_range" == "" ]]; then
    echo "Unknown commit range. use --commit-range." >&2
    exit 99
  fi

  local result=""
  pushd $git_repo_path > /dev/null
    result=$(git diff --name-only $commit_range)

    if [[ "$opt_directories_only" == true ]]; then
      result=$(git diff --dirstat $commit_range | awk '{print $2}')
    fi

    if [[ $opt_depth -gt 0 ]]; then
      if [[ result != "" ]]; then
        result=$(echo "$result" | awk -F/ -v depth=$opt_depth '{print $depth}')
      fi
    fi
  popd > /dev/null

  echo "$result" | uniq
}

update_commit_status() {
  if [[ $# -le 0 ]]; then
    echo "Usage: update_commit_status RESOURCE [--status STATUS --message \"MESSAGE\" --context CONTEXT]" >&2
    exit 99
  fi

  # parse and validate the resource details
  local resourceName="$1"
  shift

  local resource_id=$(eval echo "$"res_"$resourceName"_resourceId)
  if [ -z "$resource_id" ]; then
    echo "Error: resource not found for $resourceName" >&2
    exit 99
  fi
  local integrationAlias=$(eval echo "$"res_"$resourceName"_integrationAlias)
  local integration_name=$(eval echo "$"res_"$resourceName"_"$integrationAlias"_name)
  if [ -z "$integration_name" ]; then
    echo "Error: integration data not found for $resourceName" >&2
    exit 99
  fi

  local i_mastername=$(eval echo "$"res_"$resourceName"_"$integrationAlias"_masterName)

  # declare options and defaults, and parse arguments
  export opt_status=""
  export opt_message=""

  export opt_context=""
  if [ -z "$opt_context" ]; then
    opt_context="${pipeline_name}_${step_name}"
  fi

  while [ $# -gt 0 ]; do
    case $1 in
      --status)
        opt_status="$2"
        shift
        shift
        ;;
      --message)
        opt_message="$2"
        shift
        shift
        ;;
      --context)
        opt_context="$2"
        shift
        shift
        ;;
      *)
        echo "Warning: Unrecognized flag \"$1\""
        shift
        ;;
    esac
  done

  if [ -z "$opt_status" ]; then
    case "$current_script_section" in
      onStart | onExecute )
        opt_status="processing"
        ;;
      onSuccess )
        opt_status="success"
        ;;
      onFailure )
        opt_status="failure"
        ;;
      onComplete )
        if [ "$is_success" == "true" ]; then
          opt_status="success"
        else
          opt_status="failure"
        fi
        ;;
      *)
        echo "Error: unable to determine status in section $current_script_section" >&2
        exit 99
        ;;
    esac
  fi

  if [ "$opt_status" != "processing" ] && [ "$opt_status" != "success" ] && [ "$opt_status" != "failure" ] ; then
    echo "Error: --status may only be processing, success, or failure" >&2
    exit 99
  fi

  if [ -z "$opt_message" ]; then
    opt_message="Step $opt_status in pipeline $pipeline_name"
  fi

  local payload=""
  local endpoint=""
  local headers=""

  local commit=$(eval echo "$"res_"$resourceName"_commitSha)
  local full_name=$(eval echo "$"res_"$resourceName"_gitRepoFullName)
  local integration_url=$(eval echo "$"res_"$resourceName"_"$integrationAlias"_url)

  # set up type-unique options
  case "$i_mastername" in
    github | githubEnterprise )
      local token=$(eval echo "$"res_"$resourceName"_"$integrationAlias"_token)
      local state=""
      if [ "$opt_status" == "processing" ] ; then
        state="pending"
      elif [ "$opt_status" == "success" ] ; then
        state="success"
      elif [ "$opt_status" == "failure" ] ; then
        state="failure"
      fi
      payload="{\"target_url\": \"\${step_url}\",\"description\": \"\${opt_message}\", \"context\": \"\${opt_context}\", \"state\": \"$state\"}"
      endpoint="$integration_url/repos/$full_name/statuses/$commit"
      headers="-H Authorization:'token $token' -H Accept:'application/vnd.GithubProvider.v3'"
      ;;
    bitbucket )
      local username=$(eval echo "$"res_"$resourceName"_"$integrationAlias"_username)
      local app_password=$(eval echo "$"res_"$resourceName"_"$integrationAlias"_token)
      local token=$( echo -n "$username:$app_password" | base64 )
      local state=""
      if [ "$opt_status" == "processing" ] ; then
        state="INPROGRESS"
      elif [ "$opt_status" == "success" ] ; then
        state="SUCCESSFUL"
      elif [ "$opt_status" == "failure" ] ; then
        state="FAILED"
      fi

      payload="{\"url\": \"\${step_url}\",\"description\": \"\${opt_message}\", \"key\": \"\${opt_context}\", \"name\": \"\${step_name}\", \"state\": \"$state\"}"
      endpoint="$integration_url/2.0/repositories/$full_name/commit/$commit/statuses/build"
      headers="-H Authorization:'Basic $token'"
      ;;
    bitbucketServerBasic )
      local username=$(eval echo "$"res_"$resourceName"_"$integrationAlias"_username)
      local password=$(eval echo "$"res_"$resourceName"_"$integrationAlias"_password)
      local token=$( echo -n "$username:$password" | base64 )
      local state=""
      if [ "$opt_status" == "processing" ] ; then
        state="INPROGRESS"
      elif [ "$opt_status" == "success" ] ; then
        state="SUCCESSFUL"
      elif [ "$opt_status" == "failure" ] ; then
        state="FAILED"
      fi

      payload="{\"url\": \"\${step_url}\",\"description\": \"\${opt_message}\", \"key\": \"\${opt_context}\", \"name\": \"\${step_name}\", \"state\": \"$state\"}"
      endpoint="$integration_url/rest/build-status/1.0/commits/$commit"
      headers="-H Authorization:'Basic $token'"
      ;;
    *)
      echo "Error: unsupported provider: $i_mastername" >&2
      exit 99
      ;;
  esac

  local payload_file=/tmp/payload.json
  echo $payload > $payload_file

  replace_envs $payload_file

  local isValid=$(jq type $payload_file || true)
  if [ -z "$isValid" ]; then
    echo "Error: payload is not valid JSON" >&2
    exit 99
  fi

  echo "sending update"
  _post_curl "$payload_file" "$headers" "$endpoint"
}

replicate_resource() {
  if [ "$1" == "" ] || [ "$2" == "" ]; then
    echo "Usage: replicate_resource FROM_resource_name TO_resource_name" >&2
    exit 99
  fi
  local resFrom=$1
  local resTo=$2

  local typeFrom=$(cat "$step_json_path" | jq -r ."resources.$resFrom.resourceTypeCode")
  local typeTo=$(cat "$step_json_path" | jq -r ."resources.$resTo.resourceTypeCode")

  # declare options
  local opt_webhook_data_only=""
  local opt_match_settings=""

  for arg in "$@"
  do
    case $arg in
      --webhook-data-only )
        opt_webhook_data_only="true"
        shift
        ;;
      --match-settings )
        opt_match_settings="true"
        shift
        ;;
      --* )
        echo "Warning: Unrecognized flag \"$arg\""
        shift
        ;;
    esac
  done

  if [ "$typeFrom" != "$typeTo" ]; then
    echo "Error: resources must be the same type." >&2
    exit 99
  fi
  if [[ "$typeFrom" != "1000" ]] && [ -n "$opt_match_settings" ]; then
    echo "Error: --match-settings flag not supported for the specified resources." >&2
    exit 99
  fi
  if [ -z "$(which jq)" ]; then
    echo "Error: jq is required for metadata copy" >&2
    exit 99
  fi

  if [ -n "$opt_match_settings" ]; then
    opt_webhook_data_only="true"
    local fromShaData=$(cat "$step_json_path" | jq -r ."resources.$resFrom.resourceVersionContentPropertyBag.shaData")
    local shouldReplicate="true"
    if [ -z "$fromShaData" ]; then
      echo "Error: FROM resource does not contain shaData." >&2
      exit 99
    fi
    # check for tag-based types.
    local isGitTag=$(cat "$step_json_path" | jq -r ."resources.$resFrom.resourceVersionContentPropertyBag.shaData.isGitTag")
    local isRelease=$(cat "$step_json_path" | jq -r ."resources.$resFrom.resourceVersionContentPropertyBag.shaData.isRelease")

    if [ "$isGitTag" == "true" ]; then
      local gitTagName=$(cat "$step_json_path" | jq -r ."resources.$resFrom.resourceVersionContentPropertyBag.shaData.gitTagName")
      # check if TO has a tags include/exclude section. Will be empty string otherwise.
      local toTagsInclude=$(cat "$step_json_path" | jq -r ."resources.$resTo.resourceConfigPropertyBag.tags.include")
      local toTagsExclude=$(cat "$step_json_path" | jq -r ."resources.$resTo.resourceConfigPropertyBag.tags.exclude")

      if [ -n "$toTagsInclude" ]; then
        local matchedTag=""

        if [[ $gitTagName =~ $toTagsInclude ]]; then
          matchedTag="true"
        fi

        if [ "$matchedTag" != "true" ]; then
          shouldReplicate=""
        fi
      fi
      if [ -n "$toTagsExclude" ]; then
        local matchedTag=""

        if [[ $gitTagName =~ $toTagsExclude ]]; then
          matchedTag="true"
        fi

        if [ "$matchedTag" == "true" ]; then
          shouldReplicate=""
        fi
      fi
    elif [ "$isRelease" != "true" ]; then
      # if it's not a tag, and it's not a release, treat it as a branch.
      local branchName=$(cat "$step_json_path" | jq -r ."resources.$resFrom.resourceVersionContentPropertyBag.shaData.branchName")
      if [ -z "$branchName" ]; then
        echo "Error: no branch name in FROM resource shaData. Cannot replicate."
        return 0
      fi
      local toBranchesInclude=$(cat "$step_json_path" | jq -r ."resources.$resTo.resourceConfigPropertyBag.branches.include")
      local toBranchesExclude=$(cat "$step_json_path" | jq -r ."resources.$resTo.resourceConfigPropertyBag.branches.exclude")

      # check the include/exclude sections
      if [ -n "$toBranchesInclude" ]; then
        local matchedBranch=""

        if [[ $branchName =~ $toBranchesInclude ]]; then
          matchedBranch="true"
        fi

        if [ "$matchedBranch" != "true" ]; then
          shouldReplicate=""
        fi
      fi
      if [ -n "$toBranchesExclude" ]; then
        local matchedBranch=""

        if [[ $branchName =~ $toBranchesExclude ]]; then
          matchedBranch="true"
        fi

        if [ "$matchedBranch" == "true" ]; then
          shouldReplicate=""
        fi
      fi
    fi

    if [ -z "$shouldReplicate" ]; then
      echo "FROM shaData does not match TO settings. skipping replicate"
      return 0
    fi
  fi

  # copy values
  local resource_directory=$(cat "$step_json_path" | jq -r ."resources.$resTo.resourcePath")
  local mdFilePathTo="$resource_directory/replicate.json"

  if [ ! -f "$mdFilePathTo" ]; then
    jq ".resources.$resFrom" $step_json_path > $mdFilePathTo
  fi

  if [ -z "$opt_webhook_data_only" ]; then
    local fromVersion=$(cat "$step_json_path" | jq -r ."resources.$resFrom.resourceVersionContentPropertyBag")
    local tmpFilePath="$resource_directory/copyTmp.json"
    cp $mdFilePathTo  $tmpFilePath
    jq ".resourceVersionContentPropertyBag = $fromVersion" $tmpFilePath > $mdFilePathTo
    rm $tmpFilePath
  else
    # update only the shaData
    local fromShaData=$(cat "$step_json_path" | jq -r ."resources.$resFrom.resourceVersionContentPropertyBag.shaData")
    local tmpFilePath="$resource_directory/copyTmp.json"

    if [ "$fromShaData" != "null" ]; then
      cp $mdFilePathTo  $tmpFilePath
      jq ".resourceVersionContentPropertyBag.shaData = $fromShaData" $tmpFilePath > $mdFilePathTo
    fi

    if [ -f "$tmpFilePath" ]; then
      rm $tmpFilePath
    fi
  fi
}

send_notification() {
  if [[ $# -le 0 ]]; then
    echo "Usage: send_notification INTEGRATION [OPTIONS]" >&2
    exit 99
  fi

  # parse and validate the resource details
  local i_name="$1"
  shift

  local integration_name=$(cat "$step_json_path" | jq -r ."integrations.$i_name.name")
  if [ -z "$integration_name" ]; then
    echo "Error: integration data not found for $i_name" >&2
    exit 99
  fi

  local i_mastername=$(cat "$step_json_path" | jq -r ."integrations.$i_name.masterName")

  # declare options and defaults, and parse arguments

  export opt_color="$NOTIFY_COLOR"
  if [ -z "$opt_color" ]; then
    case "$current_script_section" in
      onStart | onExecute )
        opt_color="#5183a0"
        ;;
      onSuccess )
        opt_color="#40be46"
        ;;
      onFailure )
        opt_color="#fc8675"
        ;;
      onComplete )
        if [ "$is_success" == "true" ]; then
          opt_color="#40be46"
        else
          opt_color="#fc8675"
        fi
        ;;
      * )
        opt_color="#40be46"
        ;;
    esac
  fi

  export opt_icon_url="$NOTIFY_ICON_URL"
  if [ -z "$opt_icon_url" ]; then
    opt_icon_url=""
  fi

  export opt_payload="$NOTIFY_PAYLOAD"
  if [ -z "$opt_payload" ]; then
    opt_payload=""
  fi

  export opt_pretext="$NOTIFY_PRETEXT"
  if [ -z "$opt_pretext" ]; then
    opt_pretext="`date`\n"
  fi

  export opt_recipient="$NOTIFY_RECIPIENT"
  if [ -z "$opt_recipient" ]; then
    opt_recipient=""
  fi

  export opt_username="$NOTIFY_USERNAME"
  if [ -z "$opt_username" ]; then
    opt_username="Shippable"
  fi

  export opt_password="$NOTIFY_PASSWORD"
  if [ -z "$opt_password" ]; then
    opt_password="none"
  fi

  export opt_type="$NOTIFY_TYPE"
  if [ -z "$opt_type" ]; then
    opt_type=""
  fi

  export opt_revision="$NOTIFY_REVISION"
  if [ -z "$opt_revision" ]; then
    opt_revision=""
  fi

  export opt_description="$NOTIFY_DESCRIPTION"
  if [ -z "$opt_description" ]; then
    opt_description=""
  fi

  export opt_changelog="$NOTIFY_CHANGELOG"
  if [ -z "$opt_changelog" ]; then
    opt_changelog=""
  fi

  export opt_project_id="$NOTIFY_PROJECT_ID"
  if [ -z "$opt_project_id" ]; then
    opt_project_id=""
  fi

  export opt_environment="$NOTIFY_ENVIRONMENT"
  if [ -z "$opt_environment" ]; then
    opt_environment=""
  fi

  export opt_email="$NOTIFY_EMAIL"
  if [ -z "$opt_email" ]; then
    opt_email=""
  fi

  export opt_repository="$NOTIFY_REPOSITORY"
  if [ -z "$opt_repository" ]; then
    opt_repository=""
  fi

  export opt_version="$NOTIFY_VERSION"
  if [ -z "$opt_version" ]; then
    opt_version=""
  fi

  export opt_summary="$NOTIFY_SUMMARY"
  if [ -z "$opt_summary" ]; then
    opt_summary=""
  fi

  export opt_attach_file="$NOTIFY_ATTACH_FILE"
  if [ -z "$opt_attach_file" ]; then
    opt_attach_file=""
  fi

  export opt_text="$NOTIFY_TEXT"
  if [ -z "$opt_text" ]; then
    # set up default text
    case "$current_script_section" in
      onStart | onExecute )
        opt_text="${step_name} PROCESSING <${step_url}|#${step_id}>"
        ;;
      onSuccess )
        opt_text="${step_name} SUCCESS <${step_url}|#${step_id}>"
        ;;
      onFailure )
        opt_text="${step_name} FAILURE <${step_url}|#${step_id}>"
        ;;
      onComplete )
        if [ "$is_success" == "true" ]; then
          opt_text="${step_name} SUCCESS <${step_url}|#${step_id}>"
        else
          opt_text="${step_name} FAILURE<${step_url}|#${step_id}>"
        fi
        ;;
      * )
        opt_text="${step_name} <${step_url}|#${step_id}>"
        ;;
    esac
  fi

  # email options
  export opt_status="$NOTIFY_STATUS"

  export opt_recipients=("${NOTIFY_RECIPIENTS[@]}")
  if [ ${#opt_recipients[@]} -eq 0 ]; then
    opt_recipients=()
  fi

  export opt_attachments=("${NOTIFY_ATTACHMENTS[@]}")
  if [ ${#opt_attachments[@]} -eq 0 ]; then
    opt_attachments=()
  fi

  export opt_attach_logs="$NOTIFY_ATTACH_LOGS"
  if [ -z "$opt_attach_logs" ]; then
    opt_attach_logs=false
  fi

  export opt_show_failing_commands="$NOTIFY_SHOW_FAILING_COMMANDS"
  if [ -z "$opt_show_failing_commands" ]; then
    opt_show_failing_commands=false
  fi

  export opt_subject="$NOTIFY_SUBJECT"
  if [ -z "$opt_subject" ]; then
    opt_subject=""
  fi

  export opt_body="$NOTIFY_BODY"
  if [ -z "$opt_body" ]; then
    opt_body=""
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --color)
        opt_color="$2"
        shift
        shift
        ;;
      --icon_url)
        opt_icon_url="$2"
        shift
        shift
        ;;
      --payload)
        opt_payload="$2"
        shift
        shift
        ;;
      --pretext)
        opt_pretext="$2"
        shift
        shift
        ;;
      --recipient)
        opt_recipient="$2"
        shift
        shift
        ;;
      --text)
        opt_text="$2"
        shift
        shift
        ;;
      --username)
        opt_username="$2"
        shift
        shift
        ;;
      --password)
        opt_password="$2"
        shift
        shift
        ;;
      --type)
        opt_type="$2"
        shift
        shift
        ;;
      --revision)
        opt_revision="$2"
        shift
        shift
        ;;
      --description)
        opt_description="$2"
        shift
        shift
        ;;
      --changelog)
        opt_changelog="$2"
        shift
        shift
        ;;
      --appId)
        opt_appId="$2"
        shift
        shift
        ;;
      --appName)
        opt_appName="$2"
        shift
        shift
        ;;
      --project-id)
        opt_project_id="$2"
        shift
        shift
        ;;
      --environment)
        opt_environment="$2"
        shift
        shift
        ;;
      --email)
        opt_email="$2"
        shift
        shift
        ;;
      --repository)
        opt_repository="$2"
        shift
        shift
        ;;
      --version)
        opt_version="$2"
        shift
        shift
        ;;
      --summary)
        opt_summary="$2"
        shift
        shift
        ;;
      --attach-file)
        opt_attach_file="$2"
        shift
        shift
        ;;
      --attach-logs)
        opt_attach_logs=true
        shift
        ;;
      --show-failing-commands)
        opt_show_failing_commands=true
        shift
        ;;
      --subject)
        opt_subject="$2"
        shift
        shift
        ;;
      --body)
        opt_body="$2"
        shift
        shift
        ;;
      --recipients)
        shift
        while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
          opt_recipients+=("$1")
          shift
        done
        ;;
      --attachments)
        shift
        while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
          opt_attachments+=("$1")
          shift
        done
        ;;
      *)
        echo "unrecognized option: $1" >&2
        shift
        ;;
    esac
  done

  if [ "$i_mastername" == "newRelicKey" ]; then
    _notify_newrelic
  elif [ "$i_mastername" == "airBrakeKey" ]; then
    _notify_airbrake
  elif [ "$i_mastername" == "jira" ]; then
    _notify_jira
  elif [ "$i_mastername" == "smtpCreds" ]; then
    _notify_email
  else
    if [ "$i_mastername" != "slackKey" ]; then
      echo "Error: unsupported notification type: $i_mastername" >&2
      exit 99
    fi

    local curl_auth=""
    local default_payload="{\"username\":\"\${opt_username}\",\"attachments\":[{\"pretext\":\"\${opt_pretext}\",\"text\":\"\${opt_text}\",\"color\":\"\${opt_color}\"}],\"channel\":\"\${opt_recipient}\",\"icon_url\":\"\${opt_icon_url}\"}"
    local i_endpoint=$(cat "$step_json_path" | jq -r ."integrations.$i_name.url")

    if [ -z "$i_endpoint" ]; then
      echo "Error: no URL found in resource $i_name" >&2
      exit 99
    fi

    if [ -n "$opt_payload" ]; then
      if [ ! -f $opt_payload ]; then
        echo "Error: file not found at path: $opt_payload" >&2
        exit 99
      fi
      local isValid=$(jq type $opt_payload || true)
      if [ -z "$isValid" ]; then
        echo "Error: payload is not valid JSON" >&2
        exit 99
      fi
      _post_curl "$opt_payload" "$curl_auth" "$i_endpoint"
    else
      echo $default_payload > /tmp/payload.json
      opt_payload=/tmp/payload.json
      replace_envs $opt_payload

      local isValid=$(jq type $opt_payload || true)
      if [ -z "$isValid" ]; then
        echo "Error: payload is not valid JSON" >&2
        exit 99
      fi
      if [ -n "$opt_recipient" ]; then
        echo "sending notification to \"$opt_recipient\""
      fi
      _post_curl "$opt_payload" "$curl_auth" "$i_endpoint"
    fi
  fi
}

_notify_email() {
  if [ -z "$opt_status" ]; then
    case "$current_script_section" in
      onStart | onExecute )
        opt_status="processing"
        ;;
      onSuccess )
        opt_status="success"
        ;;
      onFailure )
        opt_status="failed"
        ;;
      onComplete )
        if [ "$is_success" == "true" ]; then
          opt_status="success"
        else
          opt_status="failed"
        fi
        ;;
      *)
        echo "Error: unable to determine status in section $current_script_section" >&2
        exit 99
        ;;
    esac
  fi

  if [ ! ${#opt_recipients[@]} -gt 0 ]; then
    echo "Error: missing recipients. At least one recipient is required." >&2
    exit 99
  fi
  export json_recipients=$(printf '%s\n' "${opt_recipients[@]}" | jq -R . | jq -s .)

  local tmp_attachments=$step_tmp_dir/attachments.json
  echo -n "[]" > $tmp_attachments
  if [ ${#opt_attachments[@]} -gt 0 ]; then
    local totalSizeInBytes=0
    echo -n "[" > $tmp_attachments
    for item in ${opt_attachments[@]}; do
      if [ ! -f "$item" ]; then
        echo "Attachment $item is not a file" >&2
        continue
      elif [ type wc >/dev/null 2>&1 ]; then
        echo "Unable to determine file size." >&2
      else
        totalSizeInBytes=$(($totalSizeInBytes + $(wc --bytes < $item)))
      fi
      local fileName=$(basename "$item")
      echo "Attaching file: $fileName"
      echo -n "{\"fileName\":\"$fileName\",\"contents\":\"" >> $tmp_attachments
      base64 $item >> $tmp_attachments
      echo -n "\"}" >> $tmp_attachments
      if [ "$item" != "${opt_attachments[-1]}" ]; then
        echo -n "," >> $tmp_attachments
      fi
    done
    if [ "$totalSizeInBytes" -gt "5000000" ]; then
      echo "Combined attachment size cannot exceed 5MB. Skipping attachments" >&2
      echo -n "[]" > $tmp_attachments
    else
      echo -n "]" >> $tmp_attachments
    fi
  fi

  local i_id=$(eval echo "$"int_"$i_name"_id)
  local curl_auth="-H Authorization:'apiToken $builder_api_token'"
  local default_email_payload="{\"stepletId\":\"\${steplet_id}\",\"status\":\"\${opt_status}\",\"recipients\":\${json_recipients},\"attachLogs\":\${opt_attach_logs}, \"showFailingCommands\":\${opt_show_failing_commands},\"subject\":\"\${opt_subject}\",\"body\":\"\${opt_body}\",\"attachments\":"

  local opt_payload=$step_tmp_dir/payload.json

  echo $default_email_payload > $opt_payload
  replace_envs $opt_payload
  cat $tmp_attachments >> $opt_payload
  echo -n "}" >> $opt_payload

  full_url="${shippable_api_url}/projectIntegrations/${i_id}/sendEmail"
  _post_curl "$opt_payload" "$curl_auth" "$full_url"
}

_notify_newrelic() {
  local curl_auth=""
  local appId=""
  local r_endpoint=""
  local default_post_deployment_payload="{\"\${opt_type}\":{\"revision\":\"\${opt_revision}\",\"description\":\"\${opt_description}\",\"user\":\"\${opt_username}\",\"changelog\":\"\${opt_changelog}\"}}"
  local default_get_appid_payload="--data-urlencode 'filter[name]=$opt_appName' -d 'exclude_links=true'"
  local default_get_payload=""
  local default_post_payload=""
  local i_authorization=$(cat "$step_json_path" | jq -r ."integrations.$i_name.token")

  if [ -n "$i_authorization" ]; then
    curl_auth="-H X-Api-Key:'$i_authorization'"
  fi

  local i_url=$(cat "$step_json_path" | jq -r ."integrations.$i_name.url")

  if [ -z "$i_url" ]; then
    echo "Error: no url found in resource $i_name" >&2
    exit 99
  fi

  if [ -z "$opt_appId" ] && [ -z "$opt_appName" ]; then
    echo "Error: --appId or --appName should be present in send_notification" >&2
    exit 99
  fi
  # get the appId from the appName by making a get request to newrelic, if appId is not present
  appId="$opt_appId"
  if [ -z "$appId" ]; then
    r_endpoint="$i_url/applications.json"
    default_get_payload="$default_get_appid_payload"
    local applications=$(_get_curl "$default_get_payload" "$curl_auth" "$r_endpoint")
    appId=$(echo $applications | jq ".applications[0].id // empty")
  fi

  # record the deployment
  if [ -z "$appId" ]; then
    echo "Error: Unable to find an application on NewRelic" >&2
    exit 99
  fi
  r_endpoint="$i_url/applications/$appId/deployments.json"
  default_post_payload="$default_post_deployment_payload"

  if [ -n "$opt_payload" ]; then
    if [ ! -f $opt_payload ]; then
      echo "Error: file not found at path: $opt_payload" >&2
      exit 99
    fi
    local isValid=$(jq type $opt_payload || true)
    if [ -z "$isValid" ]; then
      echo "Error: payload is not valid JSON" >&2
      exit 99
    fi
    echo "Recording deployments on NewRelic for appID: $appId"

    local deployment=$(_post_curl "$opt_payload" "$curl_auth" "$r_endpoint")
    local deploymentId=$(echo $deployment | jq ".deployment.id")
    if [ -z "$deploymentId" ]; then
      echo "Error: $deployment" >&2
      exit 99
    else
      echo "Deployment Id: $deploymentId"
    fi
  else
    if [ -z "$opt_type" ]; then
      echo "Error: --type is missing in send_notification" >&2
      exit 99
    fi
    if [ -z "$opt_revision" ]; then
      echo "Error: --revision is missing in send_notification" >&2
      exit 99
    fi
    echo $default_post_payload > /tmp/payload.json
    opt_payload=/tmp/payload.json
    replace_envs $opt_payload
    local isValid=$(jq type $opt_payload || true)
    if [ -z "$isValid" ]; then
      echo "Error: payload is not valid JSON" >&2
      exit 99
    fi
    echo "Recording deployments on NewRelic for appID: $appId"

    local deployment=$(_post_curl "$opt_payload" "$curl_auth" "$r_endpoint")
    local deploymentId=$(echo $deployment | jq ".deployment.id")
    if [ -z "$deploymentId" ]; then
      echo "Error: $deployment" >&2
      exit 99
    else
      echo "Deployment Id: $deploymentId"
    fi
  fi
}

_notify_airbrake() {
  local curl_auth=""
  local obj_type=""
  local project_id="${opt_project_id}"
  local i_endpoint=$(cat "$step_json_path" | jq -r ."integrations.$i_name.url")
  local i_token=$(cat "$step_json_path" | jq -r ."integrations.$i_name.token")

  local default_airbrake_payload="{\"environment\":\"\${opt_environment}\",\"username\":\"\${opt_username}\",\"email\":\"\${opt_email}\",\"repository\":\"\${opt_repository}\",\"revision\":\"\${opt_revision}\",\"version\":\"\${opt_version}\"}"

  if [ -z "$opt_type" ]; then
    echo "Error: --type is missing in send_notification" >&2
    exit 99
  fi
  if [ "$opt_type" == "deploy" ]; then
    obj_type="deploys"
  else
    echo "Error: unsupported type value $opt_type" >&2
    exit 99
  fi

  if [ -z "$project_id" ]; then
    echo "Error: missing project ID, --project-id is required for Airbrake" >&2
    exit 99
  fi

  i_endpoint="${i_endpoint%/}"
  i_endpoint="${i_endpoint}/projects/${project_id}/${obj_type}?key=${i_token}"

  if [ -n "$opt_payload" ]; then
    if [ ! -f $opt_payload ]; then
      echo "Error: file not found at path: $opt_payload" >&2
      exit 99
    fi
  else
    echo $default_airbrake_payload > /tmp/payload.json
    opt_payload=/tmp/payload.json
    replace_envs $opt_payload
  fi

  local isValid=$(jq type $opt_payload || true)
  if [ -z "$isValid" ]; then
    echo "Error: payload is not valid JSON" >&2
    exit 99
  fi

  echo "Requesting Airbrake project: $project_id"

  _post_curl "$opt_payload" "$curl_auth" "$i_endpoint"
}

_notify_jira() {
  local i_username=$(cat "$step_json_path" | jq -r ."integrations.$i_name.username")
  local i_endpoint=$(cat "$step_json_path" | jq -r ."integrations.$i_name.url")
  local i_token=$(cat "$step_json_path" | jq -r ."integrations.$i_name.token")
  local default_v2_payload="{\"fields\":{\"project\":{\"key\":\"\${opt_project_id}\"},\"summary\":\"\${opt_summary}\",\"description\":\"\${opt_description}\",\"issuetype\":{\"name\":\"\${opt_type}\"}}}"
  local default_v3_payload="{\"fields\":{\"project\":{\"id\":\"\${project_key_id}\"},\"summary\":\"\${opt_summary}\",\"description\":{\"type\":\"doc\",\"version\":1,\"content\":[{\"type\":\"paragraph\",\"content\":[{\"text\":\"\${opt_description}\",\"type\":\"text\"}]}]},\"issuetype\":{\"id\":\"\${type_id}\"}}}"

  if [ -z "$(which base64)" ]; then
    echo "Error: base64 utility is not present, but is required for Jira authorization" >&2
    exit 99
  fi
  if [ -z "$i_endpoint" ]; then
    echo "Error: missing endpoint. Please check your integration." >&2
    exit 99
  fi
  if [ -z "$i_token" ]; then
    echo "Error: missing token. Please check your integration." >&2
    exit 99
  fi
  if [ -z "$i_username" ]; then
    echo "Error: missing username. Please check your integration." >&2
    exit 99
  fi
  if [ -z "$opt_project_id" ]; then
    echo "Error: missing project identifier. Please use --project-id." >&2
    exit 99
  fi
  if [ -z "$opt_type" ]; then
    echo "Error: missing issue type. Please use --type." >&2
    exit 99
  fi
  if [ -z "$opt_summary" ]; then
    echo "Error: missing summary. Please use --summary." >&2
    exit 99
  fi

  local encoded_auth=$(echo -n "$i_username:$i_token" | base64)
  local split_endpoint=(${i_endpoint//\// })
  last_item=${split_endpoint[-1]}
  opt_payload=/tmp/payload.json

  case $last_item in
    2)
      echo $default_v2_payload > $opt_payload
      ;;
    3)
      echo $default_v3_payload > $opt_payload
      issue_meta=$(curl -XGET -s \
        -H "Content-Type: application/json" \
        -H "Authorization: Basic $encoded_auth" \
        "$i_endpoint/issue/createmeta")
      export project_key_id=$(jq -r ".projects[] | select(.key==\"$opt_project_id\") | .id  " <<<$issue_meta)
      if [ -z "$project_key_id" ]; then
        echo "Error: unable to determine project ID from provided key: $opt_project_id"
        exit 99
      fi
      export type_id=$(jq -r ".projects[].issuetypes[] | select(.name==\"$opt_type\") | .id  " <<<$issue_meta)
      if [ -z "$type_id" ]; then
        echo "Error: unable to determine issue type ID from provided type name: $opt_type"
        exit 99
      fi
      ;;
    *)
      echo "Error: Jira integration url must be 'https://<domain>/rest/api/2' or 'https://<domain>/rest/api/3'"
      exit 99
  esac

  replace_envs $opt_payload

  local isValid=$(jq type $opt_payload || true)
  if [ -z "$isValid" ]; then
    echo "Error: payload is not valid JSON" >&2
    exit 99
  fi

  result=$(curl -XPOST -sS \
    -H "Content-Type: application/json" \
    -H "Authorization: Basic $encoded_auth" \
    "$i_endpoint/issue" \
    -d @$opt_payload)
  echo $result

  if [ -n "$opt_attach_file" ]; then
    if [ -f "$opt_attach_file" ]; then

      issueKey=$(jq -r '.key' <<< $result)
      curl -sS -XPOST \
        -H "X-Atlassian-Token: nocheck" \
        -H "Authorization: Basic $encoded_auth" \
        -F "file=@$opt_attach_file" \
        "$i_endpoint/issue/$issueKey/attachments"
    else
      echo "Error: --attach-file option refers to a file that doesn't exist" >&2
      exit 99
    fi
  fi
}

_post_curl() {
  local payload=$1
  local auth=$2
  local endpoint=$3

  local curl_cmd="curl -XPOST -sS -H content-type:'application/json' $auth $endpoint -d @$payload"
  eval $curl_cmd
  echo ""
}

_get_curl() {
  local payload=$1
  local auth=$2
  local endpoint=$3

  local curl_cmd="curl -s $auth $endpoint $payload"
  eval $curl_cmd
  echo ""
}

replace_envs() {
  local temp_dest=/tmp/shippable/replace_envs
  mkdir -p $temp_dest
  for file in "$@"; do
    local path
    path=$(dirname "$file")
    if [ -d "$file" ]; then
      echo "replace_envs is not supported for directories" >&2
      return 82
    fi
    if [ "$path" != '.' ]; then
      mkdir -p "$temp_dest/$path"
    fi
    envsubst < "$file" > "$temp_dest/$file"
    mv "$temp_dest/$file" "$file"
  done
}

write_output() {
  if [ "$1" == "" ] || [ "$2" == "" ]; then
    echo "Usage: write_output RESOURCE_NAME VALUES"
    exit 99
  fi

  local resource_name=$1
  shift

  local resource_directory=$(cat "$step_json_path" | jq -r ."resources.$resource_name.resourcePath")

  if [ -z "$resource_directory" ]; then
    echo "Error: resource data not found for $resource_name" >&2
    exit 99
  fi

  local env_file_path="$resource_directory/$resource_name.env"

  if [ ! -f "$env_file_path" ]; then
    echo "Creating .env file $env_file_path"
    touch $env_file_path
  fi

  while [ $# -gt 0 ]; do
    if [[ "$1" == *=* ]]; then
      echo "$1" >> $env_file_path
    else
      echo "$1 is not a valid key-value pair."
      echo "Please make sure the key and value are separated by an =."
    fi
    shift
  done
}

retry_command() {
  for i in $(seq 1 3);
  do
    {
      "$@"
      ret=$?
      [ $ret -eq 0 ] && break;
    } || {
      echo "retrying $i of 3 times..."
    }
  done
  return $ret
}

switch_env() {
  if [[ $# -le 0 ]]; then
    echo "Usage: switch_env LANGUAGE [VERSION] [OPTIONS]" >&2
    exit 99
  fi

  local language="$1"
  shift

  local optional_jdk=""
  local optional_bundler=""
  local version=""

  while [ $# -gt 0 ]; do
    case $1 in
      --jdk)
        optional_jdk="$2"
        shift
        shift
        ;;
      --bundler)
        optional_bundler="$2"
        shift
        shift
        ;;
      *)
        if [ -z "$version" ]; then
          version=$1
          shift
        else
          echo "Unrecognized option $1" >&2
          exit 1
        fi
        ;;
    esac
  done

  if [ ! -z "$optional_jdk" ]; then
    _set_jdk $optional_jdk
  fi

  if [ "$language" == "java" ]; then
    _set_jdk $version
  elif [ "$language" == "go" ]; then
    _set_go $version
  elif [ "$language" == "python" ]; then
    _set_python "$version"
  elif [ "$language" == "nodejs" ]; then
    _set_nodejs "$version"
  elif [ "$language" == "ruby" ]; then
    _set_ruby "$version" "$optional_jdk" "$optional_bundler"
  elif [ "$language" == "php" ]; then
    _set_php "$version"
  elif [ "$language" == "scala" ]; then
    _set_scala "$version"
  elif [ "$language" == "clojure" ]; then
    _set_clojure "$version"
  elif [ "$language" == "c" ]; then
    _set_c "$version"
  elif [ "$language" == "none" ]; then
    echo "Skipping version setup for language: none" >&2
  else
    echo "Error: unsupported language: $language" >&2
    exit 99
  fi
}

_export_java_path() {
  directory=$1;
  if [ -d "$directory" ]; then
    export JAVA_HOME="$directory";
    export PATH="$PATH:$directory/bin";
  else
    echo "$2 is not supported on this image" >&2
    exit 99
  fi
}

_set_java_path() {
  java_path=$1
  if [ -f $java_path ]; then
    sudo update-alternatives --set java $java_path
  else
    echo "$2 is not supported on this image" >&2
    exit 99
  fi
}

_set_javac_path() {
  javac_path=$1
  if [ -f $javac_path ]; then
    sudo update-alternatives --set javac $javac_path
  else
    echo "$2 is not supported on this image" >&2
    exit 99
  fi
}

_set_jdk() {
  local jdk_version=$1
  if [ "$jdk_version" == "" ]; then
    echo "Usage: switch_env java openjdk9" >&2
    exit 1
  fi

  if [ "$jdk_version" == "openjdk7" ]; then
    _export_java_path "/usr/lib/jvm/java-7-openjdk-amd64" "$jdk_version";
    _set_java_path "/usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java" "$jdk_version";
    _set_javac_path "/usr/lib/jvm/java-7-openjdk-amd64/bin/javac" "$jdk_version";
  elif [ "$jdk_version" == "openjdk8" ]; then
    _export_java_path "/usr/lib/jvm/java-8-openjdk-amd64" "$jdk_version";
    _set_java_path "/usr/lib/jvm/java-8-openjdk-amd64/bin/java" "$jdk_version";
    _set_javac_path "/usr/lib/jvm/java-8-openjdk-amd64/bin/javac" "$jdk_version";
  elif [ "$jdk_version" == "openjdk9" ]; then
    _export_java_path "/usr/lib/jvm/java-9-openjdk-amd64" "$jdk_version";
    _set_java_path "/usr/lib/jvm/java-9-openjdk-amd64/bin/java" "$jdk_version";
    _set_javac_path "/usr/lib/jvm/java-9-openjdk-amd64/bin/javac" "$jdk_version";
  elif [ "$jdk_version" == "openjdk10" ]; then
    _export_java_path "/usr/lib/jvm/java-10-openjdk-amd64" "$jdk_version";
    _set_java_path "/usr/lib/jvm/java-10-openjdk-amd64/bin/java" "$jdk_version";
    _set_javac_path "/usr/lib/jvm/java-10-openjdk-amd64/bin/javac" "$jdk_version";
  elif [ "$jdk_version" == "openjdk11" ]; then
    _export_java_path "/usr/lib/jvm/java-11-openjdk-amd64" "$jdk_version";
    _set_java_path "/usr/lib/jvm/java-11-openjdk-amd64/bin/java" "$jdk_version";
    _set_javac_path "/usr/lib/jvm/java-11-openjdk-amd64/bin/javac" "$jdk_version";
  elif [ "$jdk_version" == "oraclejdk7" ]; then
    _export_java_path "/usr/lib/jvm/java-7-oracle" "$jdk_version";
    _set_java_path "/usr/lib/jvm/java-7-oracle/jre/bin/java" "$jdk_version";
    _set_javac_path "/usr/lib/jvm/java-7-oracle/bin/javac" "$jdk_version";
  elif [ "$jdk_version" == "oraclejdk8" ]; then
    _export_java_path "/usr/lib/jvm/java-8-oracle" "$jdk_version";
    _set_java_path "/usr/lib/jvm/java-8-oracle/jre/bin/java" "$jdk_version";
    _set_javac_path "/usr/lib/jvm/java-8-oracle/bin/javac" "$jdk_version";
  elif [ "$jdk_version" == "oraclejdk9" ]; then
    _export_java_path "/usr/lib/jvm/java-9-oracle" "$jdk_version";
    _set_java_path "/usr/lib/jvm/java-9-oracle/bin/java" "$jdk_version";
    _set_javac_path "/usr/lib/jvm/java-9-oracle/bin/javac" "$jdk_version";
  elif [ "$jdk_version" == "oraclejdk10" ]; then
    _export_java_path "/usr/lib/jvm/java-10-oracle" "$jdk_version";
    _set_java_path "/usr/lib/jvm/java-10-oracle/bin/java" "$jdk_version";
    _set_javac_path "/usr/lib/jvm/java-10-oracle/bin/javac" "$jdk_version";
  elif [ "$jdk_version" == "oraclejdk11" ]; then
    export_java_path "/usr/lib/jvm/java-11-oraclejdk-amd64" "$jdk_version";
    _set_java_path "/usr/lib/jvm/java-11-oraclejdk-amd64/bin/java" "$jdk_version";
    _set_javac_path "/usr/lib/jvm/java-11-oraclejdk-amd64/bin/javac" "$jdk_version";
  else
    echo "The version of the JDK you are trying to use is not supported. The supported versions include openjdk7, openjdk8, openjdk9, openjdk10, openjdk11, oraclejdk8, oraclejdk9, oraclejdk10, and oraclejdk11." >&2
    exit 99
  fi

  java -version
}

_set_go() {
  local go_version=$1
  if [ "$go_version" == "" ]; then
    echo "Usage: switch_env go 1.11.5" >&2
    exit 1
  fi

  mkdir -p $HOME
  export GOPATH=$HOME
  export PATH=$PATH:$GOPATH/bin

  . $HOME/.gvm/scripts/gvm;
  local version_installed=false
  for local_version in $(gvm list); do
    if [[ $local_version =~ ^go([0-9]).([0-9]) ]] && [[ $local_version == "go$go_version" ]]; then
      version_installed=true
      break
    fi
  done

  if [ $version_installed == true ]; then
    gvm use go$go_version;
  else
    gvm install go$go_version --prefer-binary;
    gvm use go$go_version;
  fi

  export GOPATH=$HOME
  go env
}

_set_python() {
  local python_version=$1
  if [ "$python_version" == "" ]; then
    echo "Usage: switch_env python 3.7" >&2
    exit 1
  fi

  local ve_dir="$HOME/venv/$python_version";
  local python_path=""

  if [ "$python_version" == "pypy" ]; then
    python_path="/usr/local/bin/pypy"
  elif [ "$python_version" == "pypy3" ]; then
    python_path="/usr/local/bin/pypy3"
  else
    python_path="/usr/bin/python$python_version"
  fi

  if [ ! -f "$python_path" ]; then
    echo "Python version $python_version not found at $python_path" >&2
    exit 99
  fi

  if [ ! -f "$ve_dir/bin/activate" ]; then
    virtualenv -p $python_path $ve_dir
    virtualenv_result=$?
    [ "$virtualenv_result" != 0 ] && return $virtualenv_result;
  else
    echo "Existing python virtual environment found at $ve_dir"
  fi

  source $ve_dir/bin/activate
  python --version
  pip --version
}

_set_nodejs() {
  local nodejs_version=$1
  if [ "$nodejs_version" == "" ]; then
    echo "Usage: switch_env nodejs 11.6.0" >&2
    exit 1
  fi

  nvm install "$nodejs_version"
  nvm use "$nodejs_version"
  node --version
}

_set_ruby() {
  local ruby_version=$1
  local jdk_version=$2
  local bundler_version="1.17.3"

  if [ ! -z "$3" ]; then
    bundler_version="$3"
  fi

  if [ "$ruby_version" == "" ]; then
    echo "Usage: switch_env ruby 3.7 [--bundler 1.17.3 --jdk openjdk9]" >&2
    exit 1
  fi

  local rvm_path=/usr/local/rvm

  if [ ! -f $rvm_path/scripts/rvm ]; then
    curl -L https://get.rvm.io | bash;
  fi

  . $rvm_path/scripts/rvm;

  if [[ "$ruby_version" == *rbx* ]]; then
    ## RBX installation ##
    if [[ "$ruby_version" == "rbx-2" ]]; then
      ## install the latest rbx binary
      rvm use rbx-2 --install --binary --fuzzy;
    else
      ## install the specified rbx binary
      rvm use $ruby_version --install --binary --fuzzy;
    fi
  elif [[ "$ruby_version" == *jruby* ]]; then
    ## JRUBY installation ##
    java -version
    JRUBY_OPTS="--server -Xcompile.invokedynamic=false";
    if [[ "$ruby_version" == "jruby-head" ]]; then
      if [ "$jdk_version" == "" ]; then
        echo "A JDK version is required for $ruby_version." >&2
        echo "Usage: switch_env ruby $ruby_version --jdk openjdk9" >&2
        exit 1
      fi
      ## Installs "jruby-head" ##
      rvm install jruby-head -n $jdk_version --create;
      rvm use jruby-head-$jdk_version --create;
    else
      if [[ "$ruby_version" =~ ^jruby-([0-9])([0-9])mode$ ]]; then
        ## installs "jruby-a.bmode" ##
        ### BASH_REMATCH values have to be stored explicitly here
        ### because they change inside following commands
        jruby_major_version=${BASH_REMATCH[1]};
        jruby_minor_version=${BASH_REMATCH[2]};
        rvm install jruby;
        rvm use jruby --create;
        export JRUBY_MODE_VERSION="$jruby_major_version.$jruby_minor_version";
        export JRUBY_OPTS="$JRUBY_OPTS --$JRUBY_MODE_VERSION";

        . $rvm_path/scripts/rvm;
        rvm use jruby
      else
        ## Installs "jruby-a.b.cd" or "jruby" ##
        rvm use $ruby_version --install --binary --fuzzy;
      fi
    fi
  elif [[ "$ruby_version" == "ruby-head" ]]; then
    ## ruby head, reinstall each time
    rvm remove ruby-head --gems --fuzzy;
    rvm reinstall $ruby_version --binary --verify-downloads 1;
    . $HOME/.bashrc && . $rvm_path/scripts/rvm && rvm use $ruby_version;
  else
    ## Regular RUBY installation ##
    rvm install $ruby_version --verify-downloads 1;
    . $HOME/.bashrc && . $rvm_path/scripts/rvm && rvm use $ruby_version;
  fi

  rvm autolibs disable;
  rvm ls;

  local gem_version=$(gem --version)
  local gem_version_major=$(echo $gem_version | awk '{split($0, a, "."); print a[1]}')
  local gem_install_cmd=""

  if [ $gem_version_major -gt 2 ]; then
    gem_install_cmd="gem install bundler --no-document --version $bundler_version"
  else
    gem_install_cmd="gem install bundler --no-ri --no-rdoc --version $bundler_version"
  fi

  $gem_install_cmd;
  bundle --version;
  ruby -v;
  gem --version;
}

_set_php() {
  local php_version=$1
  if [ "$php_version" == "" ]; then
    echo "Usage: switch_env php 7.3.1" >&2
    exit 1
  fi

  export PATH=$HOME/.phpenv/bin:$HOME/.phpenv/extensions:$PATH;

  if [ ! -d "$HOME/.phpenv/versions/$php_version" ]; then
    /usr/local/bin/phpenv-install "$php_version"
  fi

  eval "$(phpenv init -)"
  $HOME/.phpenv/bin/phpenv global "$php_version"

  php --version
}

_set_scala() {
  local scala_version=$1
  if [ ! -z "$scala_version" ]; then
    echo "The Scala version cannot be changed.  Select a different image." >&2
    exit 1
  fi
  java -version
}

_set_clojure() {
  local clojure_version=$1
  if [ ! -z "$clojure_version" ]; then
    echo "The lien version cannot be changed.  Select a different image." >&2
    exit 1
  fi
  lein version
}

_set_c() {
  local c_version=$1
  if [ ! -z "$c_version" ]; then
    echo "The gcc and clang versions cannot be changed.  Select a different image." >&2
    exit 1
  fi
  gcc --version
  clang --version
}

save_tests() {
  local source_file="$1"
  local reports_size_limit_mb=5

  if [ "$source_file" == "" ]; then
    echo "Usage: save_tests [DIRECTORY] [FILE]" >&2
    exit 1
  fi

  if [ ! -z "$REPORTS_SIZE_LIMIT_MB" ]; then
    reports_size_limit_mb=$REPORTS_SIZE_LIMIT_MB
  fi

  if [ ! -f $source_file ] && [ ! -d $source_file ]; then
    echo "$source_file is not a file or directory." >&2
    exit 99
  fi

  if [ -d $source_file ] && [ -z "$(ls -A $source_file)" ]; then
    echo "$source_file is an empty directory."
    return 0
  fi

  echo "Copying test reports"
  local output_directory=$step_workspace_dir/upload/tests/$step_id
  mkdir -p $output_directory

  local test_reports_size_kb=$(du -s $source_file | awk '{print $1}')
  local test_reports_size_limit_kb=$(($reports_size_limit_mb * 1024))

  if [ $test_reports_size_kb -gt $test_reports_size_limit_kb ]; then
    echo "Test reports size exceeds limit"
    echo "Test Reports size: $test_reports_size_kb KB, Max size: $test_reports_size_limit_kb KB"
    return 1
  else
    echo "Test reports size: $test_reports_size_kb KB"
    cp -r $source_file $output_directory
  fi
}

cache_files() {
  if [ "$1" == "" ] || [ "$2" == "" ]; then
    echo "Usage: cache_files [DIRECTORY] [FILE] NAME" >&2
    exit 1
  fi
  # Wildcards will be expanded.  The last item is the name.
  local source_files=( "$@" )
  local cache_name="${!#}"
  unset "source_files[${#source_files[@]}-1]"

  local pattern=" |'"
  if [[ $cache_name =~ $pattern ]]; then
    echo "Cache name may not contain spaces."
    exit 1
  fi

  echo "Copying files for cache"
  local output_directory=$step_workspace_dir/upload/cache
  if [ "${#source_files[@]}" -gt 1 ]; then
    mkdir -p "$output_directory/$cache_name"
    for filepath in "${source_files[@]}"; do
      cp -r "$filepath" "$output_directory/$cache_name/$filepath"
    done
  else
    mkdir -p "$output_directory"
    cp -r "$source_files" "$output_directory/$cache_name"
  fi
  echo "Files copied"
}

restore_cache() {
  if [ "$1" == "" ] || [ "$2" == "" ]; then
    echo "Usage: restore_cache NAME PATH" >&2
    exit 1
  fi

  local cache_name="$1"
  local restore_path="$2"
  local cache_location="$step_workspace_dir/download/cache/$cache_name"

  local pattern=" |'"
  if [[ $cache_name =~ $pattern ]]; then
    echo "Cache name may not contain spaces."
    exit 1
  fi

  if [ ! -d $cache_location ] && [ ! -f $cache_location ]; then
    echo "No cache found for $cache_name."
    return 0
  fi

  echo "Restoring cache files"
  if [ -d "$cache_location" ]; then
    mkdir -p "$restore_path"
    cp -r "$cache_location/." "$restore_path"
  elif [ -f "$cache_location" ]; then
    mkdir -p "$(dirname $cache_location)"
    cp "$cache_location" "$restore_path"
  fi
  echo "Files restored"
}

add_run_variable() {
  if [ "$1" == "" ]; then
    echo "Usage: add_run_variable KEY=VALUE" >&2
    exit 1
  fi

  local env_file_path="$run_dir/workspace/run.env"

  if [ ! -f "$env_file_path" ]; then
    echo "Creating .env file $env_file_path"
    touch $env_file_path
  fi

  while [ $# -gt 0 ]; do
    if [[ "$1" == *=* ]]; then
      export $1
      echo "export $1" >> $env_file_path
    else
      echo "$1 is not valid."
      echo "Please make sure the key and value are separated by an =."
    fi
    shift
  done
}

add_pipeline_variable() {
  if [ "$1" == "" ]; then
    echo "Usage: add_pipeline_variable KEY=VALUE" >&2
    exit 1
  fi

  local env_file_path="$pipeline_workspace_dir/pipeline.env"

  if [ ! -f "$env_file_path" ]; then
    echo "Creating .env file $env_file_path"
    touch $env_file_path
  fi

  while [ $# -gt 0 ]; do
    if [[ "$1" == *=* ]]; then
      export $1
      echo "export $1" >> $env_file_path
    else
      echo "$1 is not valid."
      echo "Please make sure the key and value are separated by an =."
    fi
    shift
  done
}

export_run_variables() {
  if [ -f $run_dir/workspace/run.env ]; then
    source $run_dir/workspace/run.env
  fi
}

export_pipeline_variables() {
  if [ -f $pipeline_workspace_dir/pipeline.env ]; then
    source $pipeline_workspace_dir/pipeline.env
  fi
}

save_run_state() {
  if [ "$1" == "" ] || [ "$2" == "" ]; then
    echo "Usage: save_run_state [DIRECTORY] [FILE] NAME" >&2
    exit 1
  fi
  # Wildcards will be expanded.  The last item is the name.
  local source_files=( "$@" )
  local cache_name="${!#}"
  unset "source_files[${#source_files[@]}-1]"

  local pattern=" |'"
  if [[ $cache_name =~ $pattern ]]; then
    echo "Name may not contain spaces."
    exit 1
  fi

  if [[ "$cache_name" == "run.env" ]]; then
    echo "The name may not be run.env."
    exit 1
  fi

  echo "Copying files to state"
  local output_directory=$run_dir/workspace
  if [ "${#source_files[@]}" -gt 1 ]; then
    mkdir -p "$output_directory/$cache_name"
    for filepath in "${source_files[@]}"; do
      cp -r "$filepath" "$output_directory/$cache_name/$filepath"
    done
  else
    mkdir -p "$output_directory"
    cp -r "$source_files" "$output_directory/$cache_name"
  fi
  echo "Files copied"
}

restore_run_state() {
  if [ "$1" == "" ] || [ "$2" == "" ]; then
    echo "Usage: restore_run_state NAME PATH" >&2
    exit 1
  fi

  local cache_name="$1"
  local restore_path="$2"
  local cache_location="$run_dir/workspace/$cache_name"

  local pattern=" |'"
  if [[ $cache_name =~ $pattern ]]; then
    echo "Name may not contain spaces."
    exit 1
  fi

  if [ ! -d $cache_location ] && [ ! -f $cache_location ]; then
    echo "No state found for $cache_name."
    return 0
  fi

  echo "Restoring state files"
  if [ -d "$cache_location" ]; then
    mkdir -p "$restore_path"
    cp -r "$cache_location/." "$restore_path"
  elif [ -f "$cache_location" ]; then
    mkdir -p "$(dirname $cache_location)"
    cp "$cache_location" "$restore_path"
  fi
  echo "Files restored"
}

save_pipeline_state() {
  if [ "$1" == "" ] || [ "$2" == "" ]; then
    echo "Usage: save_pipeline_state [DIRECTORY] [FILE] NAME" >&2
    exit 1
  fi

  # Wildcards will be expanded.  The last item is the name.
  local source_files=( "$@" )
  local cache_name="${!#}"
  unset "source_files[${#source_files[@]}-1]"

  local pattern=" |'"
  if [[ $cache_name =~ $pattern ]]; then
    echo "Name may not contain spaces."
    exit 1
  fi

  if [[ "$cache_name" == "pipeline.env" ]]; then
    echo "The name may not be pipeline.env."
    exit 1
  fi

  echo "Copying files to state"
  local output_directory=$pipeline_workspace_dir
  if [ "${#source_files[@]}" -gt 1 ]; then
    mkdir -p "$output_directory/$cache_name"
    for filepath in "${source_files[@]}"; do
      cp -r "$filepath" "$output_directory/$cache_name/$filepath"
    done
  else
    mkdir -p "$output_directory"
    cp -r "$source_files" "$output_directory/$cache_name"
  fi
  echo "Files copied"
}

restore_pipeline_state() {
  if [ "$1" == "" ] || [ "$2" == "" ]; then
    echo "Usage: restore_pipeline_state NAME PATH" >&2
    exit 1
  fi

  local cache_name="$1"
  local restore_path="$2"
  local cache_location="$pipeline_workspace_dir/$cache_name"

  local pattern=" |'"
  if [[ $cache_name =~ $pattern ]]; then
    echo "Name may not contain spaces."
    exit 1
  fi

  if [ ! -d $cache_location ] && [ ! -f $cache_location ]; then
    echo "No state found for $cache_name."
    return 0
  fi

  echo "Restoring state files"
  if [ -d "$cache_location" ]; then
    mkdir -p "$restore_path"
    cp -r "$cache_location/." "$restore_path"
  elif [ -f "$cache_location" ]; then
    mkdir -p "$(dirname $cache_location)"
    cp "$cache_location" "$restore_path"
  fi
  echo "Files restored"
}

start_group() {
  # First argument is the name of the group
  # Second argument is whether the group should be visible or not
  if [ -z "$1" ]; then
    echo "Error: missing group name as first argument." >&2
  fi
  local group_name=$1
  local is_shown=true
  if [ ! -z "$2" ]; then
    is_shown=$2
  fi
  # if there are already 2 groups open, force close one before starting a new one
  # this prevents repeated nesting
  if [ "${#open_group_list[@]}" -gt 1 ]; then
    stop_group
  fi
  # TODO: use shipctl to compute this
  local group_uuid=$(cat /proc/sys/kernel/random/uuid)
  # set up this group's name
  local sanitizedName=$(echo "$group_name" | sed s/[^a-zA-Z0-9_]/_/g)
  if [[ "$sanitizedName" =~ ^[0-9] ]]; then
    sanitizedName="_"$sanitizedName
  fi
  # if at least one group is already open, use it as a parentConsoleId
  local parent_uuid=""
  if [ "${#open_group_list[@]}" -gt 0 ]; then
    #look at the most recent group, and find its UUID
    local last_element="${open_group_list[-1]}"
    parent_uuid="${open_group_info[${last_element}_uuid]}"
  else
    parent_uuid="root"
  fi
  local group_start_timestamp=`date +"%s"`
  echo ""
  echo "__SH__GROUP__START__|{\"type\":\"grp\",\"sequenceNumber\":\"$group_start_timestamp\",\"id\":\"$group_uuid\",\"is_shown\":\"$is_shown\",\"parentConsoleId\":\"$parent_uuid\"}|$group_name"

  # add info to the global associative array
  open_group_list+=("$sanitizedName")
  open_group_info[${sanitizedName}_shown]="$is_shown"
  open_group_info[${sanitizedName}_uuid]="$group_uuid"
  open_group_info[${sanitizedName}_name]="$group_name"
  open_group_info[${sanitizedName}_parent_uuid]="$parent_uuid"
  open_group_info[${sanitizedName}_status]=0
}

stop_group() {

  if [ "${#open_group_list[@]}" -lt 1 ]; then
    return
  fi
  # stop the most recently started group.
  local sanitizedName="${open_group_list[-1]}"
  local group_uuid="${open_group_info[${sanitizedName}_uuid]}"
  local parent_uuid="${open_group_info[${sanitizedName}_parent_uuid]}"
  local is_shown="${open_group_info[${sanitizedName}_shown]}"
  local group_status="${open_group_info[${sanitizedName}_status]}"
  local group_name="${open_group_info[${sanitizedName}_name]}"

  group_end_timestamp=`date +"%s"`
  echo "__SH__GROUP__END__|{\"type\":\"grp\",\"sequenceNumber\":\"$group_end_timestamp\",\"id\":\"$group_uuid\",\"is_shown\":\"$is_shown\",\"exitcode\":\"$group_status\",\"parentConsoleId\":\"$parent_uuid\"}|$group_name"

  # remove the group info from the global associative array
  unset open_group_info[${sanitizedName}_uuid]
  unset open_group_info[${sanitizedName}_parent_uuid]
  unset open_group_info[${sanitizedName}_shown]
  unset open_group_info[${sanitizedName}_status]
  unset open_group_info[${sanitizedName}_name]
  unset 'open_group_list[${#open_group_list[@]}-1]'
}

execute_command() {
  local retry_cmd=false
  if [ "$1" == "--retry" ]; then
    retry_cmd=true
    shift
  fi
  cmd="$@"
  if [ "${#open_group_list[@]}" -gt 0 ]; then
    local sanitizedName="${open_group_list[-1]}"
    local group_uuid="${open_group_info[${sanitizedName}_uuid]}"
  fi
  # TODO: use shipctl to compute this
  cmd_uuid=$(cat /proc/sys/kernel/random/uuid)
  cmd_start_timestamp=`date +"%s"`
  echo "__SH__CMD__START__|{\"type\":\"cmd\",\"sequenceNumber\":\"$cmd_start_timestamp\",\"id\":\"$cmd_uuid\",\"parentConsoleId\":\"$group_uuid\"}|$cmd"

  export current_cmd=$cmd
  export current_cmd_uuid=$cmd_uuid

  trap on_error ERR

  if [ "$retry_cmd" == "true" ]; then
    eval retry_command "$cmd"
    cmd_status=$?
  else
    eval "$cmd"
    cmd_status=$?
  fi

  unset current_cmd
  unset current_cmd_uuid

  if [ "$2" ]; then
    echo $2;
  fi

  cmd_end_timestamp=`date +"%s"`
  # If cmd output has no newline at end, marker parsing
  # would break. Hence force a newline before the marker.
  echo ""
  local cmd_first_line=$(printf "$cmd" | head -n 1)
  echo "__SH__CMD__END__|{\"type\":\"cmd\",\"sequenceNumber\":\"$cmd_start_timestamp\",\"id\":\"$cmd_uuid\",\"exitcode\":\"$cmd_status\"}|$cmd_first_line"

  trap before_exit EXIT
  if [ "$cmd_status" != 0 ]; then
    is_success=false
    return $cmd_status;
  fi
  return $cmd_status
}

on_error() {
  exit $?
}

before_exit() {
  return_code=$?
  exit_code=1;
  if [ $return_code -eq 0 ]; then
    is_success=true
    exit_code=0
  else
    is_success=false
    if [ "${#open_group_list[@]}" -gt 0 ]; then
      last_element="${open_group_list[-1]}"
       if [ "$last_element" == "Processing_required_resources" ]; then
         exit_code=199
       else
         exit_code=$return_code
       fi
    else
      exit_code=$return_code
    fi
  fi

  # Flush any remaining console
  echo $1
  echo $2

  if [ -n "$current_cmd_uuid" ]; then
    current_timestamp=`date +"%s"`
    echo "__SH__CMD__END__|{\"type\":\"cmd\",\"sequenceNumber\":\"$current_timestamp\",\"id\":\"$current_cmd_uuid\",\"exitcode\":\"$exit_code\"}|$current_cmd"
  fi

  # before going into the final handlers, close any open groups.
  # any non-root group that is still opened should be closed with a failed status.
  # do not close the root group here
  while [ "${#open_group_list[@]}" -gt 1 ]; do
    last_element="${open_group_list[-1]}"
    open_group_info[${last_element}_status]=1
    stop_group
  done
  if [ -z $skip_before_exit_methods ]; then
    skip_before_exit_methods=false
  fi

  if [ "$is_success" == true ]; then
    # "onSuccess" is only defined for the last task, so execute "onComplete" only
    # if this is the last task.
    # running onComplete and onSuccess inside a subshell to handle the scenario of
    # exit 0/exit 1 in these sections not failing the build
    subshell_exit_code=0
    (
      if [ "$(type -t onSuccess)" == "function" ] && ! $skip_before_exit_methods; then
        execute_command "onSuccess" || true
      fi

      if [ "$(type -t onComplete)" == "function" ] && ! $skip_before_exit_methods; then
        execute_command "onComplete" || true
      fi
    # subshell_exit_code will be set to 1 only when there is a exit 1 command in
    # the onSuccess & onFailure sections. exit 1 in these sections, is
    # considered as failure
    ) || subshell_exit_code=1

    if [ "${#open_group_list[@]}" -gt 0 ]; then
      last_element="${open_group_list[-1]}"
      open_group_info[${last_element}_status]="$subshell_exit_code"
      stop_group
    fi

    if [ "$(type -t output)" == "function" ] && ! $skip_before_exit_methods; then
      start_group "Processing outputs" true
      # unsetting -e flag so that the script doesn't exit on error
      set +e
      # setting -o errtrace so that ERR trap gets called inside functions
      set -o errtrace
      # unsetting the error trap in this shell so that if the subshell errors
      # out, the main shell doesn't run the ERR trap function
      trap "" ERR
      # run output function inside a subshell
      ( output )
      subshell_exit_code=$?
      # reset -e flag
      set -e
      # unset the errtrace flag
      set +o errtrace
      # add the ERR trap
      trap on_error ERR
      last_element="Processing_outputs"
      open_group_info[${last_element}_status]=$subshell_exit_code
      stop_group
    fi

    if [ $subshell_exit_code -eq 0 ]; then
      echo "__SH__SCRIPT_END_SUCCESS__";
    else
      echo "__SH__SCRIPT_END_FAILURE__|199";
    fi
  else
    # running onComplete and onFailure inside a subshell to handle the scenario of
    # exit 0/exit 1 in these sections not failing the build
    (
      if [ "$(type -t onFailure)" == "function" ] && ! $skip_before_exit_methods; then
        execute_command "onFailure" || true
      fi

      if [ "$(type -t onComplete)" == "function" ] && ! $skip_before_exit_methods; then
        execute_command "onComplete" || true
      fi
    # adding || true so that the script doesn't exit when onFailure/onComplete
    # section has exit 1. if the script exits the group will not be
    # closed correctly.
    ) || true

    if [ "${#open_group_list[@]}" -gt 0 ]; then
      last_element="${open_group_list[-1]}"
      open_group_info[${last_element}_status]="$exit_code"
      stop_group
    fi

    echo "__SH__SCRIPT_END_FAILURE__|$exit_code";
  fi
}

trap before_exit EXIT

export skip_before_exit_methods=false

if [ -z "$HOME" ]; then
  export HOME=$(echo ~)
fi
